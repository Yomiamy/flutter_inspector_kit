# Flutter Inspector Kit - 檔案用途與類型參考表 (File Reference)

本文件列出專案中所有核心源檔的單一職責、包含的關鍵類別與模組歸屬，並記錄了跨層混合時序軸（Merged Timeline）在 `v1.1.0` 重構實作後的代碼現狀。

---

## 📂 核心模組與檔案結構

### 1. 入口與核心層 (`lib/src/core/`)

| 檔案路徑 | 關鍵類別/列舉 | 單一職責 (Single Responsibility) | v1.1.0 混合時序軸重構實作現狀 |
| :--- | :--- | :--- | :--- |
| [`flutter_inspector_kit.dart`](../../lib/flutter_inspector_kit.dart) | - | Barrel 檔案，導出本套件對外公開的 API。 | - |
| [`flutter_inspector.dart`](../../lib/src/core/flutter_inspector.dart) | `FlutterInspector` | 主入口。初始化註冊表、附加 FAB Overlay、配置全域未捕獲錯誤捕捉、調用資料收集。 | **已實裝** `mergedTimeline()`，薄轉發調用註冊表以獲取混合排序後的數據。 |
| [`inspector_registry.dart`](../../lib/src/core/inspector_registry.dart) | `InspectorRegistry` | 中央註冊表。統一管理四個領域的專屬 Inspector 實例。 | **已實裝** `mergedTimeline()`，負責讀取 Log、Network、Nav、DB 等四個 RingBuffer 並進行歸併排序。 |
| [`ring_buffer.dart`](../../lib/src/core/ring_buffer.dart) | `RingBuffer<T>` | 基礎 FIFO 環形緩存。提供高效率的 `removeAt(0)` 及就地 `replace` 功能，為所有數據緩存之基石。 | 無影響，維持最單純的高效 FIFO 結構。 |
| [`uncaught_error_handler.dart`](../../lib/src/core/uncaught_error_handler.dart) | `UncaughtErrorHandler` | 負責捕捉未捕捉例外與鏈接錯誤鉤子。 | - |
| [`inspector_overlay_manager.dart`](../../lib/src/core/inspector_overlay_manager.dart) | `InspectorOverlayManager` | 負責安全地管理懸浮 FAB overlay 的生命週期。 | - |

### 2. 數據模型層 (`lib/src/models/`)

| 檔案路徑 | 關鍵類別/列舉 | 單一職責 (Single Responsibility) | v1.1.0 混合時序軸重構實作現狀 |
| :--- | :--- | :--- | :--- |
| [`timestamped_entry.dart`](../../lib/src/models/timestamped_entry.dart) | `TimestampedEntry`<br>`TimelineSource` (enum) | 定義混合時序軸排序契約介面、統一的時間格式化 extension (`displayTime`) 與來源列舉。 | **已新增此檔案**。作為四大領域 Entry 在時序軸排序的核心基礎契約。 |
| [`log_level.dart`](../../lib/src/models/log_level.dart) | `LogLevel` (enum) | 標記 Console 日誌的嚴重性等級 (`verbose` 至 `error`)。 | - |
| [`log_entry.dart`](../../lib/src/models/log_entry.dart) | `LogEntry` | 單條日誌記錄，包含訊息、級別、堆疊追蹤與附加的 structured payload。 | **已實作** `TimestampedEntry`，實現 `timestamp` 介面。 |
| [`network_entry.dart`](../../lib/src/models/network_entry.dart) | `NetworkEntry` | 網路 HTTP 請求記錄，包含 Method、URL、Headers、截斷的 Body、狀態碼與 `WeakReference<Dio>`。 | **已實作** `TimestampedEntry`，實現 `timestamp` 介面。 |
| [`navigator_action.dart`](../../lib/src/models/navigator_action.dart) | `NavigatorAction` (enum) | 導航動作類型（`push`、`pop`、`replace`、`remove`）。 | - |
| [`navigator_entry.dart`](../../lib/src/models/navigator_entry.dart) | `NavigatorEntry` | 導航事件記錄，解析 Route Name、頁面 Widget 類型與參數。 | **已實作** `TimestampedEntry`，實現 `timestamp` 介面。 |
| [`database_operation.dart`](../../lib/src/models/database_operation.dart) | `DatabaseOperation` (enum) | 資料庫操作類型（`insert`、`update`、`delete`、`query`）。 | - |
| [`database_entry.dart`](../../lib/src/models/database_entry.dart) | `DatabaseEntry` | SQL/資料庫操作記錄，包含操作類型、表名、影響行數與結構化數據。 | **已實作** `TimestampedEntry`，實現 `timestamp` 介面。 |
| [`database_browser_source.dart`](../../lib/src/models/database_browser_source.dart) | `DatabaseBrowserSource`<br>`DatabaseTableInfo`<br>`DatabaseTablePage` | 抽象介面。定義如何列出資料庫表與分頁獲取行資料，使 UI 與具體資料庫實現解耦。 | - |

### 3. 控制與收集器層 (`lib/src/inspectors/` 等)

| 檔案路徑 | 關鍵類別/列舉 | 單一職責 (Single Responsibility) | v1.1.0 混合時序軸重構實作現狀 |
| :--- | :--- | :--- | :--- |
| [`log_inspector.dart`](../../lib/src/inspectors/log_inspector.dart) | `LogInspector` | 對 Console 日誌 `RingBuffer` 的包裝，提供級別過濾。 | - |
| [`network_inspector.dart`](../../lib/src/inspectors/network_inspector.dart) | `NetworkInspector` | 對網路請求 `RingBuffer` 的包裝，提供 Body 自動截斷與 completion 替換。 | - |
| [`navigator_inspector.dart`](../../lib/src/inspectors/navigator_inspector.dart) | `NavigatorInspector` | 對導航事件 `RingBuffer` 的包裝。 | - |
| [`navigator_stack_resolver.dart`](../../lib/src/inspectors/navigator_stack_resolver.dart) | `NavigatorStackResolver` | 負責從歷史觀察者記錄中重建與解析當前作用中導航堆疊。 | - |
| [`database_inspector.dart`](../../lib/src/inspectors/database_inspector.dart) | `DatabaseInspector` | 對資料庫操作 `RingBuffer` 的包裝，提供表名或操作類型過濾。 | - |
| [`dio_interceptor.dart`](../../lib/src/interceptors/dio_interceptor.dart) | `FlutterInspectorDioInterceptor` | Dio 網路攔截器，在 `onRequest`、`onResponse` 與 `onError` 自動轉換並更新快取。 | **已移除**任何主動向 `LogInspector` 寫入鏡射字串的程式碼，日誌緩存保持 100% 純淨。 |
| [`navigator_observer.dart`](../../lib/src/observers/navigator_observer.dart) | `FlutterInspectorNavigatorObserver` | 導航監聽器，捕捉路由變更，並利用反射/ builder 解析頁面的真實 Widget 類型。 | **已移除**任何主動向 `LogInspector` 寫入 Warning 鏡射的程式碼，修正了時序衝突。 |
| [`operation_log_source.dart`](../../lib/src/sources/operation_log_source.dart) | `OperationLogSource` | 將 `DatabaseInspector` 的 SQL 日誌包裝為虛擬 `DatabaseBrowserSource` 供給 UI。 | - |

### 4. 平台適應通知層 (`lib/src/notifications/`)

| 檔案路徑 | 關鍵類別/列舉 | 單一職責 (Single Responsibility) | v1.1.0 混合時序軸重構實作現狀 |
| :--- | :--- | :--- | :--- |
| [`alert_throttler.dart`](../../lib/src/notifications/alert_throttler.dart) | `AlertThrottler` | 限制通知頻率。保證每兩秒最多觸發一次系統 heads-up banner 通知。 | - |
| [`network_notifier.dart`](../../lib/src/notifications/network_notifier.dart) | - | 平台導出分流器。在 Web 上載入 no-op，在 Native 上載入 `network_notifier_io`。 | - |
| [`network_notifier_io.dart`](../../lib/src/notifications/network_notifier_io.dart) | `NetworkNotifier` (Native) | 使用 `flutter_local_notifications` 顯示動態更新的 HTTP 通知，點擊可喚醒控制台。 | - |
| [`network_notifier_web.dart`](../../lib/src/notifications/network_notifier_web.dart) | `NetworkNotifier` (Web) | Web no-op 實現，排除 `dart:io` 防止破壞 WASM 編譯。 | - |

### 5. 無狀態工具層 (`lib/src/utils/`)

| 檔案路徑 | 關鍵類別/列舉 | 單一職責 (Single Responsibility) | v1.1.0 混合時序軸重構實作現狀 |
| :--- | :--- | :--- | :--- |
| [`log_formatters.dart`](../../lib/src/utils/log_formatters.dart) | - | 將 `LogEntry` 轉換為純文字導出格式。 | - |
| [`network_formatters.dart`](../../lib/src/utils/network_formatters.dart) | `ReplayRequest` | 提供網路請求的格式化工具，如 `buildCurl` 產出 cURL、`prettyJson` 縮排、`formatBytes` 等。 | - |
| [`network_utils.dart`](../../lib/src/utils/network_utils.dart) | `NetworkStatusGroup`<br>`NetworkFilter` | 網路請求的搜尋過濾邏輯（基於關鍵字、Method 與 HTTP 狀態分組），並集中 `timeOf` 時間格式化與 `httpMethods`/`statusLabels` 篩選常數。 | - |
| [`redaction.dart`](../../lib/src/utils/redaction.dart) | - | 安全過濾。識別敏感 header（如 `authorization`）並將其內容遮蔽為 `••••`。 | - |
| [`share_text.dart`](../../lib/src/utils/share_text.dart) | - | 分享平台分流器。Web 端匯出 `share_text_web`，Native 端匯出 `share_text_io` | - |
| [`share_text_io.dart`](../../lib/src/utils/share_text_io.dart) | - | 使用 `share_plus` 開啟手機系統原生分享面板。 | - |
| [`share_text_web.dart`](../../lib/src/utils/share_text_web.dart) | - | 使用 Web Share API `navigator.share`，降級則複製到剪貼簿。 | - |
| [`table_sort.dart`](../../lib/src/utils/table_sort.dart) | - | 提供虛擬資料庫表格的單列排序與單元格預覽。 | - |

### 6. UI 表現層 (`lib/src/ui/`)

| 檔案路徑 | 關鍵類別/列舉 | 單一職責 (Single Responsibility) | v1.1.0 混合時序軸重構實作現狀 |
| :--- | :--- | :--- | :--- |
| [`dashboard_modal.dart`](../../lib/src/ui/dashboard/dashboard_modal.dart) | `DashboardModal` | 控制台的主視窗 Dialog。封裝 `TabBarView` 結構與自訂頁。 | - |
| [`console_tab.dart`](../../lib/src/ui/dashboard/tabs/console_tab.dart) | `ConsoleTab` | 顯示日誌清單，區分顏色，點擊可開啟日誌詳細視窗。 | **已大幅重構**。新增 `TimelineSource` 頂部過濾晶片列，基於 `mergedTimeline` 讀取混合數據，並按 `is` 判型進行多樣化視圖渲染與點擊詳情跳轉。 |
| [`log_detail_view.dart`](../../lib/src/ui/dashboard/tabs/console/log_detail_view.dart) | `LogDetailView` | 顯示單條日誌的 General、Stack Trace 與 Data 卡片，支援分享。 | - |
| [`network_tab.dart`](../../lib/src/ui/dashboard/tabs/network_tab.dart) | `NetworkTab` | 提供網路請求清單、即時搜尋、Method/Status Chip 過濾器。 | - |
| [`network_detail_view.dart`](../../lib/src/ui/dashboard/tabs/network/network_detail_view.dart) | `NetworkDetailView` | 展示詳細請求/響應 Headers 與 Body，支持 Replay、複製為 cURL 或文字分享。 | - |
| [`navigator_tab.dart`](../../lib/src/ui/dashboard/tabs/navigator_tab.dart) | `NavigatorTab` | 以時間軸列表展示路由事件與傳參。 | - |
| [`database_tab.dart`](../../lib/src/ui/dashboard/tabs/database_tab.dart) | `DatabaseTab` | 數據源表瀏覽器。支援動態下拉切換不同的 `DatabaseBrowserSource`。 | - |
| [`table_rows_view.dart`](../../lib/src/ui/dashboard/tabs/database/table_rows_view.dart) | `TableRowsView` | 表格二維數據瀏覽器。支援動態加載（Load More）、點擊單元格查看/複製完整內容，以及點擊表頭排序。 | - |
| [`inspector_fab.dart`](../../lib/src/ui/widgets/inspector_fab.dart) | `InspectorFab` | 全螢幕飄移懸浮按鈕。使用 `GestureDetector.onPanUpdate` 與 `clamp` 實現拖曳邊界控制。 | - |
| [`magical_tap.dart`](../../lib/src/ui/widgets/magical_tap.dart) | `FlutterInspectorMagicalTap` | 透明手勢防護罩。可用於靜默包覆 App，監聽快速連擊（預設 5 次，每次小於 500ms）開啟 Dashboard。 | - |
| [`key_value_table.dart`](../../lib/src/ui/widgets/key_value_table.dart) | `KeyValueTable` | 通用的緊湊二欄式鍵值表格組件。 | - |
| [`detail_section.dart`](../../lib/src/ui/widgets/detail_section.dart) | `DetailSection`<br>`DetailKeyValueRow` | 共用的詳細資訊卡片與鍵值佈局組件。 | - |
| [`error_card.dart`](../../lib/src/ui/widgets/error_card.dart) | `ErrorCard` | 通用的錯誤狀態 UI 卡片組件。 | - |

### 7. 主題與樣式設計 (`lib/src/ui/theme/`)

| 檔案路徑 | 關鍵類別/列舉 | 單一職責 (Single Responsibility) | v1.1.0 混合時序軸重構實作現狀 |
| :--- | :--- | :--- | :--- |
| [`theme.dart`](../../lib/src/ui/theme/theme.dart) | - | Barrel 檔案，導出所有的主題樣式設計以進行集中化設計 tokens 管理。 | - |
| [`theme_color.dart`](../../lib/src/ui/theme/theme_color.dart) | `ThemeColor` | 定義 UI 語意色調色盤與配色常數。 | - |
| [`theme_padding.dart`](../../lib/src/ui/theme/theme_padding.dart) | `ThemePadding` | 定義邊距常數以統一內外間距。 | - |
| [`theme_radius.dart`](../../lib/src/ui/theme/theme_radius.dart) | `ThemeRadius` | 定義 UI 圓角半徑常數。 | - |
| [`theme_size.dart`](../../lib/src/ui/theme/theme_size.dart) | `ThemeSize` | 定義佈局尺寸與最大最小邊界限制。 | - |
| [`theme_spacing.dart`](../../lib/src/ui/theme/theme_spacing.dart) | `ThemeSpacing` | 定義排版間距以對齊元件位置。 | - |
| [`theme_textstyle.dart`](../../lib/src/ui/theme/theme_textstyle.dart) | `ThemeTextStyle` | 定義文字字型、粗細與樣式常數。 | - |

### 8. 擴充方法層 (`lib/src/extensions/`)

| 檔案路徑 | 關鍵類別/列舉 | 單一職責 (Single Responsibility) | v1.1.0 混合時序軸重構實作現狀 |
| :--- | :--- | :--- | :--- |
| [`log_level_color_extension.dart`](../../lib/src/extensions/log_level_color_extension.dart) | `LogLevelColor` | 定義 `LogLevelColor` 擴充方法，為不同的 `LogLevel` 級別指派對應的語意顏色。 | - |
