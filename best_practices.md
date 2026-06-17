# Flutter/Dart 專案 Best Practices

本檔供 Qodo Merge 的 `/improve` 與 `/review` 自動載入，作為 Code Review 與程式碼建議的審查基準。
語言與術語、評論嚴重度、結尾創作規範等 review 行為設定於 `.pr_agent.toml` 的 `extra_instructions`。

Flutter 版本 3.35

## 1. 格式化 (Formatting)

- 始終使用 `dart format` 自動格式化程式碼。
- 建議行長度限制在 80 個字元以內。

## 2. 命名規範 (Naming Conventions)

- **類別、列舉、型別定義**：使用 `PascalCase`（`MyAwesomeWidget`、`enum Status`、`typedef OnTapCallback`）。
- **函式、方法、變數**：使用 `camelCase`（`myFunction()`、`String userName`）。
- **常數**：通常 `camelCase`；全域或跨檔共享可用 `k` 前綴（`kDefaultPadding`）或 `SCREAMING_SNAKE_CASE`（`API_BASE_URL`），皆可接受。
- **檔案名**：使用 `snake_case`（`my_widget.dart`）。
- **庫前綴**：命名衝突時用 `snake_case` 前綴（`import 'package:path/path.dart' as p;`）。

### 2.6. 建構式 (Constructors)

- 命名建構式與 factory 建構式皆用 `camelCase`，於類別名稱後加點號（`User.guest()`、`User.fromJson()`）。
- 成員預設值用 `=` 設定，可在建構式參數或類別成員中設定。
- **Singleton**：私有建構式 + 靜態實例變數，參考 GetIt 提供靜態 getter `I`。

```dart
class MySingleton {
  MySingleton._privateConstructor();
  static final MySingleton _instance = MySingleton._privateConstructor();
  factory MySingleton() => _instance;
  static MySingleton get I => _instance;
}
```

## 3. 導入 (Imports)

按 `dart:` → `package:` → relative 順序組織，每區塊以空行分隔。只導入實際需要的庫。

## 4. 註解 (Comments)

### 4.1. 文件註解（使用 `///`）

**必須添加**：對外公開的 API、複雜邏輯、配置類別（如 API 介面）、抽象類別與介面。

**不需添加**：內部實作類別、測試相關類別（Mock 等）、簡單資料類別（Entity / Dto / Model）、BLoC Event 與 State 類別（註解寫在 `*Bloc` class 即可）。

### 4.2. 行內註解（使用 `//`）

解釋複雜或非顯而易見的邏輯。

### 4.3. TODO 註解

使用 `// TODO:` 標記待辦。

## 5. 程式碼結構 (Code Structure)

### 5.1. 類別成員順序

常數 → 靜態變數 → 實例變數 → 建構函式 → 公共方法 → 私有方法 → `build` 方法（Widget）。

### 5.2. 使用 `final` 和 `const`

- 盡可能使用 `final` 提高不可變性與效能。
- `const` 用於編譯時常數；建構函式不強迫使用 `const`（flutter_lints 5.0.0 已不再強制）。

**⚠️ 規範優先權說明**：本檔為 Qodo Merge 審查參考依據。當與 `.agents/rules/flutter-rules.md` 的編碼規則衝突時（如 const 使用程度），以各自工具的適用範圍為準：Qodo 審查依本檔判準，AI agent 編碼遵循 `.agents/rules` 規範。

### 5.3. 避免深層巢狀

以提取方法、衛語句 (guard clauses) 等方式降低巢狀深度。

```dart
// Good
void func() {
  if (user == null || !user.isActive) return;
  doSomething();
}
```

## 6. 錯誤處理 (Error Handling)

對可能拋出異常的程式碼使用 `try-catch`，並針對具體例外型別處理（`on FormatException catch (e)`）。

## 7. Flutter 特定建議

- **Widget 拆分**：將複雜 Widget 拆成更小、單一職責、可重用的 Widget。
- **`const` 建構函式**：已於 flutter_lints 5.0.0 deprecated，不再強制。
- **避免在 `build` 中執行昂貴操作**：將計算/網路請求移至 `initState`、`didChangeDependencies` 或狀態管理層。
- **資源管理**：正確釋放 `AnimationController`、`StreamSubscription` 等。

### 7.4. 狀態管理 (State Management)

選擇 **BLoC** 作為主要狀態管理方案。

- 每個 BLoC 專注單一職責 (SRP)；以 Events 觸發狀態變更、以 State 表示 UI 狀態；BLoC 與 UI 分離。
- BLoC 命名具描述性（`GetCartCountBloc`）。
- 為每個 BLoC 編寫單元測試，使用 `bloc_test`。
- **BLoC Events**：
  - 用 `abstract class` 定義事件基類，子類為具體事件。
  - 使用 `equatable`，覆寫 `props` 包含所有相關屬性（基於內容而非引用比較）。
  - 事件與 Bloc 同前綴（`CartBloc` → `CartLoad`）。
  - 避免 Query 事件處理過多邏輯：建議在 Bloc 中以私有方法 `_onCompleted`、`_onFailed` 處理（符合 BLoC 規範，避免事件迴圈）。

## 8. 測試 (Testing)

- 至少編寫單元測試；Widget 測試與整合測試為可選。
- 測資與測試邏輯分離，放在同檔的 `_Data` class。
- 通用測資放 `test/mock/mock_common_message.dart` 供多檔共用。
- 測試函式名稱清楚描述目的，以 `test` / `group` 組織。

## Y. 其他

- **避免魔術數字/字串**：重複使用的數字或字串定義為具名常數（測試除外）。
- **保持函式簡潔**：每個函式只做一件事。
- **Logger 規則**：使用 `logger` 套件，依環境設定日誌等級。`Logger().d` 為 debug mode only，release 不輸出。

## X. AI Review Decisions

### X.1. Retrofit

依 Domain 拆分不同 API，透過 Dio 管理 Base URL、Headers、Interceptors，使用 Retrofit 生成 API 客戶端。

- 不在 `@RestApi()` 使用 `baseUrl` 參數（由 Dio 統一管理）。
- Path 宣告需含 `/` 前綴，不在 `@GET`、`@POST` 重複 Base URL。

```dart
@RestApi()
abstract class UserApi {
  @GET('/users')
  Future<List<User>> getUsers();
}
```

### X.2. DTO / Entity / Model 轉換

- 大多數情境建議透過 `fromJson` / `toJson` 完成轉換以減少程式碼（接受 type safety 的取捨）。
- 僅在需要複雜轉換或更高效能時，才直接在建構函式中映射欄位。
