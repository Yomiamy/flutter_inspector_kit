# 實作計畫：修復 iOS 前景無法跳出網路通知 banner

- 對應規格：docs/features/2026-06-17-ios-foreground-notification.md
- 日期：2026-06-17

## 資料結構 / 機制

無新資料結構。三處異動皆為「補上 iOS 通知鏈缺口」與「修正 callback 掛載時序」。

## 任務拆分

各任務寫入路徑互不重疊，但數量少、且 C 涉及測試驗證，採**序列**執行較穩。
逐任務複雜度標註供 model 分級。

### Task 1 — Fix A：example AppDelegate 設定 UN delegate
- **複雜度**：機械性（單檔、規格完整）→ 快/便宜 model
- **寫入**：`example/ios/Runner/AppDelegate.swift`
- **內容**：
  - `import UserNotifications`
  - 在 `didFinishLaunchingWithOptions` 內、`super` 呼叫前：
    ```swift
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self as UNUserNotificationCenterDelegate
    }
    ```
  - `FlutterAppDelegate` 已 conform `UNUserNotificationCenterDelegate` 並轉發，無需額外 protocol/method。

### Task 2 — Fix B：README 加「Required iOS setup」
- **複雜度**：機械性（文件）→ 快/便宜 model
- **寫入**：`README.md`（找通知相關段落，或在 iOS 設定／Getting Started 附近新增）
- **內容**：說明使用 `showNetworkNotification` 的 host app 必須在 `AppDelegate` 設
  `UNUserNotificationCenter.current().delegate = self`，附上對齊 example 的程式碼片段，
  並註明沒設的話 iOS 前景不顯示通知（背景仍會進通知中心）。

### Task 3 — Fix C：清除 init race + 納入既有 presentAlert
- **複雜度**：整合（觸及核心建構子時序，需確認測試）→ 標準 model
- **寫入**：`lib/src/core/flutter_inspector.dart`（line 41-47 區段）
- **內容**：
  ```dart
  _notifier = notifier ?? NetworkNotifier(onTap: _openNetworkFromNotification);
  _notifier!.init().then((_) {
    _registry.network.onAdd = (entry, total) {
      _notifier!.showOrUpdate(entry, total);
    };
  });
  ```
  - 既有未 commit 的 `presentAlert: alert`（network_notifier_io.dart）保留，一併納入。
  - 注意：`flutter_inspector.dart` 需 `import 'dart:async'` 若用到 `unawaited`；
    用 `.then()` 不需要額外 import，優先用 `.then()`。

## 驗證

- `flutter analyze`（無新增 warning）
- `flutter test`（全綠，特別是 test/notifications/network_notifier_test.dart）
- example app 編譯確認（`flutter build ios --no-codesign` 或至少 analyze）

## 不做（範圍邊界）

- 不改 AlertThrottler、DarwinInitializationSettings()、presentSound。
- 真機 banner 顯示由使用者在實體裝置驗證。
