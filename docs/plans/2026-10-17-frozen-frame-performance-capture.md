# 實作計畫：掉幀／凍結幀效能捕捉（§P20 / capturePerformance）

- **日期**：2026-10-17
- **規格**：`docs/features/2026-10-17-frozen-frame-performance-capture.md`
- **Effort**：low~medium
- **總任務數**：3

---

## 1. 資料結構與核心設計 (Linus 模式分解)

### 資料結構
**不新增任何儲存實體與緩衝區。**
- 零新增 `JankEntry`、零新增 `JankInspector`、零新增 `RingBuffer`、零新增 `TimelineSource`（恪守 Anti-Feature #6）。
- 凍結幀本質上是系統效能的 Warning 信號，直接落入既有 `LogEntry`（`LogLevel.warning`），與其他日誌、生命週期事件、網路請求一同在 `mergedTimeline` 排序。
- 載荷置於既有 `LogEntry.data`：
  - `totalSpanMs`: `int` (總跨度毫秒)
  - `vsyncOverheadMs`: `int` (UI 執行緒前置排隊/同步阻塞耗時)
  - `buildDurationMs`: `int` (UI build 耗時)
  - `rasterDurationMs`: `int` (Raster 繪製耗時)
  - `frameCount`: `int?` (僅在連續凍結合併時提供)

### 連續超標合併 (Streak Coalescing)
- 避免重度連續掉幀（如急速滾動龐大列表）塞滿 `RingBuffer(500)`。
- **無背景 Timer**：利用幀本身的單調時鐘（`timestampInMicroseconds`）與批次迴圈判斷：
  - 若連續幀之 `totalSpan >= frozenFrameThreshold`，累計總耗時與幀數。
  - 當遇到正常幀（`< threshold`）、或者幀間間隔過大（大於常規幀間隔）、或者呼叫 `detach()` 時，將累積的 cluster 立即 flush 成一筆 Warning log。
  - Log 的時間戳採用 cluster 中**第一幀**之時間戳，保證時間軸因果排序絕對精確。

### 時鐘域與平台相容性
- Native 平台：優先從 `FrameTiming.timestampInMicroseconds(FramePhase.rasterFinishWallTime)` 取出系統時鐘對齊之微秒戳，轉換為 `DateTime`。
- Web 平台或異常時（`kIsWeb` 或 wall time ≤ 0）：退回 `DateTime.now()`，絕不拋出例外。

### 自造停頓排除 (Observer Effect)
- Kit 在 `dashboard_modal.dart` 切換排版邊界時會呼叫 `RendererBinding.instance.reassembleApplication()`，此操作必然引發全 App 重新構建。
- `PerformanceHandler` 提供 `markSelfInducedReassemble()` 機制，在 reassemble 期間跳過幀時間判定。

---

## 2. 任務拆分

### Task 1 · 核心 PerformanceHandler 實作與單元測試
**目標**：獨立封裝幀時間處理器，無外部 UI 依賴，具備完整的單元測試防護。

**寫入路徑**：
- `lib/src/core/performance_handler.dart`
- `test/core/performance_handler_test.dart`

**實作要點**：
1. 定義 `PerformanceHandler`：
   - 參數：`LogCallback onLog`、`String? Function()? topPageLabel`、`Duration threshold`、可注入之 `DateTime Function()? clock`。
   - 方法：`attach()`、`detach()`、`handleTimings(List<FrameTiming>)`、`markSelfInducedReassemble()`。
2. 逐幀迭代 `for (final t in timings)`，使用 `t.totalSpan >= threshold` 判定。
3. 實作連續超標幀合併演算法與跨批次 streak 保留。
4. 處理 `rasterFinishWallTime` 轉換與 Web fallback。
5. 包含 `try/catch` 保護，避免任何未預期例外逸出中斷 `SchedulerBinding`。
6. 單元測試覆蓋：
   - 單幀超標（>=700ms 觸發 warning，<700ms 靜默）。
   - 資料載荷包含 4 個 ms 欄位。
   - 連續 3 幀超標在遇到正常幀時合併為 1 筆，帶 `frameCount: 3`。
   - `detach()` 時 flush 殘留 streak。
   - `markSelfInducedReassemble()` 忽略自造停頓。
   - 時鐘轉換（wall time vs fallback）。

---

### Task 2 · FlutterInspector 整合與 Dashboard 自造停頓標記
**目標**：將 `PerformanceHandler` 接入 Inspector 主生命週期與 Dashboard 元件。

**寫入路徑**：
- `lib/src/core/flutter_inspector.dart`
- `lib/src/core/inspector_registry.dart`（若需要公開或存取）
- `lib/src/ui/dashboard/dashboard_modal.dart`
- `test/core/flutter_inspector_test.dart`

**實作要點**：
1. `FlutterInspector` 建構式新增：
   - `bool capturePerformance = false`
   - `Duration frozenFrameThreshold = const Duration(milliseconds: 700)`
   - 參數校驗：`if (frozenFrameThreshold <= Duration.zero) throw ArgumentError.value(...)`。
2. 在建構式中初始化 `_performanceHandler`，若 `capturePerformance == true` 則於適當時機 `attach()`。
3. `detach()` 時呼叫 `_performanceHandler.detach()`。
4. 在 `dashboard_modal.dart` 切換 `debugPaintSizeEnabled` 並呼叫 `reassembleApplication()` 之前，呼叫 `inspector.performanceHandler?.markSelfInducedReassemble()`。
5. 整合測試：
   - 驗證 `capturePerformance: false` 不掛載回呼。
   - 驗證 `capturePerformance: true` 正確傳遞日誌並附帶當前路由標籤。

---

### Task 3 · Example App 模擬按鈕、文件與 CHANGELOG
**目標**：提供實機／模擬器互動驗收能力，更新版本紀錄。

**寫入路徑**：
- `example/lib/main.dart`
- `CHANGELOG.md`

**實作要點**：
1. `example/lib/main.dart`：
   - `FlutterInspector` 設定開啟 `capturePerformance: true`。
   - 新增「Simulate Frozen Frame (900ms)」按鈕：
     - 在 `onPressed` 中使用 `Stopwatch` 忙等 ~900ms（模擬事件同步阻塞）。
     - 提供另一個按鈕或切換在 Widget `build()` 內忙等 ~900ms（模擬龐大 build 阻塞）。
2. 更新 `CHANGELOG.md`：
   - 在 `## Unreleased` 記錄新增 `capturePerformance` 與 `frozenFrameThreshold`。
3. 執行完整驗證：
   - 執行 `flutter test`。
   - 執行 `dart analyze`。
