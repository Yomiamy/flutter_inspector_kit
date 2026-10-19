# 功能規格：Android 切背景記憶體壓力誤報過濾（§Z1-5 / §P21 既有缺陷修正）

- **日期**：2026-10-16（2026-10-19 決策變更：由「附加狀態修飾」改為「非前景直接丟棄」）
- **來源**：`docs/brainstorm/2026-10-14-features-brainstorm.md` §Z1 第 5 項（既有缺陷 · §P21 在 Android 切背景即誤報）
- **關聯**：§P21 記憶體壓力事件（PR #155 已落地）
- **Effort**：trivial ｜ **排查價值**：⭐⭐⭐⭐

---

## 1. 使用者故事

> 作為一位在 Android 裝置上排查記憶體問題的開發者／QA，
> 我希望**切到背景時系統例行送出的記憶體壓力事件根本不進時間軸**，
> 這樣 Console 的 warning 過濾與 Dashboard badge 只剩前景運作時真正的 OOM/LMK 前導信號，不必逐筆判讀誤報。

### 為什麼這件事需要修

PR #155 落地了 §P21，將 `WidgetsBindingObserver.didHaveMemoryPressure()` 納入混合時間軸作為 OOM/LMK 的前導警告（`LogLevel.warning`）。
然而 Android Flutter engine（`FlutterActivityAndFragmentDelegate.java:1067-1070`，SDK 3.47.1+）在 `level >= TRIM_MEMORY_RUNNING_LOW` 即廣播 memory pressure，而 App 切至背景觸發的 `TRIM_MEMORY_UI_HIDDEN` 數值亦在此範圍內。
同時 Google 已將現代 Android 上的 `onTrimMemory` 大部分 callback 棄用，只保留 `UI_HIDDEN` 與 `BACKGROUND`。
這導致現代 Android 上記錄到的記憶體壓力事件，絕大多數只是使用者按 Home 鍵切換到背景的正常行為。

### 為什麼是丟棄而非加修飾（2026-10-19 決策變更）

原方案在訊息附加 `(app <state>)`，但事件仍是 `LogLevel.warning`：誤報照樣進 warning 過濾與 badge 計數，噪音沒少，只是把判讀成本轉給讀者。
背景時的事件也沒有排查價值——App 若因此被殺，記憶體內的時間軸一起消失；沒被殺，使用者端什麼都沒發生。
整個移除 §P21 亦不可行：iOS 的 `didReceiveMemoryWarning` 在前景時是真訊號，移除即破壞既有行為。

---

## 2. 範圍邊界

### ✅ 做

- `LifecycleHandler.didHaveMemoryPressure()` 開頭檢查 `WidgetsBinding.instance.lifecycleState`
- 若狀態非 `null` 且非 `resumed`：直接 return，不記錄
- 若狀態為 `resumed` 或 `null`：維持原訊息格式 `Memory pressure$suffix`
- 修正 `lifecycle_handler.dart` 註解中關於 RSS 與 platform channel 的不精確陳述
- 更新對應單元測試（涵蓋所有非 `resumed` 狀態）

### ❌ 不做（明確排除）

| 排除項 | 理由 |
|:---|:---|
| 引入 Android Native Plugin / EventChannel | 違反本套件純 Dart 定位；切背景誤報以純 Dart 狀態讀取即可消除 |
| 引入 `dart:io` 的 `ProcessInfo.currentRss` | 破壞 Web 跨平台相容性且違背公開承諾 |
| 新增 `filterBackgroundMemoryPressure` 旗標 | 背景事件無排查價值，沒有人需要把它開回來；多一個 bool 只是製造特殊情況 |
| 附加 `(app <state>)` 修飾或降級為 `LogLevel.info` | 事件仍留在時間軸，噪音不減；丟棄才是消滅特殊情況 |
| 整個移除 `didHaveMemoryPressure` 記錄 | iOS 前景記憶體警告是真訊號，移除會破壞既有行為 |

---

## 3. 驗收條件

| # | 條件 | 驗證方式 |
|:---:|:---|:---|
| 1 | 當 `lifecycleState` 為 `AppLifecycleState.resumed` 時，訊息為 `Memory pressure$suffix` | 單元測試斷言 |
| 2 | 當 `lifecycleState` 為 `null` 時，照常記錄 `Memory pressure$suffix`（狀態未知時寧可多記） | 程式碼 review |
| 3 | 當 `lifecycleState` 為 `hidden` / `paused` / `inactive` / `detached` 時，不產生任何 log | 單元測試覆蓋非 resumed 狀態 |
| 4 | `lifecycle_handler.dart` 註解精確陳述 RSS 與 native 邊界，並說明丟棄理由 | 程式碼 review |
| 5 | 既有與新增測試全數通過（`flutter test`） | 指令執行驗證 |
| 6 | 靜態分析無新增警告（`flutter analyze`） | 指令執行驗證 |

### 前提（✅ 2026-10-19 已於 Android 實機確認）

Android 送出 `TRIM_MEMORY_UI_HIDDEN` 時，Flutter 的 `lifecycleState` 已離開 `resumed`。實機觀察為 `onStop` 先到、之後才呼叫 `didHaveMemoryPressure()`，guard 可擋下切背景的事件。

### 手動觸發方法

```bash
adb shell am send-trim-memory com.example.example RUNNING_CRITICAL
```

`am send-trim-memory` 走 `ActivityManagerService.setProcessMemoryTrimLevel()`，有兩條限制（AOSP 原始碼確認）：

- **level 只能遞增**：每個 process 記錄上次送出的 level，同級或更低一律拒絕（`Unable to set a higher trim level than current level`），且無任何路徑重置——要重測同一 level 只能重啟 process。
- **前景不收背景級**：`TRIM_MEMORY_UI_HIDDEN`(20) 以上的 level 對前景 process 一律拒絕（`Unable to set a background trim level on a foreground process`）。

Flutter engine 僅在 `level >= TRIM_MEMORY_RUNNING_LOW`(10) 時轉送 memory pressure，因此單一 process 生命週期內可測：

| App 狀態 | 依序送出 | 預期 |
|:---|:---|:---|
| 前景 | `RUNNING_LOW` → `RUNNING_CRITICAL` | 各記一筆 `Memory pressure`，共 2 筆 |
| 背景 | `HIDDEN` → `BACKGROUND` → `MODERATE` → `COMPLETE` | 全數被 guard 丟棄 |

快速重啟 process：`adb shell am force-stop com.example.example && adb shell monkey -p com.example.example -c android.intent.category.LAUNCHER 1`（`flutter run` 的 debug session 會中斷，需重跑或 `flutter attach`）。
