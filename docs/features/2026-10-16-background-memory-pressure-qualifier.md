# 功能規格：Android 切背景記憶體壓力修飾標籤（§Z1-5 / §P21 既有缺陷修正）

- **日期**：2026-10-16
- **來源**：`docs/brainstorm/2026-10-14-features-brainstorm.md` §Z1 第 5 項（既有缺陷 · §P21 在 Android 切背景即誤報）
- **關聯**：§P21 記憶體壓力事件（PR #155 已落地）
- **Effort**：trivial ｜ **排查價值**：⭐⭐⭐⭐

---

## 1. 使用者故事

> 作為一位在 Android 裝置上排查記憶體問題的開發者／QA，
> 我希望**切到背景觸發的記憶體壓力事件帶有狀態修飾（如 `(app hidden)`）**，
> 這樣我就能一眼分辨這是系統切背景時例行的資源修剪（`TRIM_MEMORY_UI_HIDDEN`），
> 還是前景運作時真正的 OOM/LMK 記憶體緊繃信號，避免被誤報干擾排查方向。

### 為什麼這件事需要修

PR #155 落地了 §P21，將 `WidgetsBindingObserver.didHaveMemoryPressure()` 納入混合時間軸作為 OOM/LMK 的前導警告（`LogLevel.warning`）。
然而 Android Flutter engine（`FlutterActivityAndFragmentDelegate.java:1067-1070`，SDK 3.47.1+）在 `level >= TRIM_MEMORY_RUNNING_LOW` 即廣播 memory pressure，而 App 切至背景觸發的 `TRIM_MEMORY_UI_HIDDEN` 數值亦在此範圍內。
同時 Google 已將現代 Android 上的 `onTrimMemory` 大部分 callback 棄用，只保留 `UI_HIDDEN` 與 `BACKGROUND`。
這導致現代 Android 上記錄到的記憶體壓力事件，絕大多數只是使用者按 Home 鍵切換到背景的正常行為。
若無生命週期狀態修飾，「OOM/LMK 唯一前導信號」的鑑別度在 Android 上會被嚴重稀釋。

---

## 2. 範圍邊界

### ✅ 做

- `LifecycleHandler.didHaveMemoryPressure()` 中檢查 `WidgetsBinding.instance.lifecycleState`
- 若當前生命週期狀態非 `resumed` 且非 `null`，訊息附上狀態修飾：`Memory pressure (app ${state.name})$suffix`
- 若當前狀態為 `resumed` 或 `null`，維持原訊息格式：`Memory pressure$suffix`
- 保持 `topPageLabel` 後綴於最末端：例如 `Memory pressure (app hidden) · HomePage (/home)`
- 修正 `lifecycle_handler.dart:66-67` 註解中關於 RSS 與 platform channel 的不精確陳述
- 補充與更新對應單元測試（包含所有 `AppLifecycleState` 狀態之斷言）

### ❌ 不做（明確排除）

| 排除項 | 理由 |
|:---|:---|
| 引入 Android Native Plugin / EventChannel | 違反本套件純 Dart 定位；切背景誤報以純 Dart 狀態讀取即可消除 |
| 引入 `dart:io` 的 `ProcessInfo.currentRss` | 破壞 Web 跨平台相容性且違背公開承諾 |
| 新增 `filterBackgroundMemoryPressure` 旗標 | 多一個 bool 旗標製造特殊情況；直接在訊息標註狀態即可滿足可讀性與真實性 |
| 將切背景時的記憶體壓力降級為 `LogLevel.info` | 仍為 OS 等級的 trim 回呼，維持 `LogLevel.warning` 讓使用者自訂過濾，不改變事件等級契約 |

---

## 3. 設計決策

**訊息格式設計**：
- 前景真壓力（`resumed` 或未獲取到狀態）：`Memory pressure` 或 `Memory pressure · HomePage (/home)`
- 切背景／非前景（如 `hidden`、`paused` 等）：`Memory pressure (app hidden)` 或 `Memory pressure (app hidden) · HomePage (/home)`

這樣做的好處：
1. **零 breaking change**：未改變任何公開介面與方法簽章。
2. **消滅特殊情況**：單純讀取 Flutter binding 既有的 `lifecycleState`，不增加額外狀態管理或儲存變數。
3. **消除誤解**：讀者在 Console 或日誌一眼看出此警告是在背景觸發，還是前景操作引發。

---

## 4. 驗收條件

| # | 條件 | 驗證方式 |
|:---:|:---|:---|
| 1 | 當 `lifecycleState` 為 `AppLifecycleState.resumed` 時，訊息為 `Memory pressure$suffix` | 單元測試斷言 |
| 2 | 當 `lifecycleState` 為 `null` 時，訊息維持 `Memory pressure$suffix`（防禦性處理） | 單元測試斷言 |
| 3 | 當 `lifecycleState` 為 `hidden` / `paused` / `inactive` / `detached` 時，訊息包含對應 `(app <state>)` 修飾 | 單元測試覆蓋非 resumed 狀態 |
| 4 | 當有 `topPageLabel` 時，修飾標籤置於 topPageLabel 之前（`Memory pressure (app <state>) · <page>`） | 單元測試斷言格式與順序 |
| 5 | `lifecycle_handler.dart` 註解精確陳述 RSS 與 native 邊界 | 代碼 review |
| 6 | 既有與新增測試全數通過（`flutter test`） | 指令執行驗證 |
| 7 | 靜態分析無新增警告（`flutter analyze`） | 指令執行驗證 |
