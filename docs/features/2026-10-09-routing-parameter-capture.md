# 路由參數擷取與深層連結追蹤 (Routing Parameter Capture)

## What & Why
在行動應用程式與 Flutter 開發中，深層連結 (Deep Link)、網址跳轉 (URL navigation) 或帶有參數的路由推送 (Route Push with arguments) 是核心且高頻的操作。然而，當深層連結帶錯參數、缺少必要欄位、或參數型別不符時，經常導致目標頁面狀態異常甚至拋出未攔截的例外而崩潰。

目前的 `FlutterInspectorNavigatorObserver` 僅能直通保存原始的 `route.settings.arguments`，在 UI 與日誌中也僅做簡單的 `toString()` 字串化輸出。這帶來了三個主要問題：
1. **無法自動擷取 URL/Uri 的 Query Parameters**：在現代宣告式路由（如 `go_router`）或具備 query string 的命名路由（如 `/order?orderId=123&from=notification`）中，參數藏在 `name` 或 `Uri` 內，目前的 observer 完全無法結構化提取。
2. **缺乏防禦與記憶體風險**：若開發者在 `arguments` 傳遞了龐大的自訂業務物件或包含循環參照的複雜結構，直接持有或未受控字串化可能引發記憶體佔用與效能問題。
3. **缺少敏感資訊防護**：若路由參數或 URL 查詢參數包含 Token、金鑰或個人憑證，未經遮蔽便直接呈現可能導致敏感資訊外洩。

本功能在 `NavigatorEntry` 新增不可變的結構化欄位 `routingParams` (`Map<String, String>?`)，並於 `FlutterInspectorNavigatorObserver` 攔截路由事件時，安全地從 URL Query Parameters 以及 Map arguments 提取純量基本型別（Primitives：`String`、`num`、`bool`）。同時提供字串長度截斷防護、非純量物件佔位標記（`<complex>`），並整合現有的 `redactSensitiveData` 機制對敏感參數進行遮蔽，在 `NavigatorTab`、`ConsoleTab` 及診斷匯出中清晰呈現。

## 使用者故事 (User Stories)
- 身為一位測試工程師 (QA) 或開發者，當我透過 Deep Link 或 App 內部導航進入頁面時，我希望在 Navigator 視圖（包含 Event History 與 Active Stack）能直接看到清晰的結構化路由參數（如 `orderId: 1001`, `tab: detail`），不需要手動人眼過濾整段原始物件字串。
- 身為一位開發者，當我使用包含 query string 的命名路由（例如 `/product?id=99&source=push`）或 `Uri` 時，我希望 Inspector 能自動解析出 Query Parameters，讓我能精準確認深層連結跳轉時帶入的參數值。
- 身為一位安全與架構專家，我希望路由參數的提取嚴格受限於純量基本型別，複雜物件安全標記為 `<complex>`，單一參數值有長度上限截斷防護，且當開啟機敏資訊遮蔽時自動遮蔽敏感鍵值（例如 `token`、`password` 等），確保對記憶體、效能與隱私安全零威脅。

## 驗收條件 (Acceptance Criteria)
1. **資料模型擴充 (`NavigatorEntry`)**:
   - 新增可選且不可變的 `Map<String, String>? routingParams` 欄位。
   - 保持 `arguments: Object?` 欄位向後相容。
   - 健全更新 `copyWith`、`operator ==`、`hashCode` 與 `toString`。
2. **安全純量擷取與防禦管線 (`RoutingParamExtractor` / Observer)**:
   - **URL Query Parameters 擷取**：若 `route.settings.name` 或 `arguments` 包含合法 Uri query string，解析其查詢參數為鍵值對。
   - **Arguments 純量提取**：若 `arguments` 為 `Map`，提取值為 `String`、`num`、`bool` 等基本型別；複雜物件或集合統一標註為 `'<complex>'`。
   - **字串長度截斷**：單一參數值超過 100 字元時進行截斷（如保留前 100 字元加上 `'...'`），防止巨大字串拖垮 UI 與記憶體。
   - **數量上限防禦**：擷取的參數總數具備上限保護（最多 20 個），避免惡意或大量參數引發效能問題。
   - **機敏資訊遮蔽**：整合現有 `redactSensitiveData` 設定；當啟用時，針對敏感參數名稱（例如包含 `password`, `token`, `secret`, `key`, `auth`, `credential` 等）遮蔽為 `'••••'`。
3. **UI 與輸出呈現 (`NavigatorTab` / `ConsoleTab` / `AgentPrompt`)**:
   - 在 `NavigatorTab` 的 `Event History` 項目中，當存在 `routingParams` 時清楚呈現參數鍵值（如 `Params: id=42, tab=profile`）。
   - 在 `NavigatorTab` 的 `Active Stack` 卡片中，適當展示目前各層 Route 的路由參數摘要。
   - 在 `AgentPrompt` 輸出診斷資訊時，若包含 `routingParams`，一併納入結構化描述。
4. **測試覆蓋**:
   - 單元測試：涵蓋 Uri query string 解析、Map arguments 基本型別擷取、複雜物件 `<complex>` 標註、字串超長截斷、敏感欄位遮蔽與大小寫不敏感比對。
   - Widget 測試：驗證帶有 `routingParams` 的 `NavigatorEntry` 在 `NavigatorTab`（Event History 與 Active Stack）中的正常呈現與空值優雅處理。

## 範圍邊界 (Scope & Boundaries)
- **Included (包含)**:
  - `NavigatorEntry` 的 `routingParams` 欄位與不可變支援。
  - 純量參數提取、URL Query 解析、截斷防護與機敏資訊遮蔽輔助邏輯。
  - `FlutterInspectorNavigatorObserver` 中的自動參數擷取與整合。
  - `NavigatorTab`、`ActiveStackView` 與 `AgentPrompt` 的視覺化與文字呈現。
  - 完整的單元測試與 Widget 測試。
- **Excluded (排除)**:
  - 不對深層自訂 Class 進行深度反射或遞迴序列化（避免循環參照與龐大記憶體佔用）。
  - 不覆寫或修改 Flutter 原生 Route 傳參行為。
  - 不引入任何外部路由套件（如 go_router、auto_route）之專屬相依，僅依賴 Flutter 核心與 Dart 原生 `Uri`。
