# 功能規格：flutter_inspector 多用途 App 內除錯工具框架

- 日期：2026-06-09
- 狀態：草稿
- 參考：[logarte](https://github.com/kamranbekirovyz/logarte)

---

## 1. 概述（What & Why）

作為 **Flutter app 開發者**，我需要一個**低侵入、模組化**的 in-app 除錯工具框架，讓我在開發與 QA 階段能快速檢視 log、網路請求、導航歷史與資料庫操作，而不需額外開啟外部工具或連接 DevTools。

本框架以 logarte 設計為 base，但範圍收斂為 **4 個內建 inspector（Log / Network / Navigator / Database）+ 1 個可選 custom tab**，並提供 **FAB 浮動按鈕**與 **Magical Tap（連點觸發）** 兩種入口機制。

---

## 2. 使用者故事

### US-01：初始化與附著
**作為** app 開發者，
**我希望** 在 app 啟動時建立全域 `FlutterInspector` 實例並呼叫 `attach(context)`，
**以便** inspector overlay（浮動按鈕）被掛載到 widget tree 上，且僅在 debug mode 可見。

**情境細節：**
- 在 `main()` 或 root widget 的 `initState` 呼叫 `flutterInspector.attach(context: context, visible: kDebugMode)`
- attach 後，螢幕上出現可拖曳的 FAB；點擊 FAB 打開 inspector dashboard

---

### US-02：透過 FAB 開啟 Dashboard
**作為** app 開發者或測試人員，
**我希望** 點擊浮動 FAB 即可開啟 inspector dashboard（全螢幕或半螢幕 modal），
**以便** 快速切換 tab 查看不同監控資訊。

**情境細節：**
- FAB 可拖曳、位置記憶（session 內）
- dashboard 有 tab bar，顯示 4 個內建 tab + 1 個可選 custom tab
- 關閉 dashboard 後 FAB 仍存在

---

### US-03：透過 Magical Tap 開啟 Dashboard（隱藏入口）
**作為** app 開發者，
**我希望** 在任意 widget 上包裹 `FlutterInspectorMagicalTap`，使用者連點 N 下後觸發開啟 dashboard，
**以便** 提供無 FAB 的隱藏入口（例如 production 中想保留隱藏偵錯方式）。

**情境細節：**
- N 預設為 5，可由 constructor 調整
- 連點計數有 timeout（例如 500ms 內未繼續則重置）
- 觸發後呼叫內部 `openDashboard(context)`

---

### US-04：手動開啟 Dashboard
**作為** app 開發者，
**我希望** 能直接呼叫 `flutterInspector.openDashboard(context)` 打開 dashboard，
**以便** 用程式邏輯控制何時顯示（例如偵測到錯誤時自動彈出）。

---

### US-05：Log Inspector（Console Tab）
**作為** app 開發者，
**我希望** 呼叫 `flutterInspector.log(message, [level])` 記錄一般 log，
**以便** 在 dashboard 的 **Console** tab 以列表形式檢視、篩選。

**情境細節：**
- 支援 level：verbose / debug / info / warning / error
- 列表顯示 timestamp、level、message
- 可按 level 篩選
- （可選）支援 tap 展開 stacktrace 或附加 data

---

### US-06：Network Inspector
**作為** app 開發者，
**我希望** 使用 `FlutterInspectorDioInterceptor` 自動記錄 Dio HTTP 請求與回應，
**以便** 在 dashboard 的 **Network** tab 檢視請求 URL、method、status code、duration、payload。

**情境細節：**
- interceptor 攔截 request / response / error
- 每筆紀錄包含：timestamp、method、url、statusCode、duration、requestHeaders、requestBody、responseHeaders、responseBody（可選截斷）
- 點擊單筆可展開詳細資訊
- **dio 為可選相依**——使用者未安裝 dio 時，interceptor class 不可導致編譯錯誤

---

### US-07：Navigator Inspector
**作為** app 開發者，
**我希望** 使用 `FlutterInspectorNavigatorObserver` 追蹤路由 push / pop / replace 事件，
**以便** 在 dashboard 的 **Navigator** tab 檢視導航歷史。

**情境細節：**
- 紀錄 route name、arguments、timestamp、action (push/pop/replace/remove)
- 列表依時間倒序顯示
- 可展開查看 route arguments

---

### US-08：Database Inspector
**作為** app 開發者，
**我希望** 呼叫 `flutterInspector.database(operation, table, [data])` 記錄 DB 操作，
**以便** 在 dashboard 的 **Database** tab 檢視 CRUD 活動（insert / update / delete / query）。

**情境細節：**
- 紀錄 timestamp、operation type、table name、affected data（JSON 格式）
- 列表顯示，可按 table 或 operation 篩選
- 不直接整合任何 ORM（如 sqflite、drift）——僅提供手動記錄 API

---

### US-09：Custom Tab（可選）
**作為** app 開發者，
**我希望** 在初始化時傳入 `customTab` widget，
**以便** 在 dashboard 顯示第 5 個 tab，用於 app-specific 的自訂監控畫面。

**情境細節：**
- customTab 為 Widget?，傳入則顯示，否則 tab bar 只有 4 個 tab
- tab title 可自訂（預設 "Custom"）
- 內容完全由使用者控制

---

## 3. 驗收條件（Given/When/Then）

### AC-01：初始化與 FAB 顯示
**Given** app 在 debug mode 執行
**When** 呼叫 `flutterInspector.attach(context: context, visible: true)`
**Then** 螢幕上出現可拖曳的 FAB

### AC-02：FAB 開啟 Dashboard
**Given** FAB 已顯示
**When** 點擊 FAB
**Then** dashboard modal 開啟，顯示 4 個內建 tab（Console / Network / Navigator / Database）

### AC-03：Custom Tab 顯示
**Given** 初始化時傳入 `customTab: MyCustomWidget()`
**When** dashboard 開啟
**Then** tab bar 顯示第 5 個 tab（標題可自訂），內容為 MyCustomWidget

### AC-04：Magical Tap 觸發
**Given** 某 widget 被 `FlutterInspectorMagicalTap(tapCount: 5)` 包裹
**When** 使用者在該 widget 上連點 5 下（每下間隔 < 500ms）
**Then** dashboard 自動開啟

### AC-05：Log 記錄與顯示
**Given** 呼叫 `flutterInspector.log('Test message', level: LogLevel.warning)`
**When** 開啟 dashboard 的 Console tab
**Then** 列表中顯示該筆 log（含 timestamp、warning level icon、message）

### AC-06：Log Level 篩選
**Given** Console tab 有多筆不同 level 的 log
**When** 選擇「只顯示 error」篩選器
**Then** 列表僅顯示 level=error 的項目

### AC-07：Network 請求記錄（Dio）
**Given** Dio 實例已加入 `FlutterInspectorDioInterceptor`
**When** 發送一個 GET 請求並收到 200 回應
**Then** Network tab 顯示該筆請求（method=GET、url、statusCode=200、duration）

### AC-08：Network 請求詳情展開
**Given** Network tab 有一筆請求紀錄
**When** 點擊該筆紀錄
**Then** 展開顯示 requestHeaders、requestBody、responseHeaders、responseBody

### AC-09：Dio 可選——未安裝 dio 時編譯不報錯
**Given** host app 的 pubspec 未列 dio 依賴
**When** 只 import `flutter_inspector.dart`（不使用 interceptor）
**Then** app 編譯成功，無 missing import 錯誤

### AC-10：Navigator Observer 追蹤
**Given** MaterialApp 的 navigatorObservers 含 `FlutterInspectorNavigatorObserver`
**When** Navigator.push 一個新 route
**Then** Navigator tab 出現該筆 push 紀錄（route name、arguments、timestamp）

### AC-11：Database 操作記錄
**Given** 呼叫 `flutterInspector.database(DatabaseOp.insert, 'users', {'id': 1, 'name': 'Alice'})`
**When** 開啟 Database tab
**Then** 顯示該筆 insert 紀錄（table=users、data JSON）

### AC-12：Dashboard 關閉後 FAB 仍存在
**Given** dashboard 已開啟
**When** 關閉 dashboard（點擊 X 或返回）
**Then** FAB 仍顯示於螢幕上

### AC-13：openDashboard 手動觸發
**Given** inspector 已 attach
**When** 程式碼呼叫 `flutterInspector.openDashboard(context)`
**Then** dashboard 開啟

### AC-14：Release Mode 下 FAB 預設隱藏
**Given** app 在 release mode 執行
**When** 呼叫 `attach(context: context, visible: kDebugMode)`
**Then** FAB 不顯示（kDebugMode = false）

---

## 4. 範圍邊界

### 4.1 本輪包含（In Scope）

| 項目 | 說明 |
|------|------|
| 核心類別 `FlutterInspector` | singleton 或 factory instance；提供 attach / log / network / database / openDashboard API |
| FAB Overlay | 可拖曳浮動按鈕，點擊開啟 dashboard |
| Magical Tap Widget | `FlutterInspectorMagicalTap`，連點 N 下觸發 |
| Dashboard UI | Tab-based modal/fullscreen；4 個內建 tab + 1 custom tab slot |
| Console Tab | log 列表、level 篩選 |
| Network Tab | HTTP 請求列表、詳情展開 |
| Navigator Tab | 路由歷史列表 |
| Database Tab | DB 操作列表（手動記錄 API） |
| Dio Interceptor | `FlutterInspectorDioInterceptor`（dio 為可選相依） |
| Navigator Observer | `FlutterInspectorNavigatorObserver` |
| Custom Tab | 初始化時傳入 Widget? |

### 4.2 本輪不包含（Out of Scope）

| 項目 | 理由 |
|------|------|
| Shake 偵測入口 | 使用者明確排除 |
| 開放式 registerTab API | 設計決策：固定 4 + 1，非可無限擴充 |
| Password 鎖 | 使用者明確排除——完全不提供 password / ignorePassword API |
| 資料持久化（存磁碟） | MVP 僅 in-memory；後續可擴充 |
| 雲端上傳 / 分享功能 | 超出 MVP 範圍 |
| ORM 直接整合（sqflite/drift） | Database inspector 僅提供手動 API，不綁定特定 ORM |
| 自動 HTTP client 偵測 | 僅提供 Dio interceptor；http package 或其他 client 需後續支援 |

---

## 5. 非功能需求

### 5.1 Dio 可選相依

**問題**：若將 dio 列為 flutter_inspector 的 dependency，會強制所有使用者安裝 dio，即使他們用 http 或其他 client。

**解決方案**：
1. `FlutterInspectorDioInterceptor` 放在獨立檔案 `lib/src/integrations/dio_interceptor.dart`
2. 該檔案 `import 'package:dio/dio.dart'`
3. **不在** `flutter_inspector.dart` 主 export 中 re-export 此檔案
4. 使用者需顯式 import：`import 'package:flutter_inspector/src/integrations/dio_interceptor.dart';`
5. 若使用者未安裝 dio 且不 import interceptor 檔案，則不會觸發 missing import 錯誤
6. pubspec.yaml **不**將 dio 列為 dependency（使用者自行安裝）

**替代方案（若上述無法滿足 pub.dev 規範）**：
- 將 dio interceptor 拆成獨立 package `flutter_inspector_dio`
- 本輪先採方案 1，實作階段驗證可行性

### 5.2 Debug / Release 行為差異

| 行為 | Debug Mode | Release Mode |
|------|------------|--------------|
| FAB 顯示 | `visible` 參數控制（預設 `kDebugMode`） | 依 `visible` 參數，建議傳 `false` |
| Log 記錄 | 正常記錄 | 正常記錄（但通常 attach visible=false，無法查看） |
| 效能 overhead | 可接受 | 應最小化（in-memory buffer 有上限） |

### 5.3 對 Host App 侵入性最小化

1. **無強制依賴**：除 Flutter SDK 外，無 hard dependency
2. **可選 attach**：不呼叫 attach 則 package 完全無副作用
3. **無全域攔截**：不自動 hook 任何系統行為；使用者需顯式加入 interceptor / observer
4. **Buffer 上限**：in-memory log / network / database 紀錄有條數上限（例如 500 筆），避免記憶體膨脹
5. **無 Platform Channel**：純 Dart + Flutter widget，無 native 依賴

### 5.4 效能考量

- Log / Network / Database 寫入為 O(1) append 到 ring buffer
- Dashboard UI lazy load（未開啟不渲染）
- 列表使用 `ListView.builder` 虛擬化

---

## 6. 待釐清事項（Questions for User）

> 以下決策已由使用者確認，列為設計基準。

### D1：Password 鎖 —— 完全移除
不提供 `password` / `ignorePassword` 任何 API。dashboard 入口無鎖。

### D2：Dashboard 樣式 —— 全螢幕 modal
Dashboard 以全螢幕 modal 開啟（類似 logarte 的 entry point）。

### D3：Buffer 上限 —— 每 inspector 500 筆 FIFO
每個 inspector 各保留最新 500 筆，超過時 FIFO 淘汰最舊紀錄。

### D4：Magical Tap 連點次數 —— 預設 5 下
`FlutterInspectorMagicalTap` 預設連點 5 下觸發，可由 constructor 調整。

### D5：Network body 截斷 —— 10KB
request / response body 超過 10KB 時截斷，顯示前 10KB + "[truncated]"。

---

## 7. 附錄：術語對照

| 本框架 | logarte 對應 |
|--------|--------------|
| `FlutterInspector` | `Logarte` |
| `FlutterInspectorDioInterceptor` | `LogarteDioInterceptor` |
| `FlutterInspectorNavigatorObserver` | `LogarteNavigatorObserver` |
| `FlutterInspectorMagicalTap` | `LogarteMagicalTap` |
| Dashboard | Console (logarte 的 entry point UI) |
| Console Tab | Console tab |
| Network Tab | API Request tab |
| Navigator Tab | (無直接對應，為本框架新增) |
| Database Tab | (無直接對應，為本框架新增) |
| Custom Tab | customTab 參數 |

---

## 8. 版本紀錄

| 版本 | 日期 | 變更 |
|------|------|------|
| 0.1 | 2026-06-09 | 初稿 |
