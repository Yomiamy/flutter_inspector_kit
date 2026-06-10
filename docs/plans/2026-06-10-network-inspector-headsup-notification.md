# 實作計畫：Network Inspector 通知改為 Heads-up 橫幅

- **日期**：2026-06-10
- **功能規格**：`docs/features/2026-06-10-network-inspector-headsup-notification.md`
- **狀態**：STAGE 0b — 待確認
- **已確認的開放問題**：節流固定 5 秒（不開 API）｜接受 channel 換 ID／刪除重建的副作用｜驗收以 AOSP/Pixel 為基準

---

## 1. 設計總覽

核心策略：**節流判定是純邏輯，先抽成可注入時鐘的獨立物件做扎實；通知 details 抽成可斷言的純 builder；平台副作用（channel 遷移、實際彈出）收斂在 `NetworkNotifier` 內，靠 example app 實機驗證**。觸發路徑（`flutter_inspector_impl.dart` 的 `onAdd → showOrUpdate`）**完全不動**——節流是 notifier 的內部事務，呼叫端不需要知道。

### 1.1 資料結構決策：節流狀態

```
AlertThrottler（lib/src/notifications/alert_throttler.dart，新檔）
├── final Duration window          // 固定 const Duration(seconds: 5)
├── final DateTime Function() _now // 時鐘注入，預設 DateTime.now
├── DateTime? _lastAlertAt         // 唯一的可變狀態
└── bool shouldAlert()             // 判定 + 記錄一次完成
```

- `shouldAlert()` 語意：`_lastAlertAt == null`（首筆）或 `now - _lastAlertAt >= window` 時回傳 `true` **並更新 `_lastAlertAt`**；否則回傳 `false` 且不動狀態。判定與記錄合一，呼叫端不可能拿到 `true` 卻忘記記錄——消滅一個錯誤類別。
- **時鐘注入**（`DateTime Function()`）是可測試性的關鍵：單元測試用假時鐘推進時間，驗證「1 秒內 20 筆只有 1 次 alert」「跨 5 秒窗口後再次 alert」，零 sleep、零 flaky。
- 狀態放在 `AlertThrottler` 內、`NetworkNotifier` 持有一個實例（建構子可注入供測試）。不放在 `NetworkNotifier` 散欄位，因為純邏輯獨立成型別後可 100% 單測——既有測試已註明此套件採 mock-free 風格、plugin 鏈在單測中無法初始化，**把可測的邏輯從不可測的 plugin 呼叫中剝離**是唯一能兼顧的設計。

### 1.2 Channel 遷移策略：**換新 channel ID**（不採刪除重建同 ID）

| 選項 | 結果 |
|---|---|
| A. 刪除舊 channel 後以**同 ID** 重建 HIGH | ❌ 不可行。Android 官方行為：同 ID 重建已刪除的 channel，系統會**還原舊設定**（含 low importance）——刪了等於沒刪 |
| B. 啟用**新 channel ID**，init 時順手刪除舊 channel | ✅ 採用。新 ID 保證以 HIGH importance 全新建立；刪舊 channel 避免系統設定頁殘留孤兒 channel |

- 新 channel ID：`flutter_inspector_network_v2`（name 維持 `Network Inspector`，使用者在系統設定看到的名稱不變）。
- `init()` 內透過 `resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.deleteNotificationChannel(...)` 刪除舊 ID `flutter_inspector_network`，包在既有的 try/catch 安全降級慣例內（非 Android 平台 resolve 回 null，自然 no-op）。
- 新 channel 不需顯式 create——`flutter_local_notifications` 在 `show()` 時依 `AndroidNotificationDetails` 自動建立。
- 已接受的副作用：使用者若曾在系統設定手動調整舊 channel，設定不會帶到新 channel（新 channel 以 HIGH 全新開始）；Android 系統設定可能顯示「已刪除的類別」計數。詳見第 6 節。

### 1.3 Heads-up 觸發機制：alert / silent 雙態 details

heads-up 條件 = channel importance **HIGH** + notification priority **high**（pre-O 相容）。重複提醒 = 移除恆定的 `onlyAlertOnce: true`，改為**每次 show 依節流判定動態決定**：

| 參數 | alert（彈橫幅） | silent（靜默更新） |
|---|---|---|
| Android `importance` / `priority` | `Importance.high` / `Priority.high` | 同左（channel 層級不變，靜默靠下列參數） |
| Android `onlyAlertOnce` | `false` → 再次 show 同 id 會重新 alert（heads-up） | `true` → 更新內容但不重新 alert |
| Android `silent` | `false` | `true`（雙保險：`Notification.setSilent`，明確抑制 heads-up/聲音/震動） |
| Android `ongoing` / `showWhen` | `true` / `false`（不變） | 同左 |
| Darwin `presentBanner` | `true`（前景 banner，對應 Android heads-up） | `false`（不彈 banner） |
| Darwin `presentList` | `true`（仍進通知中心） | `true` |
| Darwin `presentSound` | `false`（維持無聲，US-3） | `false` |

- 抽成 `@visibleForTesting static NotificationDetails buildDetails({required bool alert})`——純函式、無平台呼叫，單元測試可直接斷言每個欄位，符合 mock-free 風格（不需要 mock plugin 就能驗證 details 正確性）。
- `showOrUpdate` 流程變為：`final alert = _throttler.shouldAlert();` → `_plugin.show(..., notificationDetails: buildDetails(alert: alert))`。內容（title/body）**永遠更新**，節流只切換 details 形態——「節流只影響是否提醒、不影響內容更新」由結構保證，沒有任何 if 會跳過 show。
- 無聲驗收（US-1「heads-up 不播聲音」）：新 channel 建立時 `playSound: false`（`AndroidNotificationDetails` 的 channel 層參數），heads-up 視覺浮出但靜音。

## 2. 檔案異動清單

| 檔案 | 動作 | 任務 |
|------|------|------|
| `lib/src/notifications/alert_throttler.dart` | **新增**：節流判定純邏輯（時鐘注入） | T1 |
| `test/notifications/alert_throttler_test.dart` | **新增**：節流單元測試 | T1 |
| `lib/src/notifications/network_notifier.dart` | 改：新 channel ID + `buildDetails(alert:)` 雙態 builder + `showOrUpdate` 接節流 + `init()` 刪舊 channel + 建構子注入 throttler/clock | T2, T3 |
| `test/notifications/network_notifier_test.dart` | 改：保留既有 3 個降級測試不動；新增 `buildDetails` 斷言群組 | T2 |
| `README.md` | 改：Live notification 段落補 heads-up 行為描述 | T4 |
| `CHANGELOG.md` | 改：記錄行為變更（heads-up + channel 遷移） | T4 |

不動的檔案（明確列出以防 scope creep）：`lib/src/core/flutter_inspector_impl.dart`（觸發路徑不變）、`lib/src/inspectors/network_inspector.dart`、`example/lib/main.dart`（已示範 `showNetworkNotification: true`，僅實機驗證）、`pubspec.yaml`（`flutter_local_notifications: ^22.0.0` 已含所需 API，不加依賴）。

## 3. 任務拆分（TDD：每任務先寫測試）

> 分級對齊 implementer 的 model 策略：🟢 機械性=快/便宜｜🟡 整合=標準｜🔴 設計判斷/跨層=最強。

### T1 — `AlertThrottler` 純邏輯 🟢 機械性
- **寫入 scope**：`lib/src/notifications/alert_throttler.dart`、`test/notifications/alert_throttler_test.dart`
- **TDD 順序**：先寫測試（紅）→ 實作（綠）：
  1. 首次 `shouldAlert()` 回傳 `true`。
  2. 緊接著（時鐘未推進）第二次回傳 `false`。
  3. 假時鐘推進 4.999 秒 → `false`；推進至 ≥5 秒 → `true`。
  4. 「1 秒內 20 筆」連續呼叫只有第 1 筆 `true`（US-2 驗收第 3 條）。
  5. `true` 之後窗口重新起算（連續兩次跨窗 alert 間隔 ≥ window）。
- **實作**：第 1.1 節的結構，`window` 預設 `const Duration(seconds: 5)`，建構子允許覆寫 window 與 now（僅供測試，不對外 export）。
- **驗收**：上述測試全綠；`flutter analyze` 零 issue。對應規格 US-2 驗收 1、3。

### T2 — `buildDetails` 雙態 details builder 🟡 標準
- **寫入 scope**：`lib/src/notifications/network_notifier.dart`、`test/notifications/network_notifier_test.dart`
- **TDD 順序**：先在既有測試檔新增 `group('buildDetails')`（紅）→ 實作（綠）：
  - `alert: true`：Android `importance == Importance.high`、`priority == Priority.high`、`onlyAlertOnce == false`、`silent == false`、`ongoing == true`、`playSound == false`、channelId == `flutter_inspector_network_v2`；Darwin `presentBanner == true`、`presentList == true`、`presentSound == false`。
  - `alert: false`：`onlyAlertOnce == true`、`silent == true`、Darwin `presentBanner == false`；其餘欄位與 alert 態相同（importance/priority/ongoing/channelId 不變）。
- **實作**：把 `showOrUpdate` 內的 const details 抽成 `@visibleForTesting static NotificationDetails buildDetails({required bool alert})`；此任務 `showOrUpdate` 先以 `buildDetails(alert: true)` 接上（節流接線留給 T3）。
- **驗收**：新測試群組全綠；既有 3 個降級測試（unavailable no-op）不退化。對應規格 US-1 驗收 2、3，US-3 驗收 1、3。

### T3 — `showOrUpdate` 接節流 + `init()` channel 遷移 🟡 標準
- **寫入 scope**：`lib/src/notifications/network_notifier.dart`、`test/notifications/network_notifier_test.dart`
- **依賴**：T1（throttler 型別）、T2（builder 就位）；與 T2 同檔 → **序列**。
- **實作**：
  1. 建構子新增 `AlertThrottler? throttler`（測試注入用），預設 `AlertThrottler()`。
  2. `showOrUpdate`：`final alert = _throttler.shouldAlert();` → `buildDetails(alert: alert)`。content（title/body）路徑不變。
  3. `init()`：在 `initialize` 成功後、`_requestPermission()` 前，呼叫 Android 實作的 `deleteNotificationChannel('flutter_inspector_network')`，包獨立 try/catch（與 `_requestPermission` 同慣例：失敗只 debugPrint，不影響 `_available`）。舊 channel ID 以 local const（如 `_legacyChannelId`）保留，註明用途。
- **測試**：unavailable 時 `showOrUpdate` 不得觸碰 throttler 狀態（先 guard 再判定——避免權限拒絕時空耗節流窗口）；既有降級測試維持綠。channel 刪除屬 plugin 平台呼叫，依本套件 mock-free 慣例不在單測 mock，列入 T4 實機驗證。
- **驗收**：`flutter analyze` 零 issue、全測試綠。對應規格 US-2 驗收 2、4，US-1 驗收 5（遷移碼就位，行為由 T4 實機驗證）。

### T4 — 文件 + 實機驗證 🟢 機械性
- **寫入 scope**：`README.md`、`CHANGELOG.md`
- **README**：Live notification 段落補述——通知以 heads-up 橫幅浮出（Android）/ 前景 banner（iOS）、5 秒節流、無聲、升級自動遷移 channel（使用者對舊 channel 的手動設定不保留）。
- **CHANGELOG**：記錄行為變更與 channel ID 遷移。
- **實機驗證清單**（example app，AOSP/Pixel 基準，對應規格第 5 節）：
  - [ ] 全新安裝：第一筆 API 呼叫 heads-up 浮出、無聲、橫幅消失後通知常駐。
  - [ ] 升級情境：先裝含舊 channel（low）的版本 → 升級 → heads-up 生效；系統設定中舊 channel 消失。
  - [ ] 連續高頻請求（example 的 burst 按鈕或連點）：5 秒窗口內僅靜默更新，內容/計數正確；跨窗口再次浮出。
  - [ ] 通知權限拒絕：no-op 不崩潰。
  - [ ] iOS（如有裝置）：前景 banner 浮現、無聲、節流生效。
- **驗收**：`flutter analyze` 零 issue、`flutter test` 全綠、example 可編譯。對應規格第 5 節跨領域驗收與 US-1 驗收 1、4、5、6。

## 4. 執行順序與並行判斷

```
T1（throttler，獨立新檔）──┐
T2（buildDetails）─────────┤ T1 ∥ T2 檔案 scope 不重疊 → 🟢 可並行
                           ↓ 兩者完成後
T3（接線 + 遷移）           ← 與 T2 同檔（network_notifier.dart）→ 必須序列
                           ↓
T4（docs + 實機驗證）
```

- 可選執行方式：**subagent-driven**（同 session 序列派工，T1+T2 可同批並行 subagent）或 **parallel session**（T1、T2 開兩個 worktree session，T3 起合流序列）。本功能規模小（4 任務、單一熱點檔），**建議 subagent-driven 序列即可**，並行收益有限。

## 5. 測試策略

- **既有測試不退化**：`network_notifier_test.dart` 的 3 個降級測試（unavailable → no-op）一行不改、必須維持綠；plugin 鏈不可單測的註解慣例延續。
- **新增**：
  - `alert_throttler_test.dart`：假時鐘驅動的節流判定（首筆 alert、窗口內 silent、跨窗 re-alert、burst 20 筆僅 1 alert、窗口重起算）。
  - `network_notifier_test.dart` 新 group：`buildDetails(alert: true/false)` 逐欄位斷言（importance/priority/onlyAlertOnce/silent/ongoing/playSound/channelId/presentBanner/presentList/presentSound）。
- **不單測**（mock-free 慣例，由 T4 實機驗證）：plugin `initialize`/`show`/`deleteNotificationChannel` 的實際平台行為、heads-up 視覺浮出。
- 每任務結束跑 `flutter analyze` + `flutter test`。

## 6. 風險與回退

| 風險 | 說明 | 緩解 / 回退 |
|------|------|------|
| 舊 channel 刪除的副作用 | 使用者曾手動調整舊 channel（如關閉）的設定不保留；新 channel 以 HIGH 全新建立。Android 系統設定可能顯示「已刪除的類別」計數 | 已於規格確認接受。README/CHANGELOG 明示。debug 工具、通知預設關閉，實際受影響面極小 |
| 同 ID 重建還原舊設定 | 若誤用「刪除後同 ID 重建」，importance 會被系統還原為 low | 設計上直接採新 ID（1.2 節），消滅此風險 |
| ongoing + heads-up 並存差異 | 部分 Android 版本/OEM 上常駐通知的 heads-up 浮出行為可能不同 | 驗收基準已限定 AOSP/Pixel；T4 實機清單涵蓋；OEM 差異屬規格 out-of-scope |
| heads-up 非保證行為 | DND、省電、使用者手動降級 channel 可抑制 | 規格 out-of-scope，OS 決定，套件不對抗 |
| `silent` 參數與 `onlyAlertOnce` 疊加 | 兩者同時設定理論上冗餘 | 雙保險設計：任一參數在特定 OS 版本失效時另一個仍生效；builder 單測鎖定兩者狀態 |
| 回退路徑 | 若實機發現 heads-up 造成不可接受的干擾 | 整包行為集中在 `buildDetails` + `AlertThrottler`：revert 單一 commit 即回到 low/low 靜默行為，公開 API 零變更 |

---

## 確認

請確認此實作計畫（4 個任務、T1∥T2 可並行、channel 換新 ID `flutter_inspector_network_v2`、節流以時鐘注入的 `AlertThrottler` 實作）。確認後進入 **STAGE 1** 建立 Issue + 分支。
