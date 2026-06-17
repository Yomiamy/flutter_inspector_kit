# Feature: 修復 iOS 前景無法跳出網路通知 banner

- 日期：2026-06-17
- 類型：Bug fix（iOS 整合缺口）+ 文件 + 程式碼硬化

## What & Why

`FlutterInspector(showNetworkNotification: true)` 在 iOS 上、app 處於**前景**時，
即使有網路請求觸發 `NetworkNotifier.showOrUpdate()`，也不會跳出系統通知 banner。

### 根因（已由對抗式驗證確認，HIGH confidence）

iOS 只有在某個 `UNUserNotificationCenterDelegate.willPresentNotification` 回傳
`.banner` / `.alert` 時，才會在前景顯示本地通知。

- `flutter_local_notifications` v22 只透過 `addApplicationDelegate` 註冊，**自己不設** UN delegate。
- `FlutterAppDelegate` 有實作 `willPresentNotification`，但**不會把自己指派**為 active UN delegate。
- example app 的 `AppDelegate.swift` 也沒設 → **沒有任何人擁有 delegate** →
  `willPresentNotification` 從不被呼叫 → iOS 前景把每一個 banner 都壓掉，
  與 `presentBanner:true`、throttler、init race 全部無關。

對照證據：`flutter_local_notifications` 自己的 example `AppDelegate.swift` 明確設了
`UNUserNotificationCenter.current().delegate = self`，本專案 example 漏了這一行。

這是 **host-app 整合缺口**，不是 package 程式碼 bug。package 不含 iOS native code，
無法替下游 host app 設 delegate，因此「真正的修復」是文件指引（每個使用者都得自己做這步）。

## 使用者故事

- 作為使用 `flutter_inspector` 的開發者，當我開啟 `showNetworkNotification` 且 app 在前景時，
  我希望能看到網路通知 banner 提醒有 API 呼叫。
- 作為套件使用者，我希望 README 清楚告訴我 iOS 上必須做哪一步整合，否則通知靜默失效。

## 驗收條件

1. example app 的 `AppDelegate.swift` 設定 `UNUserNotificationCenter.current().delegate = self`。
2. README 有「Required iOS setup」段，說明 host app 必須在自己的 `AppDelegate` 設 UN delegate，
   否則 iOS 前景不顯示通知。
3. `flutter_inspector.dart` 的 init race 清除：`onAdd` 只在 `init()` resolve 後才掛上。
4. 既有的 `presentAlert: alert`（network_notifier_io.dart）一併納入。
5. `flutter test` 全綠；`flutter analyze` 無新增 warning。

## 範圍邊界

- **不改** `AlertThrottler`（2 秒節流是設計，已驗證非成因，且有單元測試保護）。
- **不改** `DarwinInitializationSettings()` 預設（已驗證會在 initialize 時請求權限，非成因）。
- **不改** `presentSound`（與 banner 無關）。
- 真機驗證（banner 實際顯示）由使用者在實體 iOS 裝置完成；模擬器通知不可靠。
