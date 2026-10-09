# 實作計畫：路由參數擷取與深層連結追蹤 (Routing Parameter Capture)

## 實作方向與 Trade-off 分析
1. **方案 A：對 `arguments` 進行全遞迴反射與 JSON 序列化**
   - *優點*: 可嘗試序列化任意複雜物件。
   - *缺點*: 存在嚴重的效能與記憶體開銷。物件可能包含 `BuildContext`、不可序列化實體或循環參照，容易引發例外或記憶體洩漏，嚴重違反 Linus「好品味」與簡潔原則。
2. **方案 B：純量白名單提取 + URL Query 解析 + 邊界防禦與遮蔽（選定方案）**
   - *優點*: 
     - **型別安全與輕量不可變**：專注於純量鍵值對（`String`、`num`、`bool` 與 `Uri.queryParameters`），非純量統一標記為 `<complex>`，徹底杜絕循環參照與龐大記憶體佔用。
     - **邊界防禦**：單一字串長度上限截斷（100 字元）與總參數量上限（20 筆），杜絕邊界效能問題。
     - **機敏遮蔽**：整合現有 `redactSensitiveData` 機制，對敏感鍵值進行 `••••` 遮蔽。
     - **零破壞相容性**：保留既有 `NavigatorEntry.arguments: Object?`，不影響任何現有呼叫端。
   - *缺點*: 不展示深層巢狀自訂物件的內部欄位，但排查導航與深層連結的本質就是確認傳遞之純量標識（如 `id`, `tab`, `url`），此 Trade-off 務實且精準。

**最終選擇**: 採用方案 B。

## 資料結構與架構設計
- **核心資料模型 (`NavigatorEntry`)**:
  - 新增欄位：`final Map<String, String>? routingParams;`
  - 建構函式支援可選具名參數 `this.routingParams`。
  - `copyWith`、`operator ==`（使用 `mapEquals`）、`hashCode`、`toString` 健全支援。
- **純量擷取工具 (`RoutingParamExtractor`)**:
  - 獨立純函式類別 `lib/src/utils/routing_param_extractor.dart`。
  - 函式簽章：
    ```dart
    Map<String, String>? extractRoutingParams({
      String? routeName,
      Object? arguments,
      bool redact = true,
      int maxStringLength = 100,
      int maxEntries = 20,
    });
    ```
  - 解析步驟：
    1. **URL Query 解析**：若 `routeName` 或 `arguments`（為 `Uri` 或帶有 `?` 之 `String`）包含 query string，透過 `Uri.tryParse` 提取 `queryParameters`。
    2. **Map Arguments 純量提取**：若 `arguments is Map`，將鍵轉換為字串，值若為 `String`、`num`、`bool` 則轉為字串並做長度截斷；若非純量則標記為 `'<complex>'`。
    3. **合併與上限防禦**：最多容納 `maxEntries`（20 個）條目。
    4. **機敏資訊遮蔽**：若 `redact == true`，當鍵名稱包含 `password`、`token`、`secret`、`apikey`、`api_key`、`auth`、`credential`、`access_token`、`pin` 時，其值替換為 `kRedactedValue` (`'••••'`)。
    5. **不可變包裝**：非空時回傳 `Map.unmodifiable(result)`，無參數時回傳 `null`。
- **Observer 串接 (`FlutterInspectorNavigatorObserver`)**:
  - 在 `_record` 中，傳入 `routeName`、`route.settings.arguments` 與 `_inspector.redactSensitiveData` 調用 `extractRoutingParams`，並傳遞至 `NavigatorEntry`。
- **UI 與診斷呈現**:
  - `NavigatorTab`:
    - `Event History`：於 `subtitle` 展示結構化參數摘要（如 `Params: orderId=123, tab=detail`）。
    - `_ActiveStackView`：若存在 `routingParams`，在卡片副標題適當展示參數摘要。
  - `AgentPrompt`:
    - 若 `NavigatorEntry.routingParams` 不為空，將參數鍵值格式化輸出至 prompt 上下文。

## 檔案異動清單
1. `lib/src/utils/routing_param_extractor.dart` (新增):
   - 實作純量提取、Uri Query 解析、長度截斷與機敏資訊遮蔽。
2. `lib/src/models/navigator_entry.dart`:
   - 增加不可變欄位 `routingParams`，維護 equality 與 copyWith。
3. `lib/src/observers/navigator_observer.dart`:
   - 於 `_record` 中整合 `extractRoutingParams`。
4. `lib/src/ui/dashboard/tabs/navigator_tab.dart`:
   - 於 `Event History` 與 `Active Stack` 中格式化呈現 `routingParams`。
5. `lib/src/utils/agent_prompt.dart`:
   - 於 NavigatorEntry 區塊加入 `routingParams` 輸出。
6. `test/utils/routing_param_extractor_test.dart` (新增):
   - 測試 Query String 解析、Map 純量提取、長度截斷、`<complex>` 標註、機敏遮蔽。
7. `test/models/navigator_entry_test.dart`:
   - 測試 `routingParams` 欄位相等性、copyWith 與不可變性。
8. `test/observers/navigator_observer_test.dart`:
   - 測試 Observer 記錄導航事件時正確填入 `routingParams`。
9. `test/ui/tabs/navigator_tab_test.dart`:
   - 測試 `NavigatorTab` 於各視圖下正確渲染路由參數文字。

## 任務拆分
1. **任務 1：實作 `RoutingParamExtractor` 工具與單元測試**
   - 檔案: `lib/src/utils/routing_param_extractor.dart`, `test/utils/routing_param_extractor_test.dart`
   - 動作:
     - 實作 Query string 與純量參數提取、截斷、數量上限與機敏遮蔽。
     - 撰寫完整的覆蓋單元測試。
2. **任務 2：擴充 `NavigatorEntry` 模型並整合 Observer**
   - 檔案: `lib/src/models/navigator_entry.dart`, `lib/src/observers/navigator_observer.dart`, `test/models/navigator_entry_test.dart`, `test/observers/navigator_observer_test.dart`
   - 動作:
     - 新增 `routingParams` 欄位並完善 equality / copyWith。
     - 於 `FlutterInspectorNavigatorObserver` 注入參數提取。
     - 更新與新增單元測試。
3. **任務 3：更新 `NavigatorTab` UI 與 `AgentPrompt` 呈現並補齊 Widget 測試**
   - 檔案: `lib/src/ui/dashboard/tabs/navigator_tab.dart`, `lib/src/utils/agent_prompt.dart`, `test/ui/tabs/navigator_tab_test.dart`
   - 動作:
     - 於 Event History 與 Active Stack 呈現參數摘要。
     - 於 `AgentPrompt` 輸出 `routingParams`。
     - 執行並確保全部測試綠燈。
