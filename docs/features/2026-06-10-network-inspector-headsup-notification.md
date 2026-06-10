# 功能規格：Network Inspector 通知改為 Heads-up 橫幅

- **日期**：2026-06-10
- **狀態**：STAGE 0a — 待確認
- **前置功能**：`docs/features/2026-06-10-network-inspector-enhancement.md`（US-3 Notification，已於 PR #6 合併至 main）

---

## 1. 背景與動機（Why）

PR #6 已交付網路通知功能（US-3）：啟用 `showNetworkNotification: true` 後，每筆截取到的 API 呼叫會更新一則常駐系統通知。但目前的通知是「靜默」的：

- Android channel importance 為 `Importance.low`、priority 為 `Priority.low`——通知只會默默躺在通知列，**不會以 heads-up 橫幅浮出**，使用者必須手動下拉通知列才看得到。
- `onlyAlertOnce: true`——即使提高 importance，也只有第一次顯示會提醒，後續更新一律靜默。

使用者期望：**截取到 API 呼叫時，通知以 heads-up（Android 浮動橫幅）形式跳出**，讓開發者在不打開 dashboard、不下拉通知列的情況下，即時看到 API 活動。

### 現況關鍵檔案

| 檔案 | 角色 | 現值 |
|---|---|---|
| `lib/src/notifications/network_notifier.dart` | 通知建立與更新 | channel `flutter_inspector_network`、`Importance.low`、`Priority.low`、`ongoing: true`、`onlyAlertOnce: true`、iOS/macOS `presentSound: false` |
| `lib/src/core/flutter_inspector_impl.dart` | 觸發時機 | `_registry.network.onAdd` → 每筆截取呼叫 `showOrUpdate(entry, total)` |
| `test/notifications/network_notifier_test.dart` | 既有測試 | 驗證 init / show / cancel 行為 |

## 2. 範圍（Scope）

### In Scope

1. **Android heads-up 化**：通知 channel/notification 的 importance 與 priority 提升至可觸發 heads-up 的等級，使新截取的 API 呼叫能以浮動橫幅形式跳出。
2. **重複提醒（re-alert）**：不再只有第一次顯示會提醒——新的 API 呼叫應能再次觸發 heads-up（受節流規範約束，見下）。
3. **節流（throttling）**：高頻 API 呼叫不可造成通知轟炸。節流期間內的呼叫仍**靜默更新**通知內容（最新呼叫 + 累計數不漏），只是不重複彈出橫幅。
4. **Channel 升級遷移**：Android notification channel 的 importance 在建立後即不可由 App 變更。曾安裝舊版（channel 已以 low importance 建立）的裝置升級後，heads-up 仍須生效。
5. **iOS/macOS 對應行為**：iOS 沒有 heads-up 概念；前景 banner 呈現由系統權限與 presentation options 決定。本功能須確保 iOS 端在權限允許下，前景時通知以 banner 呈現（與 Android heads-up 的對應體驗），且維持無聲。

### Out of Scope（Non-goals）

- 不改變通知的**啟用方式與預設值**：仍由 `FlutterInspector(showNetworkNotification: true)` 明確啟用，預設關閉。
- 不改變通知的**內容格式**（title：`Network · N calls`；body：`[method] url · status`）。
- 不改變**單一通知更新模型**：仍是同一則通知持續更新，不會每筆呼叫各產生一則通知。
- 不改變**點擊行為**：點擊通知開啟 dashboard Network tab（US-3 既有行為）。
- 不新增使用者可調的節流參數 API（先採固定預設值；若日後有需求再開放）。
- 不處理系統層級的抑制因素：Do Not Disturb、全螢幕模式、使用者手動在系統設定將 channel 降級——這些由 OS 決定，套件不對抗。
- 不新增聲音／震動提醒（debug 工具以低干擾為原則，heads-up 視覺浮出即可）。

## 3. 使用者故事與驗收條件

### US-1：Android heads-up 橫幅

> 身為開發者，在 Android 裝置上啟用網路通知後，當 App 截取到 API 呼叫時，我要看到通知以 heads-up 橫幅從畫面頂部浮出，不必下拉通知列。

**驗收條件：**

- [ ] Android 上（已授權通知、無 DND 干擾），第一筆被截取的 API 呼叫使通知以 heads-up 橫幅浮出。
- [ ] 通知 channel importance 為 HIGH（或以上）、notification priority 為 high，滿足 Android heads-up 顯示條件。
- [ ] heads-up 浮出時**不播放聲音**（維持低干擾）。
- [ ] 通知仍為單一常駐（ongoing）通知：橫幅消失後，通知保留在通知列並持續更新內容。
- [ ] 從含舊版（low importance channel）的安裝升級後，heads-up 行為同樣生效（channel 遷移成功）。
- [ ] 通知權限被拒時行為不變：安全降級為 no-op，不崩潰。

### US-2：後續呼叫的重複提醒與節流

> 身為開發者，後續的 API 呼叫也要能再次以 heads-up 提醒我；但當 App 高頻發出請求時，我不要被橫幅轟炸。

**驗收條件：**

- [ ] 距上次 heads-up 浮出超過節流窗口（預設 2 秒，定值，不開放設定）後的下一筆呼叫，再次觸發 heads-up 浮出。
- [ ] 節流窗口內的呼叫**靜默更新**通知內容：最新呼叫資訊與累計數正確反映，不彈橫幅、不出聲。
- [ ] 短時間內連續 N 筆呼叫（如 1 秒內 20 筆），heads-up 浮出次數不超過節流規則允許的次數（單元測試以注入時鐘或等效方式驗證 alert/silent 判定邏輯）。
- [ ] 節流只影響「是否提醒」，不影響「內容更新」——通知列中的內容永遠是最新狀態。

### US-3：iOS / macOS 對應行為

> 身為開發者，在 iOS 上我期望得到與 Android heads-up 對等的體驗：App 前景時通知以系統 banner 呈現（在權限允許下）。

**驗收條件：**

- [ ] iOS 上（已授權通知），App 前景時截取到 API 呼叫，通知以系統 banner 呈現；banner 的實際樣式與停留時間由 iOS 系統決定，套件不保證。
- [ ] iOS banner 呈現同樣受 US-2 的節流規則約束（節流窗口內靜默更新）。
- [ ] iOS/macOS 維持無聲（`presentSound: false` 行為不變）。
- [ ] iOS 通知權限被拒時，安全降級不崩潰（既有行為不變）。

## 4. 與既有通知行為的關係

| 面向 | 既有行為 | 本次 |
|---|---|---|
| 啟用方式 | `showNetworkNotification: true`，預設關閉 | **保留** |
| 通知模型 | 單一通知持續更新（不洗版） | **保留** |
| 通知內容 | 最新呼叫 + 累計數 | **保留** |
| 點擊開啟 Network tab | US-3（PR #6） | **保留** |
| 權限請求與安全降級 | init 時請求，失敗 no-op | **保留** |
| Android importance/priority | low / low（靜默） | **改變**：HIGH / high（heads-up） |
| 提醒頻率 | `onlyAlertOnce: true`（僅首次） | **改變**：可重複提醒 + 節流 |
| Android channel | `flutter_inspector_network`（low） | **改變**：需遷移至 HIGH importance channel（升級相容） |
| iOS 前景呈現 | 依套件預設 presentation options | **明確化**：前景 banner 呈現 + 節流 |
| 聲音 | 無聲 | **保留**（heads-up 亦無聲） |

## 5. 跨領域驗收

- [ ] `flutter analyze` 零 issue。
- [ ] `test/notifications/network_notifier_test.dart` 既有測試不退化；新增節流判定與 channel 遷移相關的單元測試。
- [ ] 對外公開 API 無破壞性變更（`showNetworkNotification` 簽名與語意不變）。
- [ ] README 中通知相關說明（若有）更新為 heads-up 行為描述。
- [ ] example app 可編譯並實機驗證 Android heads-up 行為。

## 6. 風險與待解

- **Android channel importance 不可變**：channel 一經建立，App 無法程式化提高其 importance。升級相容需以「刪除舊 channel 重建」或「啟用新 channel ID」處理（實作方式由 STAGE 0b 決定），規格層面的要求是第 3 節 US-1 的升級驗收條件。
- **heads-up 非保證行為**：Android 上 heads-up 是否實際浮出受 OEM 客製、省電模式、DND、使用者手動降級 channel 等影響；驗收以「標準 AOSP/Pixel 行為、權限允許、無 DND」為基準環境。
- **ongoing + heads-up 並存**：常駐通知搭配 heads-up 在部分 Android 版本上的浮出行為可能有差異，實機驗證需涵蓋（example app 驗證項）。
- **節流預設值（2 秒）**：為提案預設值，無實證資料；若確認階段使用者有不同偏好（更短／更長／首筆即足夠），以使用者決定為準。

---

## 確認

請確認以上功能規格（使用者故事、驗收條件、範圍邊界、與既有行為的關係）。確認後進入 **STAGE 0b** 產出實作計畫。
