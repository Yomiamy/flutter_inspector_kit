---
trigger: always_on
---

# Flutter/Dart 專案 Style Guide

本 Style Guide 旨在為 Flutter/Dart 專案提供一致的程式碼風格和最佳實踐，以提高程式碼的可讀性、可維護性和協作效率。

Flutter 版本 3.35

## 1. 格式化 (Formatting)

### 1.1. 使用 `dart format`

始終使用 `dart format` 工具來自動格式化程式碼。這確保了所有程式碼都遵循 Dart 官方推薦的格式。

```bash
dart format .
```

### 1.2. 行長度 (Line Length)

建議將行長度限制在 80 個字元以內。這有助於在大多數螢幕上保持程式碼的可讀性，並減少水平滾動。

## 2. 命名規範 (Naming Conventions)

### 2.1. 類別、列舉、型別定義 (Classes, Enums, Type Definitions)

使用 `PascalCase` (大駝峰命名法)。

```dart
class MyAwesomeWidget {
  /*...*/
}
enum Status { /*...*/ }

typedef OnTapCallback = void Function();
```

### 2.2. 函式、方法、變數 (Functions, Methods, Variables)

使用 `camelCase` (小駝峰命名法)。

```dart
void myFunction() {
  /*...*/
}

String userName = 'John Doe';
```

### 2.3. 常數 (Constants)

通常使用 `camelCase`。如果常數是全域的或在多個檔案中共享，可以考慮使用 `k` 前綴 (例如 `kDefaultPadding`)，但這並非強制。
由於規範還沒完全定論，在全域的條件下使用 `SCREAMING_SNAKE_CASE` (全大寫蛇形命名法) 也可以被接受。

```dart
const int maxAttempts = 3;
const double kDefaultPadding = 16.0; // 可選
const String API_BASE_URL = 'https://api.example.com'; // 可選
```

### 2.4. 檔案名 (File Names)

使用 `snake_case` (蛇形命名法)。

```
my_widget.dart
data_provider.dart
```

### 2.5. 庫前綴 (Library Prefixes)

當導入的庫有命名衝突時，使用小寫的 `snake_case` 作為前綴。

```dart
import 'package:path/path.dart' as p;
```

## 2.6. 建構式 (Constructors)

### 2.6.1. 命名建構式 (Named Constructors)

使用 `camelCase` 命名建構式，並在類別名稱後加上點號。

```dart
class User {
  User(this.name, this.email);

  User.guest()
      : name = 'Guest',
        email = '',
        super();
}
```

### 2.6.2. factory 建構式 (Factory Constructors)

使用 `camelCase` 命名，並在類別名稱後加上點號。

```dart
class User {
  User(this.name, this.email);

  factory User.fromJson(Map<String, dynamic> json) {
    return User(json['name'], json['email']);
  }
}
```

### 2.6.3. 成員預設值

使用 `=` 來設定成員的預設值，並在建構式中使用 `this` 關鍵字，預設值可依情境選擇在建構式參數中設定，或在類別成員中直接設定。

```dart
class User {
  String? name;
  String? email;

  User({this.name = 'Guest', this.email = ''});
}
// 或
class User {
  String? name = 'Guest';
  String? email = '';

  User({this.name, this.email});
}
```

### 2.7 Singleton 建構式 (Singleton Constructors)

使用私有建構式和靜態實例變數來實現 Singleton 模式。
參考 GetIt 的命名慣例，提供一個靜態 getter `I` 來獲取實例。

```dart
class MySingleton {
  MySingleton._privateConstructor();

  static final MySingleton _instance = MySingleton._privateConstructor();

  factory MySingleton() {
    return _instance;
  }
  
  static MySingleton get I => _instance;
}
```

## 3. 導入 (Imports)

### 3.1. 組織導入 (Organizing Imports)

按照以下順序組織導入：

1. `dart:` 核心庫
2. `package:` 第三方套件
3. `relative` 相對路徑導入

每個區塊之間用空行分隔。

```dart
import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'widgets/my_button.dart';
import 'utils/app_constants.dart';
```

### 3.2. 避免不必要的導入 (Avoid Unnecessary Imports)

只導入你實際需要的庫。

## 4. 註解 (Comments)

### 4.1. 文件註解 (Documentation Comments)

使用 `///` 進行文件註解，**重點針對以下情況**：

#### 4.1.1. 必須添加註解的情況

- **對外公開的 API**：供其他模組或套件使用的類別、函式、方法
- **複雜邏輯**：業務邏輯複雜或演算法不直觀的程式碼
- **配置類別**：如 API 介面等
- **抽象類別和介面**：定義契約的類別

#### 4.1.2. 不需添加註解的情況

- **內部實作類別**：僅在專案內部使用的工具類別
- **測試相關類別**：Mock 類別、測試工具類別等
- **簡單的資料類別**：domain layer 的 Entity、data layer 的Dto、presentation layer 的 Model 等
- **BLoC Event, State 類別**：BLoC 註解寫在 *Bloc class 即可，事件和狀態類別通常不需要詳細註解，除非有特殊邏輯

#### 4.1.3. 註解範例

```dart
/// 管理購物車商品總數的 BLoC。
/// 
/// 提供購物車商品數量的功能，並處理相關的載入和錯誤狀態。
class CartCountBloc extends Bloc<CartCountEvent, CartCountState> {
  // ... existing code ...
}

/// 購物車相關 API 介面。
/// 
/// 包含所有與購物車操作相關的 HTTP API 呼叫。
@RestApi()
abstract class CartApi {
  // ... existing code ...
}
```

### 4.2. 行內註解 (Inline Comments)

使用 `//` 進行行內註解，解釋複雜的邏輯或非顯而易見的程式碼。

```dart
// Calculate the total price including tax.
double totalPrice = itemPrice * (1 + taxRate);
```

### 4.3. TODO 註解 (TODO Comments)

使用 `// TODO:` 標記待辦事項或需要改進的地方。

```dart
// TODO: Add error handling for network requests.
```

## 5. 程式碼結構 (Code Structure)

### 5.1. 類別成員順序 (Class Member Order)

建議按照以下順序組織類別成員：

1. 常數 (Constants)
2. 靜態變數 (Static Variables)
3. 實例變數 (Instance Variables)
4. 建構函式 (Constructors)
5. 公共方法 (Public Methods)
6. 私有方法 (Private Methods)
7. `build` 方法 (對於 Widget)

### 5.2. 使用 `final` 和 `const` (Use `final` and `const`)

盡可能使用 `final` 來聲明變數，以提高程式碼的不可變性和效能。

`const` 用於編譯時常數，而在建構函式時，不強迫使用 `const`。(原因： Flutter lints 5.0.0 已不再強制要求使用 `const` 建構函式)

> https://github.com/dart-lang/sdk/issues/32602#issuecomment-379499141

```dart
final String name = 'Alice';
const int maxCount = 100;
```

### 5.3. 避免深層巢狀 (Avoid Deep Nesting)

盡量減少程式碼的巢狀深度，這有助於提高可讀性。可以透過提取方法、使用衛語句 (guard clauses) 等方式來實現。

```dart
// Bad: Deeply nested code
void func() {
  if (user != null) {
    if (user.isActive) {
      doSomething();
    }
  }
}

// Good: Flattened structure
void func() {
  if (user == null || !user.isActive) return;
  doSomething();
}
```

## 6. 錯誤處理 (Error Handling)

### 6.1. 使用 `try-catch` (Use `try-catch`)

對於可能拋出異常的程式碼，使用 `try-catch` 塊進行適當的錯誤處理。

```dart
void method() {
  try {
    // Some operation that might throw an exception
  } on FormatException catch (e) {
    print('Format error: $e');
  } catch (e) {
    print('An unknown error occurred: $e');
  }
}
```

## 7. Flutter 特定建議 (Flutter Specific Recommendations)

### 7.1. Widget 拆分 (Widget Splitting)

將複雜的 Widget 拆分成更小、可重用的 Widget，每個 Widget 負責單一職責。這有助於提高程式碼的可讀性、可測試性和效能。

### 7.2. 避免在 `build` 方法中執行昂貴操作 (Avoid Expensive Operations in `build` Method)

`build` 方法可能會被頻繁呼叫，因此應避免在其中執行昂貴的計算或網路請求。將這些操作移到 `initState`、`didChangeDependencies` 或使用狀態管理解決方案。

### 7.3. 狀態管理 (State Management)

選擇 BLoC 作為主要的狀態管理解決方案，並遵循 BLoC 的最佳實踐來組織和管理應用程式的狀態。

#### 7.3.1. BLoC 組織 (BLoC Organization)

- 每個 BLoC 應該專注於單一職責 (Single Responsibility Principle)。
- 使用事件 (Events) 來觸發狀態變更，並使用狀態 (State) 來表示不同的 UI 狀態。
- 將 BLoC 與 UI 分離，確保 UI 只關心如何呈現狀態。

#### 7.3.2. BLoC 命名 (BLoC Naming)

- 使用描述性的名稱來命名 BLoC，例如 `GetCartCountBloc`、`GetUserDataBloc`。

#### 7.3.3. BLoC 測試 (BLoC Testing)

- 為每個 BLoC 編寫單元測試，確保事件和狀態轉換的正確性。
- 使用 `bloc_test` 套件來簡化 BLoC 的測試過程。

#### 7.3.4. BLoC 事件 (BLoC Events)

- 使用 `abstract class` 定義事件基類，並為每個具體事件創建子類。
- 確保事件名稱清晰且描述性強。
- 使用 `equatable` 套件來簡化事件的比較。
- 事件保持與 Bloc 相同前綴，例如 `CartBloc` 的事件命名為 `CartInitial`、 `CartLoad`。
- 事件類別中覆寫 `props` 屬性以包含所有相關的屬性，確保事件的比較是基於其內容而非引用。

```dart
abstract class CartEvent extends Equatable {
  const CartEvent();
}

class CartLoad extends CartEvent {
  @override
  List<Object?> get props => [];
}
```

### 7.4. 資源管理 (Resource Management)

確保正確釋放不再需要的資源，例如 `AnimationController`、`StreamSubscription` 等。

## 8. 測試 (Testing)

### 8.1. 測試 (Testing)

至少為你的程式碼編寫單元測試，Widget 測試 and 整合測試為可選項目，以確保程式碼的正確性和穩定性。

### 8.2. 測試資料 (Test Data)

將測資與測試邏輯分離，放在同檔案中的 `_Data` 類別中。部分通用測試資料可以放在專案的 `test/mock/mock_common_message.dart` 下。

```dart
class _Data {
  static const String sampleData = r'''
  {
    "name": "John Doe",
    "email": "johndoe@example.com"
  }
  ''';
}
```

### 8.3. 測試命名 (Test Naming)

測試函式應該清楚地描述其目的，使用 `test` 或 `group` 來組織測試。

```dart
void main() {
  group('Example Tests', () {
    test('John Doe email', () {
      final email = jsonDecode(_Data.sampleData)['email'];
      expect(email, 'johndoe@example.com');
    });
  });
}
```

## Y. 其他 (Miscellaneous)

### Y.1. 避免魔術數字/字串 (Avoid Magic Numbers/Strings)

將重複使用的數字或字串定義為具名常數。測試除外。

```dart
const double kDefaultPadding = 8.0;
```

### Y.2. 保持函式簡潔 (Keep Functions Concise)

每個函式或方法應該只做一件事，並且盡可能簡潔。

### Y.3. Logger 規則

使用 `logger` 套件來進行日誌記錄，Debug 模式下使用 `Logger().d`，確保 Release 模式下不會有額外輸出。
