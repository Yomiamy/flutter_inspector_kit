# Flutter Inspector Kit - 整體架構概覽 (Overview)

> 「差勁的程式員只擔心程式碼，優秀的程式員關心資料結構。」 —— Linus Torvalds

`flutter_inspector_kit` 是一個輕量、低干涉且實用的 Flutter 開發期調試工具。它將 Console 日誌、網路請求（HTTP）、頁面導航（Navigator）以及資料庫操作（Database）集成在單一的懸浮按鈕（FAB）與全螢幕儀表板中。

---

## 🏗️ 核心架構分層

本套件遵循「資料驅動」與「低侵入性」的設計原則，將架構劃分為四個主要層次：

```text
  ┌────────────────────────────────────────────────────────┐
  │                 表現層 (Presentation Layer)            │
  │  [DashboardModal]  [InspectorFab]  [ConsoleTab (Merged)]│
  └───────────────────────────┬────────────────────────────┘
                              │ 讀取與操作
                              ▼
  ┌────────────────────────────────────────────────────────┐
  │                 核心調試引擎 (Core Engine)             │
  │   [FlutterInspector]  [InspectorRegistry]  [RingBuffer]│
  └───────────────────────────┬────────────────────────────┘
                              │ 持有與快取
                              ▼
  ┌────────────────────────────────────────────────────────┐
  │                 領域模型層 (Domain Models)             │
  │               [TimestampedEntry] (抽象介面)            │
  │   [LogEntry]  [NetworkEntry]  [NavigatorEntry]  [DB]   │
  └───────────────────────────▲────────────────────────────┘
                              │ 結構化寫入
                              │
  ┌───────────────────────────┴────────────────────────────┐
  │               資料擷取層 (Collectors / Interceptors)   │
  │  [DioInterceptor]  [NavigatorObserver]  [ErrorHandlers]│
  └────────────────────────────────────────────────────────┘
```

### 1. 基礎核心層 (Core Engine)
- **`FlutterInspector`**：全域單例管理器。負責協調各子系統、註冊全域錯誤 Handler、掛載/卸載 UI Overlay、接收各類數據輸入。
- **`InspectorRegistry`**：中央緩衝註冊表，集中持有四個領域的專屬 Inspector。
- **`RingBuffer`**：最核心的底層資料結構，為一個固定容量的 FIFO 快取。**所有**數據搜集（日誌、網絡、導航、資料庫）皆基於它來儲存。

### 2. 數據模型層 (Domain Models)
- 採用 **Immutable (不可變)** 的設計模式。
- 包括 `LogEntry`、`NetworkEntry`、`NavigatorEntry` 與 `DatabaseEntry`。
- **好品味體現**：快取中的數據一旦寫入就不應被隨意修改。對於 `NetworkEntry` 等需要異步更新的數據，採用 `copyWith` 與 `RingBuffer.replace` 在快取中原地替換，防止列表重建時發生狀態混亂與不必要的內存拷貝。

### 3. 數據擷取層 (Collectors / Interceptors)
- **`DioInterceptor`** 〔獨立 class · `lib/src/interceptors/dio_interceptor.dart`〕：攔截 Dio 請求與響應，處理 pending 狀態更新，並支持請求重發（Replay）。
- **`NavigatorObserver`** 〔獨立 class · `lib/src/observers/navigator_observer.dart`〕：自動監聽路由變化，安全解析頁面 Widget 類型。
- **`ErrorHandlers`** 〔非獨立 class · 由 `FlutterInspector.setupErrorHandlers()` 直接以 callback 設定〕：無侵入地鏈接 FlutterError、PlatformDispatcher 與 ErrorWidget 錯誤鉤子。該 method 將 closure 直接賦值給 Flutter 的全域鉤子（`FlutterError.onError`、`PlatformDispatcher.instance.onError`、`ErrorWidget.builder`），不存在獨立的 handler 類別。
- **`OperationLogSource`** 〔獨立 class · `lib/src/sources/operation_log_source.dart`〕：將資料庫操作日誌轉換為虛擬表格，以配合資料庫瀏覽器展示。

#### 設計模式標注：Adapter + Constructor Injection

`FlutterInspectorDioInterceptor` 與 `FlutterInspectorNavigatorObserver` 自身不持有任何儲存，它們只作為「第一手資料的接入口」，拿到原始事件後立即轉派給 `FlutterInspector`。此結構是兩個經典模式的疊加：

- **Adapter Pattern（Object Adapter）**：`Interceptor`（Dio）與 `NavigatorObserver`（Flutter）是第三方框架定義、無法修改的介面；這兩個類別把「框架的回呼語言」翻譯成「Inspector 的記錄語言」，透過組合（持有 `_inspector` 參考）而非繼承來轉接，正是 Object Adapter 的標準形態。

  ```text
  Dio 的 onRequest/onResponse/onError    ──adapt──▶  FlutterInspector.logNetwork()
  Flutter 的 didPush/didPop/didReplace   ──adapt──▶  FlutterInspector.navigatorInspector.add()
  ```

- **Constructor Injection（DI 技巧，非 GoF 模式）**：`FlutterInspectorDioInterceptor(this._inspector)` 將 inspector 由建構子注入，而非在內部硬抓全域單例。它解決的是「依賴從哪取得」，與「架構角色（Adapter）」是兩個獨立維度。好處是測試時可注入 mock inspector，無需依賴全域狀態。

> ⚠️ **常見誤判**：`NavigatorObserver` 名稱帶 "Observer"，易誤認為 GoF 的 Observer Pattern。實則不然——它只是 Flutter 提供的回呼介面（callback hook），這兩個類別實作後將事件「轉發」出去，屬 Adapter 行為，並非 Observer 的「subject 維護 observer 清單、主動通知」協作結構。

> **品味守則**：Adapter 必須維持薄翻譯層，不得在其中滋長業務邏輯（如 `dio_interceptor.dart` 中 `_stringifyData` 這類純格式轉換是可接受的邊界）。

### 4. 表現層 (Presentation Layer)
- **`InspectorFab`**：支持手勢拖拽的懸浮按鈕，限制在屏幕安全區域內。
- **`DashboardModal`**：包含四大 Tab 的全螢幕控制台，支持自訂第五個開發者 Tab。
- **`MagicalTap`**：靜默連擊偵測組件，可在隱藏 FAB 的情況下通過連擊手勢喚醒控制台。

---

## 🛠️ 架構設計原則與「好品味」

### 1. 平台自適應與 WASM 相容性 (Conditional Exports)
在網路通知 (`NetworkNotifier`) 與文字分享 (`ShareText`) 模組中，為了解決 Native（依賴 `dart:io` 與三方套件）與 Web（WASM 相容）之間的平台差異：
- 採用 **條件匯出 (Conditional Exports)** 技術：
  - Web 端自動切換為 no-op stub，或直接調用 Web 原生的 API（例如 Web Share API）。
  - Native 端則載入對應的插件（例如 `flutter_local_notifications`、`share_plus`）。
- **結果**：完全阻斷 `dart:io` 傳遞式匯入進入 Web 編譯鏈，保持 Flutter 網頁端 WASM 構建的乾淨相容。

### 2. 弱引用與防洩漏設計 (WeakReference)
在 `NetworkEntry` 中，重發（Replay）功能需要調用發起請求的 `Dio` 實例：
- **致命風險**：如果直接持有 `Dio` 實例強引用，隨著 RingBuffer 達到上限並拋棄舊 Entry，這些已失效的 `Dio` 將無法被垃圾回收，造成嚴重的內存洩漏。
- **Linus 式解法**：在 `NetworkEntry` 中使用 `WeakReference<Dio>`。這是一個暫時性的運行期引用，只在 Replay 時嘗試獲取。此欄位被刻意排除在 `==`、`hashCode` 與所有導出序列化之外，確保安全、乾淨且零洩漏。

### 3. 無害的錯誤鉤子 (Never Break Host App)
在捕獲 uncaught exceptions 時：
- `setupErrorHandlers` 嚴格包裹現有 Host 處理程序（`FlutterError.onError` 等）。
- 寫入日誌的邏輯完全置於 `try-catch` 中，不論日誌儲存是否失敗，**都必須確保將錯誤原樣轉發回 downstream**。
- **原則**：我們的職責是輔助調試，絕不能因為套件自身的崩潰或錯誤導致主 App 的行為改變。

---

## 🧵 跨層混合時序軸 (Cross-Layer Merged Timeline) - v1.1.0 新特點

自 `v1.1.0` 起（PR #40 / #42 合入後），控制台的主體時間軸已完成重構，實現了高品味的跨層混合時序軸。

### 1. 單一真相源與歸併排序
- **設計**：所有領域模型（`LogEntry`、`NetworkEntry`、`NavigatorEntry`、`DatabaseEntry`）皆實現了統一的 `TimestampedEntry` 介面，暴露單一 `timestamp` 與 `displayTime`。
- **時序軸渲染**：擷取層（攔截器與觀察者）**純淨寫入**各自的專屬緩存，不進行任何日誌鏡射。在 UI 渲染期，`ConsoleTab` 呼叫 `FlutterInspector.mergedTimeline(sources)`，由底層的 `InspectorRegistry` 將四個獨立的 `RingBuffer` 拍扁（Flatten），並在記憶體中依 `timestamp` 降序進行歸併排序（Merge-Sort），即時引用原始 Entry 物件。
- **富交互**：時序軸行依 `entry is NetworkEntry` 等類型動態分派渲染。點擊 Network 類型列直接跳轉至 `NetworkDetailView`，支援 cURL 複製與 Replay 重發請求。

### 2. 歷史演進：為什麼要進行此項重構？
在 `v1.1.0` 之前，套件是靠「複製式鏡射 (Mirroring)」來假裝呈現綜合時間軸：在擷取到網絡/路由事件時，強行將 Method/URL/路由名稱**複製為字串**，主動調用 `_inspector.log(...)` 灌入日誌緩存。

這帶來了三大低品味痛點，已在 `v1.1.0` 被徹底消滅：
1. **第二份真相**：網路請求進度更新為 Completed 時，日誌緩存中的 pending 字串拷貝無法原地更新，造成狀態不同步。
2. **污染日誌級別**：路由導航事件強制佔用了 `warning` 級別，混淆了真正的 Warning 錯誤。
3. **互吃緩存配額**：大量的網絡與路由字串塞滿了限額 500 條的日誌緩存，將主應用真正的 Error 日誌無情擠出 RingBuffer。
