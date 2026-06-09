# 實作計畫：flutter_inspector 多 Inspector 框架

- 日期：2026-06-09
- 規格：`docs/features/2026-06-09-inspector-framework.md`
- 狀態：可進入實作

---

## 0. 關鍵設計決策：Dio 相依

### 問題分析

規格（5.1）原本建議使用者直接 import `lib/src/integrations/dio_interceptor.dart`，這違反 pub.dev 慣例：
- `lib/src/` 視為私有；要求使用者從 `src/` import 會被 pub.dev 扣分
- Dart analyzer **要求**所有被 import 的 package 都必須宣告在 `pubspec.yaml`
- 若 `dio_interceptor.dart` 含 `import 'package:dio/dio.dart'` 但 dio 未列為相依，**編譯會失敗**——無論該檔是否真的被使用者 import

### 評估過的選項

| 選項 | 結論 | 原因 |
|------|------|------|
| (a) 公開 entry point `lib/flutter_inspector_dio.dart` 並 import dio | **失敗** | dio 未列入 pubspec 時 analyzer 報錯 |
| (b) dio 設為 dev_dependency | **失敗** | dev_dependencies 無法被使用者取用 |
| (c) 用泛型/dynamic 介面避開 import dio | **醜** | 強迫使用者自寫 adapter，DX 差 |
| (d) 手動 `logNetwork()` API + 範例程式碼 | **純淨** | 乾淨、零強制相依、完全符合 pub.dev 規範 |
| **(e) dio 設為 runtime 相依 + typed interceptor** | **採用** | DX 最佳、與 logarte 模式一致、開箱即用 |

### 最終決定：dio 作為 Runtime 相依（使用者選擇）

**使用者明確選擇選項 (e)**：接受 dio 為強制相依，提供與 logarte 一致的 typed `FlutterInspectorDioInterceptor`。

**取捨：**
- **優點：** DX 最佳（使用者零樣板程式碼）、與 logarte 模式一致、開箱即用的 interceptor
- **缺點：** 即使使用者用 http/chopper/graphql 也被強制安裝 dio；增加 package 體積

**實作方式：**
1. `pubspec.yaml` 新增 `dio: ^5.0.0` 作為 runtime 相依
2. `lib/src/integrations/dio_interceptor.dart` 內含 typed `FlutterInspectorDioInterceptor extends Interceptor`
3. 主 export `lib/flutter_inspector.dart` 重新 export 該 interceptor（因 dio 現為強制相依）
4. `FlutterInspector.logNetwork(NetworkEntry entry)` 保留，供手動記錄（其他 HTTP client）使用
5. `/doc/dio_integration.md` 說明內建 interceptor 用法

**使用者體驗：**
```dart
// 使用者的 app —— 零樣板、開箱即用
final dio = Dio();
dio.interceptors.add(FlutterInspectorDioInterceptor(flutterInspector));
```

---

## 1. 架構總覽

### 分層結構

```
lib/
+-- flutter_inspector.dart              # 公開 API（主 entry point，re-export dio_interceptor）
+-- src/
    +-- core/
    |   +-- flutter_inspector_impl.dart # 核心實作（一般 constructor，使用者自行保存全域實例）
    |   +-- ring_buffer.dart            # 泛型 FIFO ring buffer（500 筆）
    |   +-- inspector_registry.dart     # 4 個固定 inspector 的內部 registry（每個 FlutterInspector 實例持有一份）
    +-- models/
    |   +-- log_entry.dart              # Console log 資料模型
    |   +-- network_entry.dart          # Network 請求資料模型
    |   +-- navigator_entry.dart        # 導航事件資料模型
    |   +-- database_entry.dart         # 資料庫操作資料模型
    |   +-- log_level.dart              # Enum：verbose/debug/info/warning/error
    |   +-- database_operation.dart     # Enum：insert/update/delete/query
    +-- inspectors/
    |   +-- log_inspector.dart          # Console inspector 邏輯
    |   +-- network_inspector.dart      # Network inspector 邏輯
    |   +-- navigator_inspector.dart    # Navigator inspector 邏輯
    |   +-- database_inspector.dart     # Database inspector 邏輯
    +-- integrations/
    |   +-- dio_interceptor.dart        # FlutterInspectorDioInterceptor（typed）
    +-- ui/
    |   +-- dashboard/
    |   |   +-- dashboard_modal.dart    # 全螢幕 modal 容器
    |   |   +-- dashboard_tab_bar.dart  # Tab bar（4 固定 + 1 可選）
    |   +-- tabs/
    |   |   +-- console_tab.dart        # Log 列表 + level 篩選
    |   |   +-- network_tab.dart        # Network 列表 + 詳情展開
    |   |   +-- navigator_tab.dart      # 導航歷史列表
    |   |   +-- database_tab.dart       # 資料庫操作列表 + 篩選
    |   +-- widgets/
    |   |   +-- inspector_fab.dart      # 可拖曳 FAB overlay
    |   |   +-- magical_tap.dart        # 連點觸發 widget
    |   |   +-- entry_list_tile.dart    # 可重用列表項元件
    |   |   +-- detail_viewer.dart      # JSON/body 詳情展開
    +-- observers/
        +-- navigator_observer.dart     # FlutterInspectorNavigatorObserver
```

### 資料流

```
使用者 App 程式碼
     |
     v
FlutterInspector（使用者保存的全域實例）
     |
     +---> log() ---------> LogInspector --------> RingBuffer<LogEntry>
     |                                                   |
     +---> logNetwork() --> NetworkInspector --> RingBuffer<NetworkEntry>
     |         ^                                         |
     |         |                                         |
     |    FlutterInspectorDioInterceptor（顯式注入 inspector，自動呼叫 logNetwork）
     |                                                   |
     +---> database() ----> DatabaseInspector -> RingBuffer<DatabaseEntry>
     |                                                   |
     +---> （NavigatorObserver 自動餵入）------------+   |
     |         |                                     |   |
     |         v                                     v   v
     |    NavigatorInspector --> RingBuffer<NavigatorEntry>
     |                                                   |
     +---> openDashboard() --> DashboardModal <--- 讀取所有 buffer
     |
     +---> attach() --> InspectorFab（Overlay）
```

---

## 2. 資料結構

### 2.1 核心模型

#### LogEntry
```dart
class LogEntry {
  final DateTime timestamp;
  final LogLevel level;
  final String message;
  final String? stackTrace;
  final Map<String, dynamic>? data;
}
```

#### NetworkEntry
```dart
class NetworkEntry {
  final DateTime timestamp;
  final String method;           // GET、POST 等
  final String url;
  final int? statusCode;
  final Duration? duration;
  final Map<String, dynamic>? requestHeaders;
  final String? requestBody;     // 10KB 截斷
  final Map<String, dynamic>? responseHeaders;
  final String? responseBody;    // 10KB 截斷
  final String? error;
  final bool isComplete;         // pending 時為 false
}
```

#### NavigatorEntry
```dart
class NavigatorEntry {
  final DateTime timestamp;
  final NavigatorAction action; // push/pop/replace/remove
  final String? routeName;
  final Object? arguments;
}
```

#### DatabaseEntry
```dart
class DatabaseEntry {
  final DateTime timestamp;
  final DatabaseOperation operation; // insert/update/delete/query
  final String tableName;
  final Map<String, dynamic>? data;
  final int? affectedRows;
}
```

### 2.2 Ring Buffer

```dart
class RingBuffer<T> {
  final int capacity; // 500
  final List<T> _items;

  void add(T item);           // O(1) append，FIFO 淘汰
  List<T> get items;          // 唯讀檢視（最新在前）
  void clear();
  int get length;
}
```

### 2.3 Inspector Registry（內部）

```dart
// 不對使用者公開 —— 內部協調用
// 每個 FlutterInspector 實例持有一份獨立的 InspectorRegistry（非全域共享）
class InspectorRegistry {
  final LogInspector log;
  final NetworkInspector network;
  final NavigatorInspector navigator;
  final DatabaseInspector database;

  // 固定 4 個 inspector，於 FlutterInspector 實例化時建立一次
}
```

### 2.4 資料擁有權

| 資料 | 擁有者 | 修改者 | 使用者 |
|------|--------|--------|--------|
| RingBuffer<LogEntry> | LogInspector | FlutterInspector.log() | ConsoleTab |
| RingBuffer<NetworkEntry> | NetworkInspector | FlutterInspector.logNetwork() / DioInterceptor | NetworkTab |
| RingBuffer<NavigatorEntry> | NavigatorInspector | NavigatorObserver callbacks | NavigatorTab |
| RingBuffer<DatabaseEntry> | DatabaseInspector | FlutterInspector.database() | DatabaseTab |
| FAB 位置 | InspectorFab state | 使用者拖曳 | InspectorFab |
| Dashboard 開啟狀態 | DashboardModal | FAB tap / MagicalTap / openDashboard() | DashboardModal |

---

## 3. 公開 API 設計

### 3.1 FlutterInspector 類別

```dart
class FlutterInspector {
  /// Package 版本
  static const String version = '0.0.1';

  /// 一般建構子 —— 建立一個 FlutterInspector 實例
  /// 使用者應於 app 啟動時建立一次並保存為全域變數
  /// （內含 mutable 的 inspector registry/buffer，故為非 const 的 generative constructor）
  FlutterInspector({
    Widget? customTab,
    String customTabTitle = 'Custom',
    int magicalTapCount = 5,
    int bufferSize = 500,
  });

  /// 將 FAB overlay 掛載到 widget tree
  void attach({
    required BuildContext context,
    bool visible = true,
  });

  /// 卸載 FAB overlay（清理）
  void detach();

  /// 記錄一則訊息到 Console tab
  void log(
    String message, {
    LogLevel level = LogLevel.info,
    String? stackTrace,
    Map<String, dynamic>? data,
  });

  /// 記錄一筆網路請求/回應到 Network tab
  void logNetwork(NetworkEntry entry);

  /// 記錄一筆資料庫操作到 Database tab
  void database(
    DatabaseOperation operation,
    String tableName, {
    Map<String, dynamic>? data,
    int? affectedRows,
  });

  /// 以程式方式開啟 dashboard modal
  void openDashboard(BuildContext context);

  /// 取得 NavigatorObserver 實例（用於 MaterialApp.navigatorObservers）
  FlutterInspectorNavigatorObserver get navigatorObserver;
}
```

### 3.2 FlutterInspectorNavigatorObserver

```dart
class FlutterInspectorNavigatorObserver extends NavigatorObserver {
  FlutterInspectorNavigatorObserver(this._inspector);

  @override
  void didPush(Route route, Route? previousRoute);

  @override
  void didPop(Route route, Route? previousRoute);

  @override
  void didReplace({Route? newRoute, Route? oldRoute});

  @override
  void didRemove(Route route, Route? previousRoute);
}
```

### 3.3 FlutterInspectorDioInterceptor

```dart
class FlutterInspectorDioInterceptor extends Interceptor {
  /// 建構子接受 FlutterInspector 實例（顯式注入）
  /// 使用者必須傳入自己保存的 FlutterInspector 全域實例
  FlutterInspectorDioInterceptor(this._inspector);

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler);

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler);

  @override
  void onError(DioException err, ErrorInterceptorHandler handler);
}
```

### 3.4 FlutterInspectorMagicalTap

```dart
class FlutterInspectorMagicalTap extends StatefulWidget {
  const FlutterInspectorMagicalTap({
    required this.child,
    this.tapCount = 5,
    this.timeout = const Duration(milliseconds: 500),
    super.key,
  });

  final Widget child;
  final int tapCount;
  final Duration timeout;
}
```

### 3.5 Enums

```dart
enum LogLevel { verbose, debug, info, warning, error }

enum DatabaseOperation { insert, update, delete, query }

enum NavigatorAction { push, pop, replace, remove }
```

---

## 4. 檔案異動清單

### 4.1 新增檔案

| 路徑 | 用途 |
|------|------|
| `lib/src/core/flutter_inspector_impl.dart` | 核心實作，一般 constructor（使用者自行保存全域實例） |
| `lib/src/core/ring_buffer.dart` | 容量 500 的泛型 FIFO ring buffer |
| `lib/src/core/inspector_registry.dart` | 持有 4 個 inspector 實例的內部容器（每個 FlutterInspector 實例各一份） |
| `lib/src/models/log_entry.dart` | Console log 資料模型 |
| `lib/src/models/network_entry.dart` | Network 請求/回應資料模型 |
| `lib/src/models/navigator_entry.dart` | 導航事件資料模型 |
| `lib/src/models/database_entry.dart` | 資料庫操作資料模型 |
| `lib/src/models/log_level.dart` | Log level enum |
| `lib/src/models/database_operation.dart` | DB 操作 enum |
| `lib/src/models/navigator_action.dart` | 導航動作 enum |
| `lib/src/inspectors/log_inspector.dart` | 含 RingBuffer 的 Console inspector |
| `lib/src/inspectors/network_inspector.dart` | 含 RingBuffer + body 截斷的 Network inspector |
| `lib/src/inspectors/navigator_inspector.dart` | 含 RingBuffer 的 Navigator inspector |
| `lib/src/inspectors/database_inspector.dart` | 含 RingBuffer 的 Database inspector |
| `lib/src/integrations/dio_interceptor.dart` | FlutterInspectorDioInterceptor（typed，建構子顯式注入 inspector 實例） |
| `lib/src/ui/dashboard/dashboard_modal.dart` | 含 TabBarView 的全螢幕 modal |
| `lib/src/ui/dashboard/dashboard_tab_bar.dart` | Tab bar 元件（4 + 可選 1） |
| `lib/src/ui/tabs/console_tab.dart` | Log 列表 + level 篩選 chip |
| `lib/src/ui/tabs/network_tab.dart` | Network 列表 + 可展開詳情 |
| `lib/src/ui/tabs/navigator_tab.dart` | 導航歷史列表 |
| `lib/src/ui/tabs/database_tab.dart` | 資料庫操作列表 + 篩選 |
| `lib/src/ui/widgets/inspector_fab.dart` | 含 Overlay 的可拖曳 FAB |
| `lib/src/ui/widgets/magical_tap.dart` | 連點手勢偵測 widget |
| `lib/src/ui/widgets/entry_list_tile.dart` | 所有 tab 共用的列表項 |
| `lib/src/ui/widgets/detail_viewer.dart` | JSON/body 展開 widget |
| `lib/src/observers/navigator_observer.dart` | FlutterInspectorNavigatorObserver |
| `test/core/ring_buffer_test.dart` | Ring buffer 單元測試 |
| `test/core/flutter_inspector_impl_test.dart` | 核心邏輯單元測試 |
| `test/models/log_entry_test.dart` | 模型序列化測試 |
| `test/models/network_entry_test.dart` | 模型 + 截斷測試 |
| `test/inspectors/log_inspector_test.dart` | Inspector 邏輯測試 |
| `test/inspectors/network_inspector_test.dart` | Network inspector + 截斷測試 |
| `test/integrations/dio_interceptor_test.dart` | DioInterceptor 單元測試（mock/fake，顯式注入 inspector） |
| `test/ui/inspector_fab_test.dart` | FAB 拖曳/點擊 widget 測試 |
| `test/ui/magical_tap_test.dart` | 連點 widget 測試 |
| `test/ui/dashboard_modal_test.dart` | Dashboard widget 測試 |
| `test/ui/console_tab_test.dart` | Console tab widget 測試 |
| `test/observers/navigator_observer_test.dart` | Observer callback 測試 |
| `doc/dio_integration.md` | 內建 Dio interceptor 用法指南 |

### 4.2 修改檔案

| 路徑 | 變更 |
|------|------|
| `pubspec.yaml` | dependencies 新增 `dio: ^5.0.0`（OWNER：T10） |
| `lib/flutter_inspector.dart` | 新增所有公開 API 的 export + re-export dio_interceptor.dart（OWNER：T10） |
| `lib/src/flutter_inspector_base.dart` | **刪除** —— 由 flutter_inspector_impl.dart 取代 |
| `test/flutter_inspector_test.dart` | 更新以測試新 API |
| `example/lib/main.dart` | 完整整合示範，含真實 Dio + interceptor（顯式注入全域 inspector） |

---

## 5. 任務拆分

### 任務依賴圖

```
[T0：Pubspec Dio 相依] ───────────────────────────────────────────────────────┐
     |                                                                         |
     v                                                                         |
[T1：Models] ─────────────────────────────────────────────────────────────────┐|
     |                                                                        ||
     v                                                                        ||
[T2：RingBuffer] ─────────────────────────────────────────────────────────┐   ||
     |                                                                    |   ||
     v                                                                    v   vv
[T3：Inspectors] <─────────────────────────────────────────────────────────────┤
     |                                                                         |
     v                                                                         |
[T4：NavigatorObserver] ────────────────────────────────────────────────────────┤
     |                                                                         |
     v                                                                         |
[T5：FlutterInspector Core] <───────────────────────────────────────────────────┤
     |                                                                         |
     +──────────────────┬──────────────────┬───────────────────┐               |
     v                  v                  v                   v               |
[T6：FAB Widget]  [T7：MagicalTap]  [T8：Dashboard]  [T5.5：DioInterceptor]      |
     |                  |                  |                   |               |
     └──────────────────┴──────────────────┴───────────────────┘               |
                        |                                                      |
                        v                                                      |
               [T9：Tab UIs] ──────────────────────────────────────────────────┤
                        |                                                      |
                        v                                                      |
               [T10：Public Export] ───────────────────────────────────────────┘
                        |
                        v
               [T11：Example App]
                        |
                        v
               [T12：Dio Doc]
```

### 並行分組

| 分組 | 任務 | 並行條件 | 備註 |
|------|------|----------|------|
| G1 | T0（Pubspec Dio 相依） | 最先單獨執行 | 必須最先 —— 讓後續所有任務能 import dio |
| G2 | T1（Models） | G1 之後 |  |
| G3 | T2（RingBuffer） | G2 之後 |  |
| G4 | T3a、T3b、T3c、T3d（Inspectors） | G3 之後，4 個並行 |  |
| G5 | T4（NavigatorObserver） | G4 之後（特別是 T3c） | **序列** —— T5 依賴 T4 |
| G6 | T5（FlutterInspector Core） | G5 之後 | **序列** —— 需要 T4 的 observer |
| G7 | T6（FAB）、T7（MagicalTap）、T8（Dashboard）、T5.5（DioInterceptor） | G6 之後，4 個並行 | 寫入檔案 scope 不重疊 |
| G8 | T9a-d（Tab UIs） | G7 之後（特別是 T8），4 個並行 |  |
| G9 | T10（Export） | G7+G8 之後 | 共享檔案唯一 owner（pubspec.yaml、flutter_inspector.dart） |
| G10 | T11（Example）、T12（Dio Doc） | G9 之後，並行 |  |

---

### T0：Pubspec Dio 相依

**複雜度：** 機械性
**檔案（專屬）：**
- `pubspec.yaml`（僅新增 dio 相依；完整擁有權轉移給 T10）

**依賴：** 無
**阻擋：** T1、T3b、T5.5、T10（所有需 dio 才能編譯的任務）

**驗收條件：**
- 於 dependencies 區段新增 `dio: ^5.0.0`
- 執行 `flutter pub get` 驗證解析

**測試：**
- 無（pubspec 變更）

**理由：** 此任務必須最先執行，後續所有需 dio 的任務（interceptor、測試）才能編譯。T10 為 pubspec.yaml 的最終 owner，負責任何額外清理。

---

### T1：資料模型

**複雜度：** 機械性
**檔案（專屬）：**
- `lib/src/models/log_entry.dart`
- `lib/src/models/network_entry.dart`
- `lib/src/models/navigator_entry.dart`
- `lib/src/models/database_entry.dart`
- `lib/src/models/log_level.dart`
- `lib/src/models/database_operation.dart`
- `lib/src/models/navigator_action.dart`
- `test/models/log_entry_test.dart`
- `test/models/network_entry_test.dart`

**依賴：** T0
**阻擋：** T2、T3、T5.5

**驗收條件：** 模型類別含不可變欄位、copyWith、equality、toString。NetworkEntry 含 body 截斷輔助函式（static method）。

**測試：**
- Unit：模型實例化、equality、copyWith
- Unit：NetworkEntry.truncateBody() 於 10KB 截斷

---

### T2：Ring Buffer

**複雜度：** 機械性
**檔案（專屬）：**
- `lib/src/core/ring_buffer.dart`
- `test/core/ring_buffer_test.dart`

**依賴：** T1（測試中需用到泛型型別）
**阻擋：** T3

**驗收條件：** 泛型 RingBuffer<T>，O(1) add、容量 500 時 FIFO 淘汰、items getter 回傳最新在前。

**測試：**
- Unit：加入項目至容量上限
- Unit：超過容量時 FIFO 淘汰
- Unit：clear() 清空 buffer
- Unit：items 以反向時間順序回傳

**AC 覆蓋：** D3（500 筆 FIFO）

---

### T3a：Log Inspector

**複雜度：** 機械性
**檔案（專屬）：**
- `lib/src/inspectors/log_inspector.dart`
- `test/inspectors/log_inspector_test.dart`

**依賴：** T1、T2
**阻擋：** T5

**驗收條件：** LogInspector 包裝 RingBuffer<LogEntry>，提供 add(LogEntry) 與 entries getter。

**測試：**
- Unit：加入 log 項目
- Unit：依序取出項目
- Unit：buffer 淘汰

**AC 覆蓋：** AC-05、AC-06

---

### T3b：Network Inspector

**複雜度：** 整合（body 截斷邏輯）
**檔案（專屬）：**
- `lib/src/inspectors/network_inspector.dart`
- `test/inspectors/network_inspector_test.dart`

**依賴：** T0（dio 已在 pubspec）、T1、T2
**阻擋：** T5、T5.5

**驗收條件：** NetworkInspector 包裝 RingBuffer<NetworkEntry>，add 時自動截斷 body > 10KB。

**測試：**
- Unit：加入 network 項目
- Unit：body 於 10KB 邊界截斷
- Unit：截斷標記 "[truncated]" 已附加

**AC 覆蓋：** AC-07、AC-08、D5（10KB 截斷）

---

### T3c：Navigator Inspector

**複雜度：** 機械性
**檔案（專屬）：**
- `lib/src/inspectors/navigator_inspector.dart`
- `test/inspectors/navigator_inspector_test.dart`

**依賴：** T1、T2
**阻擋：** T4、T5

**驗收條件：** NavigatorInspector 包裝 RingBuffer<NavigatorEntry>。

**測試：**
- Unit：加入 navigator 項目
- Unit：依序取出項目

**AC 覆蓋：** AC-10

---

### T3d：Database Inspector

**複雜度：** 機械性
**檔案（專屬）：**
- `lib/src/inspectors/database_inspector.dart`
- `test/inspectors/database_inspector_test.dart`

**依賴：** T1、T2
**阻擋：** T5

**驗收條件：** DatabaseInspector 包裝 RingBuffer<DatabaseEntry>。

**測試：**
- Unit：加入 database 項目
- Unit：依操作類型篩選
- Unit：依 table 名稱篩選

**AC 覆蓋：** AC-11

---

### T4：Navigator Observer

**複雜度：** 整合
**檔案（專屬）：**
- `lib/src/observers/navigator_observer.dart`
- `test/observers/navigator_observer_test.dart`

**依賴：** T3c
**阻擋：** T5（為 Core 的 navigatorObserver getter 提供 observer 實例）

**驗收條件：** FlutterInspectorNavigatorObserver extends NavigatorObserver，於 didPush/didPop/didReplace/didRemove 餵入 NavigatorInspector。

**測試：**
- Unit：didPush 產生 action=push 的項目
- Unit：didPop 產生 action=pop 的項目
- Unit：route name 與 arguments 有被捕捉

**AC 覆蓋：** AC-10

---

### T5：FlutterInspector Core

**複雜度：** 設計判斷（一般 constructor、attach/detach 生命週期）
**檔案（專屬）：**
- `lib/src/core/flutter_inspector_impl.dart`
- `lib/src/core/inspector_registry.dart`
- `test/core/flutter_inspector_impl_test.dart`

**依賴：** T3a、T3b、T3c、T3d、T4（navigatorObserver getter 需要 T4 的 observer）
**阻擋：** T6、T7、T8、T5.5

**驗收條件：**
- 一般 constructor 含設定參數（非 factory、非內部 _instance 快取）
- 使用者應於 app 啟動時建立一次並保存為全域變數
- 每次 new 產生獨立實例（各自持有獨立的 4 個 inspector registry/buffer）
- log()、logNetwork()、database() 方法委派給各 inspector
- navigatorObserver getter 回傳快取的 observer（由 T4 的類別建立）
- attach()/detach() 管理 FAB overlay 生命週期
- openDashboard() 顯示 modal

**測試：**
- Unit：constructor 建立的實例持有獨立的 4 個 inspector registry
- Unit：多次 new 產生不同實例（實例不共享 buffer）
- Unit：log() 加入 LogInspector
- Unit：logNetwork() 加入 NetworkInspector
- Unit：database() 加入 DatabaseInspector
- Widget：attach() 顯示 FAB
- Widget：detach() 移除 FAB
- Widget：openDashboard() 顯示 modal

**AC 覆蓋：** AC-01、AC-02、AC-12、AC-13、AC-14

---

### T5.5：Dio Interceptor

**複雜度：** 整合（request/response 關聯、duration 計算）
**檔案（專屬）：**
- `lib/src/integrations/dio_interceptor.dart`
- `test/integrations/dio_interceptor_test.dart`

**依賴：** T0（dio 相依）、T1（NetworkEntry 模型）、T5（FlutterInspector.logNetwork）
**阻擋：** T10

**驗收條件：**
- `FlutterInspectorDioInterceptor extends Interceptor`
- 建構子接受 `FlutterInspector` 實例（顯式注入，使用者必須傳入自己保存的全域 inspector）
- **onRequest：** 記錄起始 timestamp（透過 RequestOptions.extra 或內部 map）、method、url、requestHeaders、requestBody（10KB 截斷）
- **onResponse：** 計算 duration、記錄 statusCode、responseHeaders、responseBody（10KB 截斷）、isComplete=true；呼叫 inspector.logNetwork()
- **onError：** 計算 duration、記錄 error 訊息、statusCode（若有）、isComplete=true；呼叫 inspector.logNetwork()
- request-response 關聯透過 RequestOptions.extra 或內部 Map<RequestOptions, DateTime>

**測試：**
- Unit：onRequest 記錄起始 timestamp
- Unit：onResponse 產生 duration 正確的 NetworkEntry
- Unit：onError 產生含 error 欄位的 NetworkEntry
- Unit：request/response body 套用截斷
- Unit：headers 正確捕捉
- Unit：顯式注入的 inspector 實例被正確使用

**AC 覆蓋：** AC-07、AC-08、AC-09

---

### T6：FAB Widget

**複雜度：** 整合（Overlay、拖曳手勢）
**檔案（專屬）：**
- `lib/src/ui/widgets/inspector_fab.dart`
- `test/ui/inspector_fab_test.dart`

**依賴：** T5
**阻擋：** T10

**驗收條件：**
- 使用 Overlay 的可拖曳 FAB
- 位置於 session 內保留（StatefulWidget state）
- 點擊透過 callback 開啟 dashboard
- visible 參數控制顯示

**測試：**
- Widget：visible=true 時 FAB 渲染
- Widget：visible=false 時 FAB 隱藏
- Widget：拖曳更新位置
- Widget：點擊觸發 callback

**AC 覆蓋：** AC-01、AC-02、AC-12、AC-14

---

### T7：Magical Tap Widget

**複雜度：** 整合（手勢計時）
**檔案（專屬）：**
- `lib/src/ui/widgets/magical_tap.dart`
- `test/ui/magical_tap_test.dart`

**依賴：** T5
**阻擋：** T10

**驗收條件：**
- 包裝子 widget
- 於 timeout 視窗內計算點擊次數（預設 500ms）
- 達 N 次點擊後觸發 callback（預設 5）
- timeout 後重置計數

**測試：**
- Widget：快速點 5 下觸發 callback
- Widget：點 4 下後 timeout 不觸發
- Widget：自訂 tapCount=3 可運作
- Widget：自訂 timeout 可運作

**AC 覆蓋：** AC-04、D4（預設 5 下）

---

### T8：Dashboard Modal

**複雜度：** 設計判斷（tab 協調）
**檔案（專屬）：**
- `lib/src/ui/dashboard/dashboard_modal.dart`
- `lib/src/ui/dashboard/dashboard_tab_bar.dart`
- `test/ui/dashboard_modal_test.dart`

**依賴：** T5
**阻擋：** T9、T10

**驗收條件：**
- 全螢幕 modal（showModalBottomSheet 搭配 isScrollControlled 或 showGeneralDialog）
- TabBar 含 4 固定 tab + 可選第 5 個
- 關閉按鈕關掉 modal
- 接收 inspector 實例以讀取 buffer

**測試：**
- Widget：modal 全螢幕開啟
- Widget：無 customTab 時顯示 4 個 tab
- Widget：有 customTab 時顯示 5 個 tab
- Widget：tab 切換可運作
- Widget：關閉關掉 modal

**AC 覆蓋：** AC-02、AC-03、D2（全螢幕 modal）

---

### T9a：Console Tab

**複雜度：** 整合（列表 + 篩選）
**檔案（專屬）：**
- `lib/src/ui/tabs/console_tab.dart`
- `test/ui/console_tab_test.dart`

**依賴：** T8
**阻擋：** T10

**驗收條件：**
- log 項目用 ListView.builder
- log level 的篩選 chip
- 項目顯示 timestamp、level icon、message
- 點擊展開 stackTrace/data

**測試：**
- Widget：渲染 log 項目
- Widget：依 level 篩選可運作
- Widget：點擊展開詳情

**AC 覆蓋：** AC-05、AC-06

---

### T9b：Network Tab

**複雜度：** 整合（列表 + 詳情展開）
**檔案（專屬）：**
- `lib/src/ui/tabs/network_tab.dart`
- `lib/src/ui/widgets/detail_viewer.dart`
- `test/ui/network_tab_test.dart`

**依賴：** T8
**阻擋：** T10

**驗收條件：**
- network 項目用 ListView.builder
- 項目顯示 method、url、statusCode、duration
- 點擊展開 headers/body
- 截斷的 body 顯示 "[truncated]"

**測試：**
- Widget：渲染 network 項目
- Widget：點擊展開詳情
- Widget：截斷 body 正確顯示

**AC 覆蓋：** AC-07、AC-08

---

### T9c：Navigator Tab

**複雜度：** 機械性
**檔案（專屬）：**
- `lib/src/ui/tabs/navigator_tab.dart`
- `test/ui/navigator_tab_test.dart`

**依賴：** T8
**阻擋：** T10

**驗收條件：**
- navigator 項目用 ListView.builder（最新在前）
- 項目顯示 action、routeName、timestamp
- 點擊展開 arguments

**測試：**
- Widget：渲染 navigator 項目
- Widget：點擊展開 arguments

**AC 覆蓋：** AC-10

---

### T9d：Database Tab

**複雜度：** 整合（列表 + 篩選）
**檔案（專屬）：**
- `lib/src/ui/tabs/database_tab.dart`
- `lib/src/ui/widgets/entry_list_tile.dart`
- `test/ui/database_tab_test.dart`

**依賴：** T8
**阻擋：** T10

**驗收條件：**
- database 項目用 ListView.builder
- 依操作類型篩選
- 依 table 名稱篩選
- 項目顯示 operation、table、timestamp
- 點擊展開 data JSON

**測試：**
- Widget：渲染 database 項目
- Widget：依 operation 篩選可運作
- Widget：依 table 篩選可運作
- Widget：點擊展開 data

**AC 覆蓋：** AC-11

---

### T10：公開 Export 與清理

**複雜度：** 機械性
**檔案（共享 —— 唯一 owner）：**
- `lib/flutter_inspector.dart`（OWNER：T10）
- `pubspec.yaml`（OWNER：T10 —— 驗證 T0 加的 dio 相依、任何最終清理）
- `lib/src/flutter_inspector_base.dart`（刪除）

**依賴：** T5.5、T6、T7、T8、T9a-d
**阻擋：** T11、T12

**驗收條件：**
- 主 export 檔 export 所有公開 API
- **re-export `dio_interceptor.dart`**（因 dio 為強制相依）
- 刪除舊 placeholder 檔
- 更新既有測試以使用新 API
- 驗證 pubspec.yaml 有 dio 相依

**測試：**
- 驗證 export 可編譯
- 更新 `test/flutter_inspector_test.dart`

**AC 覆蓋：** 全部（整合點）

---

### T11：Example App 整合

**複雜度：** 整合
**檔案（專屬）：**
- `example/lib/main.dart`

**依賴：** T10
**阻擋：** 無

**驗收條件：**
- 含所有功能的完整可運作示範
- **於 app 啟動時建立一個 FlutterInspector 實例並保存為全域變數**
- attach() 搭配 FAB
- app bar 上的 MagicalTap
- MaterialApp 中的 NavigatorObserver
- 觸發 log/database 操作的按鈕
- **Network tab 用真實 Dio + FlutterInspectorDioInterceptor（顯式注入全域 inspector）** 發送請求並顯示
- 範例：`dio.interceptors.add(FlutterInspectorDioInterceptor(inspector))`

**測試：**
- 手動：執行 example app，驗證所有功能可運作

**AC 覆蓋：** 全部（端對端驗證）

---

### T12：Dio 整合文件

**複雜度：** 機械性
**檔案（專屬）：**
- `doc/dio_integration.md`

**依賴：** T10
**阻擋：** 無

**驗收條件：**
- 說明內建 interceptor 用法的文件
- 範例展示 `dio.interceptors.add(FlutterInspectorDioInterceptor(inspector))`
- 說明使用者須自行保存全域 FlutterInspector 實例並傳入 interceptor
- 註明 logNetwork() API 仍保留供其他 HTTP client 使用

**測試：**
- 無（文件）

**AC 覆蓋：** AC-07、AC-09

---

## 6. 測試策略

### 6.1 各層測試類型

| 層 | 測試類型 | 工具 |
|----|----------|------|
| Models | Unit | flutter_test |
| RingBuffer | Unit | flutter_test |
| Inspectors | Unit | flutter_test |
| Observer | Unit | flutter_test + mock Route |
| DioInterceptor | Unit | flutter_test + mock/fake（顯式注入 inspector） |
| FlutterInspector Core | Unit + Widget | flutter_test |
| UI Widgets（FAB、MagicalTap） | Widget | flutter_test |
| Dashboard + Tabs | Widget | flutter_test |
| Example App | 手動 + 整合 | flutter run |

### 6.2 測試檔案組織

```
test/
+-- core/
|   +-- ring_buffer_test.dart
|   +-- flutter_inspector_impl_test.dart
+-- models/
|   +-- log_entry_test.dart
|   +-- network_entry_test.dart
+-- inspectors/
|   +-- log_inspector_test.dart
|   +-- network_inspector_test.dart
|   +-- navigator_inspector_test.dart
|   +-- database_inspector_test.dart
+-- integrations/
|   +-- dio_interceptor_test.dart
+-- observers/
|   +-- navigator_observer_test.dart
+-- ui/
|   +-- inspector_fab_test.dart
|   +-- magical_tap_test.dart
|   +-- dashboard_modal_test.dart
|   +-- console_tab_test.dart
|   +-- network_tab_test.dart
|   +-- navigator_tab_test.dart
|   +-- database_tab_test.dart
+-- flutter_inspector_test.dart  # 更新後的整合測試
```

### 6.3 覆蓋率目標

- 核心邏輯（models、buffer、inspectors）：> 90%
- DioInterceptor：> 90%
- UI widgets：> 80%（關鍵路徑）
- Observer：> 90%

### 6.4 Example App 驗證檢查表

- [ ] debug mode 出現 FAB
- [ ] FAB 拖曳可運作
- [ ] FAB 點擊開啟 dashboard
- [ ] Dashboard 顯示 4 tab（無 custom）或 5 tab（有 custom）
- [ ] Console tab 顯示 log 並可篩選
- [ ] Network tab 顯示項目並可展開（透過真實 Dio 請求）
- [ ] Navigator tab 顯示路由歷史
- [ ] Database tab 顯示操作並可篩選
- [ ] MagicalTap 連點 5 下後觸發
- [ ] openDashboard() 以程式方式可運作
- [ ] 關閉 dashboard 後 FAB 仍存在

---

## 7. 摘要

| 指標 | 值 |
|------|-----|
| 任務總數 | 17（T0 + T1 + T2 + T3a-d + T4 + T5 + T5.5 + T6 + T7 + T8 + T9a-d + T10 + T11 + T12） |
| 新增檔案 | 37 |
| 修改檔案 | 4 |
| 刪除檔案 | 1 |
| 並行分組 | 10 |
| 最大並行度 | 4 任務（G4：T3a-d；G7：T6+T7+T8+T5.5） |

### Dio 決策摘要

**最終選擇：** dio 作為強制 runtime 相依（`^5.0.0`），package 內建 typed `FlutterInspectorDioInterceptor`。使用者一行加入 interceptor：`dio.interceptors.add(FlutterInspectorDioInterceptor(inspector))`。`logNetwork()` API 保留給用其他 HTTP client（http、chopper、graphql）的使用者。

**取捨：** DX 最佳（與 logarte 模式一致），代價是強制所有使用者安裝 dio。

### FlutterInspector 建構方式摘要

**最終選擇：** 一般 generative constructor（非 factory、無內部 _instance 快取）。使用者於 app 啟動時建立一次並自行保存為全域變數，與 logarte 模式一致。每次 new 產生獨立實例，各自持有獨立的 4 個 inspector registry/buffer。

### 建議執行順序

1. **序列：** T0（Pubspec Dio 相依）—— **必須最先**
2. **序列：** T1（Models）
3. **序列：** T2（RingBuffer）
4. **並行（4）：** T3a、T3b、T3c、T3d（Inspectors）
5. **序列：** T4（Navigator Observer）—— **T5 依賴 T4，不可並行**
6. **序列：** T5（FlutterInspector Core）
7. **並行（4）：** T6（FAB）、T7（MagicalTap）、T8（Dashboard）、T5.5（DioInterceptor）
8. **並行（4）：** T9a、T9b、T9c、T9d（Tabs）
9. **序列：** T10（Export）—— pubspec.yaml 與 flutter_inspector.dart 的共享檔案 owner
10. **並行（2）：** T11（Example）、T12（Dio Doc）

### 共享檔案擁有權

| 共享檔案 | Owner 任務 | 備註 |
|----------|-----------|------|
| `lib/flutter_inspector.dart` | T10 | 主 export，re-export dio_interceptor |
| `pubspec.yaml` | T10 | T0 先加 dio 相依；T10 為清理/驗證的最終 owner |

### 相對原計畫的關鍵修正

1. **T4 → T5 改為序列**（非並行）：T5 的 `navigatorObserver` getter 依賴 T4 的 observer 類別
2. **新增 T0**：Pubspec dio 相依必須最先，讓所有依賴 dio 的程式碼能編譯
3. **新增 T5.5**：獨立的 DioInterceptor 任務，含正確的依賴鏈
4. **並行分組增加**：8 → 10（因 T4/T5 序列化與新任務）
5. **FlutterInspector 改為一般 constructor**：移除 factory singleton 模式，使用者自行保存全域實例
