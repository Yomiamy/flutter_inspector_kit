# 功能規格：掉幀／凍結幀效能捕捉（§P20 / capturePerformance）

- **日期**：2026-10-17
- **來源**：`docs/brainstorm/2026-10-14-features-brainstorm.md` §P20 與第八部分 §Z2
- **裁決依據**：2026-10-16 裁決解禁「凍結幀離散事件」，採 700ms 絕對門檻（對齊 Android Vitals frozen frame 定義），實機 benchmark 閘門已通過（0/307 幀 ≥ 700ms）
- **Effort**：low~medium ｜ **排查價值**：⭐⭐⭐⭐⭐

---

## 1. 使用者故事

> 作為一位在實機上測試或排查 App 卡頓的開發者／QA，
> 我希望**當畫面發生嚴重凍結（單幀繪製耗時 ≥ 700ms）時，Inspector 能自動記錄一筆 Warning 事件到時間軸**，
> 這樣我就能將凍結事件與同一時間點前後的 API 請求、頁面跳轉或資料庫操作精準對齊，
> 一眼看出卡頓是因為哪個沉重大 JSON、同步阻塞工作或巨型 rebuild 所引起。

### 為什麼這件事值得做

1. **對齊 Google Play Core Vital**：Slow rendering / Frozen frames 是 Google Play 的核心指標，直接影響商店推薦與排名。Play Console 僅提供大盤聚合百分比（知道卡，但不知卡在哪個使用者操作或哪支 API）。
2. **因果鏈推斷**：時間軸的核心價值是「前後文脈絡」。一次 700ms 的畫面停頓夾在 Network 回傳、Route Push 與 DB 寫入之間，能夠回答單一 FPS 數字或獨立儀表無法回答的關鍵問題：「卡頓發生在什麼事情之後」。
3. **解決 Debug 膨脹誤報死因**：先前 Anti-Feature #1 否決 profiler / FPS 儀表的原因是 Debug 模式下無 AOT 且 assert 全開，16ms/32ms 的常規掉幀預算會產生數倍的乘法膨脹，導致時間軸被假 jank 洗版；改採 700ms 凍結級門檻後，即便 10ms 的幀膨脹 40 倍也僅 400ms，不會觸發誤報。實機實測（0/307 幀 ≥ 700ms）已正式證實此門檻有效避開 Debug JIT/Shader 停頓。

---

## 2. 範圍邊界

### ✅ 做

1. **公開 API 與配置**：
   - `FlutterInspector` 建構式新增：
     - `bool capturePerformance = false`（預設關閉，對齊 `captureLifecycleEvents` / `captureUncaughtErrors` 慣例）。
     - `Duration frozenFrameThreshold = const Duration(milliseconds: 700)`（可自訂門檻，拒絕非正值／負值）。
   - 提供 `detach()` 完整釋放機制：註銷 `SchedulerBinding.instance.removeTimingsCallback`。
2. **底層採集與判定式（依 §Z2 勘誤）**：
   - 透過 `SchedulerBinding.instance.addTimingsCallback` 註冊回呼。
   - 批次走訪 `for (final t in timings)` 逐幀處理，不可單批只判一幀。
   - **判定式採 `t.totalSpan >= frozenFrameThreshold`**（涵蓋 `vsyncOverhead`，能捕獲事件 handler 在幀前同步阻塞 UI 執行緒的凍結）。
3. **事件形狀與資料結構**：
   - 寫入既有 `LogEntry` 維度（`LogLevel.warning`），**不新增** `JankEntry` / `JankInspector` / `TimelineSource`（恪守 Anti-Feature #6，避免新增第五維度）。
   - 訊息格式：
     - 單幀：`Frozen frame (${totalSpanMs}ms)$suffix`
     - 連續超標合併：`Frozen frame (${totalSpanMs}ms, ${count} frames)$suffix`
     - 末尾附帶當前 top-most page（`topPageLabel`）。
   - `LogEntry.data` 結構化載荷：
     ```dart
     {
       'totalSpanMs': totalSpan.inMilliseconds,
       'vsyncOverheadMs': vsyncOverhead.inMilliseconds,
       'buildDurationMs': buildDuration.inMilliseconds,
       'rasterDurationMs': rasterDuration.inMilliseconds,
       if (count > 1) 'frameCount': count,
     }
     ```
4. **時間戳對齊**：
   - Native 平台：優先使用 `FrameTiming.timestampInMicroseconds(FramePhase.rasterFinishWallTime)`，以 `DateTime.fromMicrosecondsSinceEpoch` 轉換為與系統時鐘同步的時間戳。
   - Web 平台或當 wall time 異常（≤ 0）時：平穩退回 `DateTime.now()`。
5. **連續超標幀合併（Debounce / Clustering）**：
   - 連續發生的凍結幀（幀間間隔小於等於閥值或連續緊鄰）合併為一筆累計事件，在下一個正常幀到達或幀間距拉大時收尾發布，避免單一重度滾動塞滿 `RingBuffer(500)`。
   - 在 `detach()` 時若有尚未發布的 pending 累計事件，立即 flush。
6. **排除自造停頓（Observer Effect Defense）**：
   - Kit 自身觸發的 `RendererBinding.instance.reassembleApplication()`（如排版邊界切換）標記自造停頓，跳過該次停頓引起的幀時間，不計入警告。
7. **Example 驗收按鈕**：
   - `example/` 新增模擬凍結按鈕（透過 `Stopwatch` 忙等 ~900ms，涵蓋 `onPressed` 同步工作阻塞與 Widget `build` 耗時）。

### ❌ 不做（明確排除）

| 排除項 | 理由 |
|:---|:---|
| 當前 FPS 即時數字、儀表盤、折線圖 | 違反 Anti-Feature #1；點查詢切斷前後文因果鏈，且常駐重繪引發自身 Jank |
| 新增 `JankEntry` / `JankInspector` / 第五 `TimelineSource` | 違反 Anti-Feature #6；凍結幀本質就是 Warning 事件，落入既有 Log 維度最純粹 |
| 常駐心跳 Watchdog Timer | 違反純 Dart package 定位，破壞無常駐 Timer、無背景輪詢的設計約束 |
| 16ms / 32ms 常規掉幀採集 | Debug build 下乘法膨脹會徹底污染時間軸，只取 700ms 凍結級事件 |
| 記憶體／堆疊自動 Dump | 違反 Anti-Feature #2；純 Dart 層無跨平台 memory dump API |

---

## 3. 資料流架構

```text
Flutter Engine Frame Rendering
  │
  ▼
SchedulerBinding.instance.addTimingsCallback (批次 List<FrameTiming>)
  │
  ▼
PerformanceHandler (核心處理器)
  ├── 檢查是否為 Kit 自身 reassembleApplication() → 是則忽略
  ├── 走訪每個 FrameTiming
  │     ├── t.totalSpan >= 700ms
  │     │     └── 進入／累計連續凍結叢集 (streak)
  │     └── t.totalSpan < 700ms
  │           └── 若有 pending streak → 收尾並觸發 onLog()
  │
  ▼ (輸出)
onLog(
  'Frozen frame (820ms) · HomePage (/home)',
  level: LogLevel.warning,
  data: {
    'totalSpanMs': 820,
    'vsyncOverheadMs': 210,
    'buildDurationMs': 120,
    'rasterDurationMs': 490,
  },
  timestamp: rasterFinishWallTime,
)
  │
  ▼
FlutterInspector._registry.log (LogInspector / RingBuffer)
  │
  ▼
ConsoleTab / Merged Timeline (黃色 Warning 標籤，點開 LogDetailView 顯示三段耗時)
```

---

## 4. 驗收條件

1. **開關與預設行為**：
   - 當 `capturePerformance: false`（預設）時，不向 `SchedulerBinding` 註冊 callback，零額外負擔。
   - 當 `capturePerformance: true` 時，註冊 callback；呼叫 `detach()` 時確實註銷 callback，無記憶體洩漏。
2. **門檻判定與數據正確性**：
   - 傳入 `totalSpan` 為 699ms 的幀不觸發任何 Warning。
   - 傳入 `totalSpan` 為 700ms 的幀正確記錄 `LogLevel.warning`。
   - `data` 正確包含 `totalSpanMs`、`vsyncOverheadMs`、`buildDurationMs`、`rasterDurationMs`。
3. **連續超標合併**：
   - 一批或連續兩批中包含 3 個連續的 ≥700ms 幀，緊接著一個正常幀：只產生 1 筆 Warning log，內容顯示總耗時與幀數（`3 frames`），`data['frameCount'] == 3`。
4. **時鐘域對齊**：
   - Native 平台取 `rasterFinishWallTime` 換算之 `DateTime`，與 `mergedTimeline` 之其他事件時序一致。
   - Web 平台（`kIsWeb == true`）或 wall time 無效時退回 `DateTime.now()`，不拋出例外。
5. **自造停頓忽略**：
   - 排版邊界切換觸發 `reassembleApplication()` 時，標記忽略，後續緊鄰的一幀不產生假 Warning。
6. **測試與靜態分析**：
   - 所有現有測試全數通過（無回歸）。
   - 新增 `PerformanceHandler` 單元測試，覆蓋單幀超標、連續超標合併、自造停頓跳過、`detach` 資源釋放。
   - `dart analyze` 零 warning/error。
