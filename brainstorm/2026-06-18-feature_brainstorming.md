# 🔍 Flutter Inspector 功能優化與新增：腦力激盪報告

> 「差勁的程式員只擔心代碼，優秀的程式員關心數據結構。」 —— Linus Torvalds
> 
> 在這份報告中，我們以「Linus Torvalds 的好品味」與「實用主義」為核心，重新審視 `flutter_inspector` 的底層架構與 UI 實現。我們拒絕過度設計與無謂的複雜度，只關注如何以最簡潔、最優雅的方式解決真實開發中的痛點。

---

## 🐧 核心哲學審查

在提出任何新功能或優化之前，我們先問自己三個鐵律問題：
1. **這是一個真實的問題，還是想像出來的？** 
   - 答：Console 日誌無法搜尋與過濾、無法檢視本機快取（Key-Value Storage）、缺乏裝置與環境資訊，這些都是開發與 QA 過程中的真實痛點。
2. **有沒有更簡單的方法？**
   - 答：有。例如檢視本機快取，我們不需要發明新的 Tab UI，而是直接利用既有的 `DatabaseBrowserSource` 抽象，將其包裝為虛擬 Database Table。
3. **這會破壞任何東西嗎？**
   - 答：向後兼容性是神聖不可侵犯的。所有優化均為擴充式，絕不改動已有的 `FlutterInspector` 公開 API。

---

## 🛠️ 第一部分：現有功能優化 (Optimizations)

### 1. Console Tab：引入搜尋與日誌級別過濾 (LogLevel Filter)
* **現狀評級**：🔴 **垃圾**
* **致命缺陷**：目前 `ConsoleTab` 只有一個簡單的日誌列表，提供 refresh 和 delete。當日誌積累到上百條時，沒有搜尋，也沒有 LogLevel 的篩選，實用性極差。
* **Linus 式優化方案**：
  - **數據結構**：不需要改動。
  - **實作方式**：在 `ConsoleTab` 頂部加入一個簡潔的搜尋欄，以及類似 `NetworkTab` 的過濾晶片（Filter Chips）來篩選 `LogLevel`（verbose, debug, info, warning, error）。
  - **程式碼品味**：直接沿用 `NetworkTab` 的篩選邏輯，重用過濾晶片 UI，保持設計語彙一致，避免無謂的程式碼膨脹。

### 2. Console Tab：新增日誌詳情底欄 (Log Detail BottomSheet)
* **現狀評級**：🔴 **垃圾**
* **致命缺陷**：目前點擊 `ConsoleTab` 中的 ListTile 沒有任何反應。日誌內含的 `stackTrace` 以及附加的結構化 `data` 根本無法在 UI 上檢視，完全浪費了 `LogEntry` 的數據設計。
* **Linus 式優化方案**：
  - 當用戶點擊某條日誌時，使用 `showModalBottomSheet` 彈出詳情面板。
  - 面板中清晰展示完整的日誌訊息、格式化後的附屬 `data`（以 JSON 縮排顯示），以及可滾動且可一鍵複製的 `stackTrace`（堆疊追蹤）。
  - 拒絕為此編寫獨立頁面，以 BottomSheet 重用機制保持斯巴達式的精簡。

### 3. TableRowsView：新增關鍵字過濾與資料匯出
* **現狀評級**：🟡 **平庸**
* **致命缺陷**：目前 `TableRowsView` 只能看不能搜，當資料庫表稍微龐大，尋找特定 row 就變成折磨。
* **Linus 式優化方案**：
  - 在 `TableRowsView` 的 AppBar 下方新增簡易的 Local 關鍵字過濾輸入框（僅過濾當前已載入內存的 page rows，避免頻繁發送 DB query 造成卡頓）。
  - 頂部 Actions 新增「匯出為 CSV/JSON」按鈕，方便開發者將虛擬或實體表數據直接拉出。

### 4. RingBuffer 性能微調
* **現狀評級**：🟢 **好品味**
* **審查分析**：目前 `RingBuffer` 使用 `_items.removeAt(0)` 來做先進先出（FIFO）的移除。對於緩衝上限設為 500 的 debugger 來說，這是極小的記憶體挪動，在 Dart/Flutter 內核中性能損耗幾乎為零。
* **改進方向**：無須為了「理論完美」將其重構為雙指針環形數組（Circular Buffer）。保持現狀，避免為了微不足道的性能提升而增加程式碼複雜度。但可以為 `ListTile` 在 UI 中加入 `const` 修飾以避免不必要的 Element Rebuild。

### 5. TableRowsView 大數據渲染優化
* **現狀評級**：🟡 **平庸**
* **致命缺陷**：`TableRowsView` 內部的數據表直接使用 `DataTable`。當數據行數較多時（如 fetch 200 筆 row），沒有虛擬化滾動（Virtual Shrink/Viewport），會導致實體渲染負載過高。
* **Linus 式優化方案**：
  - 考慮到 `DataTable` 本身不支援高度虛擬化，限制單頁載入上限（如從 200 降至 50，點擊 Load More 再加載），或改為基於分頁按鈕（Pagination Controls）的設計，確保不會因為一次加載過多數據導致手機 UI 凍結。

---

## 🚀 第二部分：新增功能規劃 (New Features)

### 1. 本機鍵值存儲監控 (Key-Value Storage Browser)
* **實用性驗證**：在 Flutter 開發中，檢查 `SharedPreferences` 的寫入是高頻操作。
* **好品味設計（關鍵洞察）**：
  > 「不要為了特殊情況寫特殊的 UI。」
  我們拒絕為此新增一個「Storage Tab」和一整套 key-value 編輯介面。
  **極簡做法**：我們只需要實作一個 `SharedPreferencesBrowserSource implements DatabaseBrowserSource`！
  - `listTables()` 返回包含一個名為 `shared_preferences` 的虛擬表。
  - `fetchRows()` 將讀取的所有鍵值對轉化為 `columns = ['Key', 'Value']`，並將每對 key-value 作為一列（row）返回。
  - **優勢**：不需要改動任何 UI 程式碼，直接重用 `DatabaseTab` 與 `TableRowsView`！開發者可以直接在 Database 頁面中瀏覽、關鍵字搜尋、排序，並點擊 cell 複製 SharedPreferences 的值。

### 2. 網絡請求重放功能 (Network Replay/Retry)
* **實用性驗證**：調試 API 時，常需要對同一個端點反覆測試。如果每次都要在 UI 上重新觸發按鈕或重走業務流程，效率極低。
* **極簡設計**：
  - 在 `NetworkDetailView` 的 Actions 中加入一個「Replay」按鈕。
  - 當用戶點擊時，利用攔截器或內部的 HttpClient，以相同的 Method、URL、Headers 及 Body 重新發送請求，並自動將新產生的請求作為一個獨立的 `NetworkEntry` 記錄進 inspector 緩衝區。
  - 這對後端介接調試是巨大的生產力解放。

### 3. 當前路由堆疊可視化 (Current Navigator Stack Visualizer)
* **實用性驗證**：目前的 `NavigatorTab` 只是個流水帳日誌。但我們常常需要確認「當前頁面底下壓了哪些 Route」。
* **極簡設計**：
  - 在 `NavigatorTab` 頂部加入一個「當前頁面堆疊 (Active Stack)」的摺疊面板。
  - 利用 `NavigatorObserver` 的 push/pop 即時維護一個表示當前 Activity Stack 的 List。
  - 在面板中以麵包屑（Breadcrumbs）或垂直疊加卡片的形式，簡潔地顯示從 Root 頁面到 Top 頁面的路由鏈（例如：`SplashPage` ➔ `LoginPage` ➔ `HomePage` ➔ `ProductDetailPage`），讓開發者一眼看清頁面有沒有被重複 Push，防範記憶體洩漏。

### 4. 應用與裝置資訊面板 (App & Device Info Screen)
* **實用性驗證**：QA 在提報 Bug 時，頻繁需要截圖並手動附上設備資訊、OS 版本、App 版本、Build 號。
* **極簡設計**：
  - 在 `DashboardModal` 中，新增一個「Info」分頁。
  - **數據源**：引入 `package_info_plus` 與 `device_info_plus`（這兩個是 Flutter 官方維護的 standard plugins）。
  - **功能**：列出 App Name, Version, Build Number, OS, Device Model, Locale，並在底部提供一個 **「Copy Diagnostics Report」** 按鈕，一鍵將所有裝置資訊 + 當前導航歷史（Navigator History）複製為 Markdown 格式，極大提升 Bug 申報效率。

### 5. 多平台快捷鍵喚醒與手勢擴充
* **實用性驗證**：目前開啟 Overlay 依賴 `magicalTapCount`（狂點螢幕 5 下）或 Draggable FAB。但在 Web 或 Desktop 模擬器上，滑鼠連擊 5 下體驗很差，且 FAB 容易遮擋測試按鈕。
* **極簡設計**：
  - 在 Web / Desktop 平台，支援鍵盤快捷鍵喚醒（例如：`Ctrl + Option + I`）。
  - 支援觸發手勢的客製化（如雙指長按 2 秒），讓開發者可以根據自己的 App Layout 避開手勢衝突。

### 6. 網絡日誌分享優化：匯出為 JSON/HAR 檔案
* **實用性驗證**：單條請求複製 cURL 很棒，但當需要把整個網絡請求序列發給後端時，一條條複製非常愚蠢。
* **極簡設計**：
  - 在 `NetworkTab` 頂部加入一個「匯出」按鈕。
  - 將當前緩衝區內的所有網絡請求序列（`NetworkEntry` 列表）序列化為一個標準的 JSON 檔案，利用 `share_plus` 開啟系統分享面板，將檔案直接發送到 Slack/Email 或是通訊軟體。

---

## ❌ 拒絕實現的「垃圾」功能 (Anti-Features)

為了防止專案走向「微核心」或「過度工程」的泥潭，我們明確拒絕以下功能：

1. **API Mocking (模擬 API 回應)**：
   - *拒絕原因*：在 in-app overlay 中實現 API Mocking 需要在 Dio 攔截器中注入極其複雜的配置、映射規則甚至動態腳本執行。這會導致調試工具本身的代碼量翻倍，且極易因為 debug 庫的 Bug 導致用戶的 userspace（正式網絡請求）中斷或崩潰。**這嚴重違反了「Never break userspace」的鐵律**。API Mocking 應該交給專門的外部 Proxy 工具（如 Proxyman, Charles）或後端 Mock 服務，而不是塞進一個 Debug Overlays。
2. **運行期 UI 佈局調整器 (Live Layout Editor)**：
   - *拒絕原因*：在手機螢幕上用手指去點選 Widget、調整 Padding 和 Margin 是一場災難。Flutter 官方的 DevTools 已經提供了非常強大的 Widget Inspector。我們不應該在 in-app 套件中重複造一個低配版且難以維護的輪子。

---

## 📅 下一步實作路徑 (Implementation Plan)

若使用者確認此設計方向，我們將按以下順序逐步實施：
1. **第一階段**：實作 `SharedPreferencesBrowserSource`，零 UI 變更即刻上線 SharedPreferences 檢視功能。
2. **第二階段**：優化 `ConsoleTab`，加入 LogLevel Chips 過濾、關鍵字搜尋，以及 `LogDetailBottomSheet`。
3. **第三階段**：新增 `InfoTab`，整合 App 與裝置診斷資訊一鍵複製，並擴展 Web/Desktop 快捷鍵支援。
4. **第四階段**：強化 [NavigatorTab](file:///Users/yomiry/StudioWorkspace/flutter_inspector/lib/src/ui/dashboard/tabs/navigator_tab.dart)，實作「Active Stack」導航樹狀堆疊顯示；為 [NetworkTab](file:///Users/yomiry/StudioWorkspace/flutter_inspector/lib/src/ui/dashboard/tabs/network_tab.dart) 加上 Replay 與批次匯出功能。
