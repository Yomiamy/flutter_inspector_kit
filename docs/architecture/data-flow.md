# Flutter Inspector Kit - 數據流與功能流程 (Data Flow)

> 「好的程式碼沒有特殊情況。」 —— Linus Torvalds

本文件詳細剖析本套件內四大核心功能的運作流程、狀態移轉與數據傳遞軌跡，並介紹了 `v1.1.0` 重構前後跨層混合時序軸（Merged Timeline）的資料流演進。

---

## 1. 網路請求攔截與更新流程 (HTTP Interception & Completion)

在網路請求的生命週期中，數據被低干涉地捕獲兩次：發出請求時（用於即時顯示 pending 狀態）與響應/失敗時（更新狀態碼、時長與 Body）。

### 數據流時序圖
在 `v1.1.0` 中，網絡請求純淨寫入 `NetworkInspector` 的環形快取中，不產生任何日誌鏡射。

```text
  Dio Client (App)            DioInterceptor               FlutterInspector & Registry
       │                           │                                    │
       │─── 1. 發起 Request ──────>│                                    │
       │                           │─── 2. 建立 Incomplete Entry ──────>│
       │                           │    (記錄 startTime)                │
       │                           │<── 3. 返回 pendingEntry ───────────│
       │                           │                                    │
       │                           │─── 4. 存入 options.extra ──────────│
       │<── 5. 放行 Request ───────│                                    │
       │                           │                                    │
       ~   ( 網絡傳輸中... )        ~                                    ~
       │                           │                                    │
       │─── 6. 響應/失敗 ─────────>│                                    │
       │                           │─── 7. 從 options.extra 取得 pending│
       │                           │─── 8. 原地更替為 Completed Entry ─>│
       │                           │    (透過 RingBuffer.replace())     │
       │                           │                                    │
       │                           │─── 9. [選用] 發送平台自適應通知 ──>│
       │                           │    (經 AlertThrottler 靜默限制)    │
       │<── 10. 返回 Response ─────│                                    │
```

### 關鍵細節：請求重發 (Replay Request)
在 `NetworkDetailView` 中點擊「重發」按鈕時：
1. **安全性檢查**：必須滿足「請求已完成（`entry.isComplete == true`）」、「來源 `Dio` 未被回收（`sourceDio.target != null`）」且「Body 未被截斷（`isRequestTruncated == false`）」。
2. **防死循環標記**：重發的請求會自動注入 `_inspector_is_replay: true` 到 `options.extra` 中。這可以使新請求在被攔截器捕獲時，標記為 `isReplay = true`，防止開發者混淆。

---

## 2. 🧵 跨層混合時序軸的設計與歸併排序 (Merged Timeline)

在 `v1.1.0` 重構後，我們徹底刪除了擷取層的 `_inspector.log(...)` 鏡射呼叫，從而實現了單一真相源（Single Source of Truth）。

### 2.1 執行時序對比區塊圖 (Execution Timeline Comparison)

這兩者在「事件發生」與「UI 渲染」兩個不同階段的執行時序有本質上的差異：

#### 歷史方案 A：v1.1.0 之前的複製式鏡射 (Mirroring)
在事件發生時，攔截器強行進行「雙寫（Double Write）」，將資料轉為字串拷貝，導致快取重疊與狀態不同步。

```text
  【 1. 事件發生 (e.g. 網絡完成) 】
  ┌──────────────────────────────────────────────────┐
  │  事件源 (Dio/Navigator/DB)                        │
  └────────┬───────────────────────────────┬─────────┘
           │                               │
           ▼ (寫入結構化數據)              ▼ (複製為字串鏡射)
  ┌────────────────────────────────┐ ┌──────────────────────────────┐
  │  目標 Buffer (Network/Nav/DB)  │ │  Log RingBuffer              │
  │  (原地更新為 Completed)         │ │  (寫入 LogEntry)              │
  └────────────────────────────────┘ └──────────────┬───────────────┘
                                                    │ (讀取日誌緩存)
                                                    ▼
                                     ┌──────────────────────────────┐
                                     │  UI ConsoleTab               │
                                     │  (僅能顯示純文字、無互動跳轉)│
                                     └──────────────────────────────┘
```

#### 現行方案 B：v1.1.0 的 `Merged Timeline` 動態排序
事件發生時純淨寫入（單一真相源），僅在 UI 渲染時按需進行歸併排序。

```text
  【 1. 事件發生 】
  ┌──────────────────────────────────────────────────┐
  │  事件源 (Dio/Navigator/DB)                        │
  └────────┬─────────────────────────────────────────┘
           │ (純淨寫入結構化數據，無複製鏡射，零贅餘)
           ▼
  ┌──────────────────────────────────────────────────┐
  │  各自 RingBuffer (Network / Navigator / DB / Log) │
  └────────┬─────────────────────────────────────────┘
           │
           │ 【 2. UI 渲染期 】
           │ (呼叫 mergedTimeline(sources))
           ▼
  ┌──────────────────────────────────────────────────┐
  │  InspectorRegistry 核心                           │
  │  → 讀取所有啟用源 (Log + Network + Nav + DB)      │
  │  → 拍扁 (Flatten) 所有數據                        │
  │  → 依 timestamp 進行記憶體中降序 Merge-Sort       │
  └────────┬─────────────────────────────────────────┘
           │ (回傳 List<TimestampedEntry>)
           ▼
  ┌──────────────────────────────────────────────────┐
  │  UI ConsoleTab                                   │
  │  → 依 Entry 實際類型分派渲染                       │
  │  → Network 類型 Row 點擊可跳轉 DetailView 交互   │
  └──────────────────────────────────────────────────┘
```

---

### 2.2 核心指標與機制對照

| 階段 | 歷史方案 A: 複製式鏡射 (v1.1.0 之前) | 現行方案 B: 歸併排序 (v1.1.0 之後) |
| :--- | :--- | :--- |
| **擷取期 (Capture)** | 寫入 Network RingBuffer，同時產生一條字串 `LogEntry` 寫入 Log RingBuffer。 | **只寫入 Network RingBuffer**，日誌快取維持 100% 純淨。 |
| **狀態更新 (Update)** | Network 快取原地更新為 Completed，但 Log 快取內的字串依然是舊的 pending 快照。 | 各快取獨立，Network 原地更新。**不存在第二份真相**。 |
| **讀取期 (Read)** | UI `ConsoleTab` 只需單純讀取 `LogInspector.entries`。 | UI `ConsoleTab` 通過 `FlutterInspector.mergedTimeline(sources)` 向 Registry 查詢。 |
| **整合排序 (Sort)** | 無需排序（因為寫入時已按先後順序轉為 Log 字串）。 | **渲染時排序**：讀取四個 RingBuffer 拍扁（Flatten）成 `List<TimestampedEntry>`，並在記憶體中按 `timestamp` 進行降序 merge-sort。 |
| **點擊查看 (Interaction)** | 點擊鏡射日誌只能看字串，無 Headers/Body，因為它只是個 `LogEntry`。 | 點擊 Network 類型的時序軸列，會利用 `is` 判型直接跳轉至完整的 `NetworkDetailView`，支持 cURL/Replay。 |

---

### 2.3 Merged Timeline 歸併排序運作流程

```text
  ┌────────────────────────────────────────┐
  │         ConsoleTab 進行 UI 渲染        │
  └───────────────────┬────────────────────┘
                      │ 呼叫
                      ▼
  ┌────────────────────────────────────────┐
  │    FlutterInspector.mergedTimeline     │
  └───────────────────┬────────────────────┘
                      │ 轉發
                      ▼
  ┌────────────────────────────────────────┐
  │   InspectorRegistry.mergedTimeline     │
  └───────────────────┬────────────────────┘
                      │
                      ├─► 讀取 Log RingBuffer (TimelineSource.log)
                      ├─► 讀取 Network RingBuffer (TimelineSource.network)
                      ├─► 讀取 Navigator RingBuffer (TimelineSource.nav)
                      └─► 讀取 Database RingBuffer (TimelineSource.db)
                      │
                      ▼
  ┌────────────────────────────────────────┐
  │          List.addAll 合併列表          │
  └───────────────────┬────────────────────┘
                      │
                      ▼
  ┌────────────────────────────────────────┐
  │  list.sort 按 timestamp 降序 Memory 排序│
  └───────────────────┬────────────────────┘
                      │ 回傳 List<TimestampedEntry>
                      ▼
  ┌────────────────────────────────────────┐
  │  UI層 ListView.builder (依 is 判型渲染) │
  ├────────────────────────────────────────┤
  │  → LogEntry: 渲染日誌行                 │
  │  → NetworkEntry: 渲染網絡行 (支援點擊)  │
  │  → NavigatorEntry: 渲染導航行           │
  │  → DatabaseEntry: 渲染資料庫行           │
  └────────────────────────────────────────┘
```

---

## 3. 路由導航監聽流程 (Navigation Observing)

透過將 `FlutterInspectorNavigatorObserver` 註冊至 `MaterialApp.navigatorObservers`，套件能實時記錄路由事件。

```text
  ┌────────────────────────────────────────┐
  │          App 發生路由導航變化          │
  └───────────────────┬────────────────────┘
                      │ (didPush / didPop / didReplace / didRemove)
                      ▼
  ┌────────────────────────────────────────┐
  │     NavigatorObserver 監聽攔截         │
  └───────────────────┬────────────────────┘
                      │
                      ▼
            是否為控制台頁面？
            (flutter_inspector_dashboard)
           ╱        ╲
        (Yes)       (No)
         ╱            ╲
  ┌───────────┐   ┌────────────────────────┐
  │ 忽略，不記 │   │   安全解析 Widget 類型  │
  │ 防止自循環│   └───────────┬────────────┘
  └───────────┘               │
                              ▼
                       路由設定類型？
                      ╱              ╲
                (settings is Page)  (其他)
                  ╱                      ╲
  ┌───────────────────────┐      Route 是否有 builder？
  │ 獲取 page.child 的    │     ╱                      ╲
  │ runtimeType           │   (Yes)                   (No)
  └──────────┬────────────┘   ╱                          ╲
             │       ┌───────────────┐          ┌──────────────────┐
             │       │ 安全呼叫      │          │ 降級使用路由名稱  │
             │       │ builder 獲取  │          │ settings.name    │
             │       │ runtimeType   │          │ (或 'Unknown')   │
             │       └───────┬───────┘          └────────┬─────────┘
             ▼               ▼                           ▼
  ┌────────────────────────────────────────────────────────────────┐
  │                       建立 NavigatorEntry                      │
  └───────────────────────────────┬────────────────────────────────┘
                                  │
                                  └─► 寫入 NavigatorInspector RingBuffer
```

---

## 4. 未捕獲錯誤鏈接與轉發流程 (Error Handling & Chaining)

當配置 `captureUncaughtErrors: true` 時，套件會主動掛載錯誤處理鉤子。為保證向後兼容性（Never break userspace），我們決不能吞掉錯誤。

```text
                  主應用發生 Uncaught Error
                              │
                              ▼
                      錯誤發生在何處？
               ┌──────────────┼──────────────┐
               │              │              │
               ▼ (渲染/UI)    ▼ (非同步/Dart) ▼ (Widget 構建崩潰)
         FlutterError   PlatformDispatcher  ErrorWidget
           .onError        .instance.onError   .builder
               │              │              │
               └──────────────┼──────────────┘
                              ▼
                     建立 LogEntry (Error)
                              │
                              ▼
                 安全處理 (try-catch 隔離包裹)
                              │
                              ▼
                寫入 LogInspector RingBuffer
                              │
                              ▼
                   是否存在 Host 原始 Handler？
                    ╱                      ╲
                  (Yes)                    (No)
                  ╱                          ╲
  ┌────────────────────────┐      ┌────────────────────────┐
  │ 調用舊 Handler 轉發錯誤 │      │ 調用系統預設錯誤處理    │
  │ (如發送至 Crashlytics) │      │ (或崩潰紅畫面渲染)     │
  └────────────────────────┘      └────────────────────────┘
```

- **安全防護**：如上圖所示，即使寫入過程發生任何異常，控制權也會在 `finally` 中被交回給 `Forward` 或 `System`，Host 應用絕不會因為除錯套件的日誌記錄失敗而產生二次崩潰。

---

## 5. 資料庫操作虛擬化與瀏覽流程 (Database Virtualization)

套件提供了可擴充的 `DatabaseBrowserSource` 介面，不僅支持真正的 App 資料庫（如 SQLite），還利用該介面設計了「操作日誌瀏覽器」。

```text
  App 執行 SQL 操作 ──► FlutterInspector ──► DatabaseInspector RingBuffer
                                                    │
                                                    ▼
                                         OperationLogSource 虛擬化
                                        ┌───────────┴───────────┐
                                        │                       │
                                        ▼                       ▼
                                   虛擬資料表              虛擬資料行
                                  (依 SQL 影響表名分群)   (格式化欄位與 timestamp)
                                        │                       │
                                        ▼                       ▼
                                   DatabaseTab (UI) ◄─── 動態分頁載入 (Load More)
                                   (支援排序與分頁)
```

### 資料分頁與排序 (TableRowsView & TableSort)
1. **動態加載 (Load More)**：`TableRowsView` 採用 `limit` (預設 200) 與 `offset` 機制進行分頁加載。用戶滑動到底部時觸發 `Load More`，累加 `offset` 並向資料源重新請求數據。
2. **表頭排序 (Sort)**：點擊表頭時，由 `table_sort.dart` 的 `sortRows` 執行記憶體排序：
   - 排序原則：`Null` 值一律排在最後（不論正序/倒序）。
   - 數值類型按數值大小比較，其餘類型轉為字串比較。
