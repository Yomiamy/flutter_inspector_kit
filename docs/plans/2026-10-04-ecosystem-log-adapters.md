# P16 實作計畫 · 生態日誌適配器（logger / talker / logging）

> **規格來源**：[`docs/features/2026-10-04-ecosystem-log-adapters.md`](../features/2026-10-04-ecosystem-log-adapters.md)（含已確認的 D3：logger 接線採 `Logger.addOutputListener`）
> **階段**：STAGE 0b 實作計畫（How）· 2026-10-04
> **異動規模**：新增 5 個 example 檔，修改 `README.md`、`example/lib/main.dart`、`example/pubspec.yaml`；`lib/`、`test/`、根 `pubspec.yaml` **零改動**
> **版本號**：四處（`pubspec.yaml` / `README.md` / `CHANGELOG.md` / `lib/src/version.dart`）**全部不動**；CHANGELOG 條目（規格 O1）未決，列為本次範圍外

---

## 0. 核心判斷

✅ **值得做**。宿主既有的日誌流不在時間軸上，鏈推斷從第一步就缺了一段。補上它不需要動套件，只需要宿主端一個同步轉送點。

**本質（一句話）**：把「外部日誌庫的一個事件」攤成「一次 `inspector.log(message, level:, stackTrace:)` 呼叫」。

**資料結構**：沒有新的資料結構。來源事件（`LogEvent` / `TalkerData` / `LogRecord`）被**讀一次、轉成一次呼叫**，之後就丟掉。不複製、不暫存、不另建 buffer，`LogEntry` 仍是唯一真相，經過的還是既有 `RingBuffer.onMutate → revision` 通道。

**Ponytail 階梯**：
- 第 1 階（是否需要存在）：套件端完全不需要，宿主端的轉送程式碼才是交付物（規格 §4.2）。
- 第 2 階（codebase 已有）：`FlutterInspector.log()` 與 `logEntries` / `mergedTimeline()` 直接拿來用。example 的 `demos/` 類別慣例（`NetworkDemo(inspector)`）與 `kv/`（宿主端整合碼獨立一個目錄）的慣例照抄。
- 第 5 階（已裝相依）：只在 `example/pubspec.yaml` 加三個套件，根套件一個都不加。
- 最終落在第 7 階：**每個套件一個檔，內容是一個公開轉送函式加一個私有等級對應**。talker 另外多一個 4 行的薄 observer，因為它的接線點只吃 observer。砍掉的抽象見 §4。

---

## 1. 實作方向與 Trade-off

### 1.1 檔案形狀（核心決定）

| 方向 | 做法 | 優點 | 缺點 | 判定 |
|:---|:---|:---|:---|:---|
| **A. 每套件一檔：轉送函式 + 一行接線寫在 `main()`** | `bridges/<pkg>_bridge.dart` 只放「公開轉送函式 + 私有等級對應」（talker 加一個薄 observer）；接線那一行寫在 `main()` | README 食譜 = **整檔逐字** + 一行接線，可以用 `diff` 機械比對。測試用真實套件管線驅動轉送函式，logger 的靜態 listener 可以在 `tearDown` 移除。沒有任何新抽象。形狀與規格 §5.4「一個轉送函式 + 一行接線」完全一致 | example 的 `main.dart` 同時用到 logger 與 logging，必須把其中一個加 prefix。這正好也是 README 要示範的撞名解法（規格 §5.5） | ✅ **採用** |
| B. bridge 檔再包一層接線函式 | 加 `bridgeLogger(inspector)` 等函式，`main()` 只呼叫三個函式 | `main.dart` 不必處理撞名 | 多一層。logger 的 closure 被藏起來，測試沒辦法 `removeOutputListener`，listener 會跨測試累積。README 也看不出「接在哪個 hook」，而且偏離規格 §5.4 的形狀 | ❌ 否決 |
| C. 三套件合併成單一 `log_bridges.dart` | 一個檔放三段 | 少兩個檔 | logger × logging 在同一檔會撞名，必須加 prefix，食譜就不再是宿主能原樣複製的形狀。README 每段只能挑片段，逐字比對沒辦法機械化 | ❌ 否決 |

### 1.2 次要決定

前兩列同時也是對規格的形式偏離（見 §7）。

| 決定 | 選擇 | 理由 |
|:---|:---|:---|
| README 逐字一致的範圍 | README 每段的第一個 ` ```dart ` 區塊 = bridge 檔**全文（含 import）** | 規格寫「import 行除外」，這裡更嚴，因為可以直接 `diff`，不需要人工比對（驗收 5）。宿主複製時的 import 本來就與 example 相同 |
| logging 接線行的參數名用 `r` | 不用 `record` | `main.dart` 多了 `logging.` 前綴，用 `record` 會超過 80 字元而被 `dart format` 折行，README 那一行就不再是 `main.dart` 那一行的子字串。`r` 版本是 77 字元 |
| talker 的 `LogLevel` 撞名 | 對 kit 加 prefix（`as kit`），talker 不加 | 該檔用到的 talker 符號（`TalkerObserver` / `TalkerData` / `TalkerError` / `TalkerException` / `LogLevel`）比 kit 符號（`FlutterInspector` / `LogLevel`）多，對 kit 加 prefix 需要寫的前綴最少 |
| `main.dart` 的 logger × logging 撞名 | `logger` 用 `show Logger`，`logging` 用 `as logging`，`talker` 用 `show Talker`（避開 kit 的 `LogLevel`） | README 的 logging 接線行 `Logger.root.onRecord.listen((r) => forwardLogRecord(inspector, r));` 是 main.dart 那一行（`logging.` 開頭）的**子字串**，可以機械驗證 |
| bridge 檔放置位置 | 新目錄 `example/lib/bridges/` | 照 `example/lib/kv/shared_prefs_browser_source.dart`（宿主端整合碼）與 `demos/shared_prefs_demo.dart`（觸發 UI）分開放的既有慣例 |
| 觸發按鈕邏輯 | `example/lib/demos/log_bridges_demo.dart`（`LogBridgesDemo` 類別） | 照 `NetworkDemo` 等 demo 類別的慣例。`main.dart` 只加一個按鈕與一行 `initState` |
| 測試寫法 | `test()`，不用 `testWidgets()` | 不需要 binding。根 `test/core/flutter_inspector_test.dart` 也是在純 `test()` 內建構 `FlutterInspector`（實查） |

---

## 2. 檔案異動清單

| # | 檔案 | 動作 | 職責 | 預估行數 |
|:-:|:---|:---|:---|:-:|
| 1 | `example/pubspec.yaml` | 修改 | 新增 `logger: ^2.8.0`、`logging: ^1.3.0`、`talker: ^5.1.20` | +3 |
| 2 | `example/test/log_bridges_test.dart` | 新增 | 驗收 6–14 共 13 個 test（單檔執行，不納入根 606 基準） | ~190 |
| 3 | `example/lib/bridges/logger_bridge.dart` | 新增 | `forwardLoggerEvent(FlutterInspector, OutputEvent)` + 閾值等級對應 | ~30 |
| 4 | `example/lib/bridges/talker_bridge.dart` | 新增 | `forwardTalkerData(kit.FlutterInspector, TalkerData)` + 窮盡 switch 等級對應 + `InspectorTalkerObserver` | ~45 |
| 5 | `example/lib/bridges/logging_bridge.dart` | 新增 | `forwardLogRecord(FlutterInspector, LogRecord)` + 閾值等級對應 | ~30 |
| 6 | `example/lib/demos/log_bridges_demo.dart` | 新增 | `LogBridgesDemo.emitAll()`：三套件每個等級各送一筆，外加各一筆帶 stack trace 的錯誤（驗收 15） | ~50 |
| 7 | `example/lib/main.dart` | 修改 | 加 import，在 `main()` 加三條接線與 `logging` root 等級，`late final Talker talker`，加一顆按鈕 | +~25 |
| 8 | `README.md` | 修改 | 在 `### Log messages` 與 `### Read the merged timeline` 之間新增 `### Bridge existing loggers` | +~115 |

**不動**：`lib/**`、`test/**`、根 `pubspec.yaml`、`CHANGELOG.md`、`lib/src/version.dart`、`example/test/widget_test.dart`（規格 R10，已失效的樣板，不在本次範圍）。
`example/pubspec.lock` 會因 `pub get` 而變動，但已被根 `.gitignore:16`（`*.lock`）忽略，不會出現在 diff。

**公共 API**：套件公共 API **零異動**。README 會把 `forwardLoggerEvent` / `forwardTalkerData` / `InspectorTalkerObserver` / `forwardLogRecord` 寫成宿主複製用的契約，它們的形狀以本計畫為準。

---

## 3. 任務拆分

```text
Task 1 (Red) ──▶ Task 2 (Green) ──┬──▶ Task 3 (main.dart 接線 + demo) ──┬──▶ Task 5 (總驗收)
                                  └──▶ Task 4 (README 食譜)       ──────┘
```

- Task 1 → 2 → 序列（TDD，且 Task 2 的 import 依賴 Task 1 的 `pub get`）。
- **Task 3 ∥ Task 4 可並行**：寫入路徑完全不重疊（`example/lib/main.dart` + `example/lib/demos/log_bridges_demo.dart` 對 `README.md`），兩者都只依賴 Task 2 定稿後的 bridge 檔。
- Task 5 不寫任何檔，必須等 3、4 都完成（接線行比對需要讀 `main.dart` 與 `README.md`）。

> 指令一律用絕對路徑（agent 每次呼叫都會重置 cwd）。驗證輸出要拿原文當判斷證據，所以 `flutter` / `dart` 指令**不加 `rtk`**。

---

### Task 1 · 加相依並寫測試（Red）

| 項目 | 內容 |
|:---|:---|
| 寫入路徑 | `example/pubspec.yaml`、`example/test/log_bridges_test.dart`（`example/pubspec.lock` 由工具產生，已被 gitignore） |
| 並行性 | ❌ 序列，所有後續任務的前置 |
| 預估行數 | +3（pubspec）、~190（test） |
| 公共 API | 否 |

**1a. 加相依**：在 `example/pubspec.yaml` 的 `shared_preferences: ^2.3.0` 下一行插入：

```yaml
  logger: ^2.8.0
  logging: ^1.3.0
  talker: ^5.1.20
```

```bash
cd /Users/yomiry/StudioWorkspace/flutter_inspector/example && flutter pub get
awk '/^  (logger|logging|talker|talker_logger):$/{n=$1} n && /version:/{print n, $2; n=""}' /Users/yomiry/StudioWorkspace/flutter_inspector/example/pubspec.lock
```

預期：`pub get` 成功；awk 輸出 `logger: "2.8.0"`、`logging: "1.3.0"`、`talker: "5.1.20"`、`talker_logger: "5.1.20"`。
若實際解析版本與上述不同（例如上游在執行前又發了 patch），Task 4 README 的 `verified with logger 2.8.0, talker 5.1.20 and logging 1.3.0` 一律改成**實際解析版本**。

**1b. 寫測試** `example/test/log_bridges_test.dart`（13 個 test，驗收對照標在 group 內註解）：

```dart
import 'dart:async';

import 'package:example/bridges/logger_bridge.dart';
import 'package:example/bridges/logging_bridge.dart';
import 'package:example/bridges/talker_bridge.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_inspector_kit/flutter_inspector_kit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart' as logger_pkg;
import 'package:logging/logging.dart' as logging_pkg;
import 'package:talker/talker.dart' as talker_pkg;

FlutterInspector _newInspector() =>
    FlutterInspector(navigatorKey: GlobalKey<NavigatorState>());

/// Levels of every log entry, oldest first (logEntries is newest first).
List<LogLevel> _levels(FlutterInspector inspector) =>
    inspector.logEntries.reversed.map((e) => e.level).toList();

/// Logs a marker right after a bridged record, then checks the record is
/// already on the timeline and stamped no later than the marker. An async
/// bridge (e.g. talker.stream) would not have delivered it yet.
void _expectNotAfterMarker(FlutterInspector inspector, String bridged) {
  inspector.log('marker');
  final logs = inspector.mergedTimeline().whereType<LogEntry>();
  final source = logs.singleWhere((e) => e.message == bridged);
  final marker = logs.singleWhere((e) => e.message == 'marker');
  expect(source.timestamp.isAfter(marker.timestamp), isFalse);
}

void main() {
  // AC 6, 7, 8, 9, 10, 13, 14
  group('logger bridge', () {
    late FlutterInspector inspector;
    late void Function(logger_pkg.OutputEvent) bridge;

    setUp(() {
      inspector = _newInspector();
      bridge = (event) => forwardLoggerEvent(inspector, event);
      logger_pkg.Logger.addOutputListener(bridge);
    });

    tearDown(() => logger_pkg.Logger.removeOutputListener(bridge));

    test('a multi-line PrettyPrinter event becomes one clean entry', () {
      final lines = logger_pkg.PrettyPrinter().log(
        logger_pkg.LogEvent(logger_pkg.Level.info, 'hello'),
      );
      expect(lines.length, greaterThan(1)); // premise: the printer boxes it

      logger_pkg.Logger().i('hello');

      // Equality also rules out ANSI escapes and box glyphs.
      expect(inspector.logEntries.map((e) => e.message), ['hello']);
    });

    test('maps every non-deprecated level by threshold', () {
      logger_pkg.Logger(level: logger_pkg.Level.trace)
        ..t('t')
        ..d('d')
        ..i('i')
        ..w('w')
        ..e('e')
        ..f('f');

      expect(_levels(inspector), [
        LogLevel.verbose,
        LogLevel.debug,
        LogLevel.info,
        LogLevel.warning,
        LogLevel.error,
        LogLevel.error,
      ]);
    });

    test('error joins the message, stack trace becomes a string', () {
      final error = StateError('boom');
      final stackTrace = StackTrace.current;

      logger_pkg.Logger()
        ..e('failed', error: error, stackTrace: stackTrace)
        ..i(() => 'lazy');

      final [lazy, failed] = inspector.logEntries;
      expect(failed.message, 'failed\n$error');
      expect(failed.stackTrace, stackTrace.toString());
      expect(lazy.message, 'lazy');
      expect(lazy.stackTrace, isNull);
    });

    test('records muted by the host level never reach the timeline', () {
      logger_pkg.Logger(level: logger_pkg.Level.warning)
        ..i('muted')
        ..w('kept');

      expect(inspector.logEntries.map((e) => e.message), ['kept']);
    });

    test('delivers synchronously', () {
      logger_pkg.Logger().i('bridged');
      _expectNotAfterMarker(inspector, 'bridged');
    });
  });

  // AC 8, 9, 10, 12, 13
  group('talker bridge', () {
    late FlutterInspector inspector;
    late talker_pkg.Talker talker;

    setUp(() {
      inspector = _newInspector();
      talker = talker_pkg.Talker(observer: InspectorTalkerObserver(inspector));
    });

    test('maps every level; a record without one falls back to debug', () {
      talker
        ..verbose('v')
        ..debug('d')
        ..info('i')
        ..warning('w')
        ..error('e')
        ..critical('c')
        ..logCustom(talker_pkg.TalkerLog('no level'));

      expect(_levels(inspector), [
        LogLevel.verbose,
        LogLevel.debug,
        LogLevel.info,
        LogLevel.warning,
        LogLevel.error,
        LogLevel.error,
        LogLevel.debug,
      ]);
    });

    test('handle() reaches onException and onError', () {
      final exception = Exception('offline');
      final error = StateError('bad state');
      final stackTrace = StackTrace.current;

      talker
        ..handle(exception, stackTrace)
        ..handle(error, null, 'while saving');

      final [fromError, fromException] = inspector.logEntries;
      expect(fromException.level, LogLevel.error);
      expect(fromException.message, '$exception');
      expect(fromException.stackTrace, stackTrace.toString());
      expect(fromError.level, LogLevel.error);
      expect(fromError.message, 'while saving\n$error');
    });

    test('message and exception are joined; no stack trace gives null', () {
      final exception = Exception('timeout');

      talker
        ..info('plain')
        ..error('request failed', exception);

      final [failed, plain] = inspector.logEntries;
      expect(plain.message, 'plain');
      expect(plain.stackTrace, isNull);
      expect(failed.message, 'request failed\n$exception');
    });

    test('delivers synchronously', () {
      talker.info('bridged');
      _expectNotAfterMarker(inspector, 'bridged');
    });
  });

  // AC 8, 9, 10, 11, 13
  group('logging bridge', () {
    late FlutterInspector inspector;
    late StreamSubscription<logging_pkg.LogRecord> subscription;

    setUp(() {
      inspector = _newInspector();
      logging_pkg.Logger.root.level = logging_pkg.Level.ALL;
      subscription = logging_pkg.Logger.root.onRecord.listen(
        (r) => forwardLogRecord(inspector, r),
      );
    });

    tearDown(() async {
      await subscription.cancel();
      logging_pkg.Logger.root.level = logging_pkg.defaultLevel;
    });

    test('maps every level by threshold', () {
      logging_pkg.Logger('Auth')
        ..finest('1')
        ..finer('2')
        ..fine('3')
        ..config('4')
        ..info('5')
        ..warning('6')
        ..severe('7')
        ..shout('8');

      expect(_levels(inspector), [
        LogLevel.verbose,
        LogLevel.verbose,
        LogLevel.debug,
        LogLevel.debug,
        LogLevel.info,
        LogLevel.warning,
        LogLevel.error,
        LogLevel.error,
      ]);
    });

    test('loggerName prefixes the message; the root logger adds none', () {
      logging_pkg.Logger('Auth').info('token expired');
      logging_pkg.Logger.root.info('root message');

      final [root, auth] = inspector.logEntries;
      expect(auth.message, '[Auth] token expired');
      expect(root.message, 'root message');
    });

    test('error joins the message, stack trace becomes a string', () {
      final error = StateError('denied');
      final stackTrace = StackTrace.current;

      logging_pkg.Logger('Auth')
        ..severe('login failed', error, stackTrace)
        ..info('plain');

      final [plain, failed] = inspector.logEntries;
      expect(failed.message, '[Auth] login failed\n$error');
      expect(failed.stackTrace, stackTrace.toString());
      expect(plain.stackTrace, isNull);
    });

    test('delivers synchronously', () {
      logging_pkg.Logger('Auth').info('bridged');
      _expectNotAfterMarker(inspector, '[Auth] bridged');
    });
  });
}
```

**測試設計要點（鑑別力）**：
- **驗收 6**：先斷言前提 `PrettyPrinter` 輸出多行（`lines.length > 1`），否則「只有 1 筆」這個斷言沒有鑑別力。
- **驗收 7**：用 `message == 'hello'` 的相等斷言，比逐字元 `isNot(contains('\x1B'))` 更強（相等就不可能夾帶 ANSI 或框線）。
- **驗收 12**：`talker.handle(Exception)` 只會走 `onException`，`handle(Error)` 只會走 `onError`（`talker.dart:399-400`）。observer 只要漏覆寫其中一個，`final [a, b] = ...` 就會因長度不符而拋例外。
- **驗收 13**：`_expectNotAfterMarker` 在 marker 之後**同步**讀時間軸。如果改用非同步的 `talker.stream`，那筆紀錄此時還沒送到，`singleWhere` 會拋例外。
- **驗收 14**：走真實的 `Logger(level: warning)` 管線，證明接線點在 filter 之後（logger 2.8.0 `logger.dart:183` 先跑 `_filter.shouldLog`，`:191` 才呼叫 `_outputCallbacks`）。同一個 test 再送一筆 `w('kept')` 當正向對照：如果 listener 根本沒接上，`isEmpty` 也會通過，所以必須斷言結果恰好是 `['kept']`。
- logging 會在 `tearDown` 把 root level 還原成 `defaultLevel`（INFO）並取消訂閱。logger 會在 `tearDown` 移除靜態 listener，所以三個 group 之間不會互相污染。

**1c. 確認 Red**：

```bash
cd /Users/yomiry/StudioWorkspace/flutter_inspector/example && flutter test test/log_bridges_test.dart
```

預期：**載入失敗**，錯誤指向 `package:example/bridges/logger_bridge.dart`（以及另外兩個）不存在，而不是斷言失敗。

---

### Task 2 · 三個轉送檔（Green）

| 項目 | 內容 |
|:---|:---|
| 寫入路徑 | `example/lib/bridges/logger_bridge.dart`、`example/lib/bridges/talker_bridge.dart`、`example/lib/bridges/logging_bridge.dart` |
| 並行性 | ❌ 序列（依賴 Task 1；三檔的寫入路徑雖然不重疊，但都要等同一個測試檔轉綠，拆開並行沒有實益） |
| 預估行數 | ~30 + ~45 + ~30 |
| 公共 API | 套件 API 否；這三個檔的頂層符號就是 README 寫給宿主的契約 |

**2a.** `example/lib/bridges/logger_bridge.dart`：

```dart
import 'package:flutter_inspector_kit/flutter_inspector_kit.dart';
import 'package:logger/logger.dart';

/// Forwards one `logger` event to [inspector] as exactly one log entry.
///
/// Reads the structured [OutputEvent.origin] rather than the printer's
/// `lines`, so no ANSI colours or box borders reach the Console and the
/// stack trace lands in its own tappable field.
void forwardLoggerEvent(FlutterInspector inspector, OutputEvent event) {
  final origin = event.origin;
  final raw = origin.message;
  final message = '${raw is Function ? raw() : raw}';
  inspector.log(
    [message, origin.error].nonNulls.join('\n'),
    level: _toInspectorLevel(origin.level),
    stackTrace: origin.stackTrace?.toString(),
  );
}

// Thresholds, not a switch: deprecated levels (verbose, wtf) fall into the
// right band without being named, which would trip deprecated_member_use.
LogLevel _toInspectorLevel(Level level) {
  if (level >= Level.error) return LogLevel.error;
  if (level >= Level.warning) return LogLevel.warning;
  if (level >= Level.info) return LogLevel.info;
  if (level >= Level.debug) return LogLevel.debug;
  return LogLevel.verbose;
}
```

**2b.** `example/lib/bridges/talker_bridge.dart`：

```dart
import 'package:flutter_inspector_kit/flutter_inspector_kit.dart' as kit;
import 'package:talker/talker.dart';

/// Forwards one talker record to [inspector] as exactly one log entry.
///
/// Shared by all three [TalkerObserver] callbacks: [TalkerError] and
/// [TalkerException] are [TalkerData] too, and carry their own level.
void forwardTalkerData(kit.FlutterInspector inspector, TalkerData data) {
  final message = [data.message, data.exception, data.error].nonNulls
      .where((p) => '$p'.isNotEmpty)
      .join('\n');
  inspector.log(
    message,
    level: _toInspectorLevel(data.logLevel),
    stackTrace: data.stackTrace?.toString(),
  );
}

// Exhaustive switch: a level talker adds later fails to compile here instead
// of being filed silently. A record without a level is debug, as in talker.
kit.LogLevel _toInspectorLevel(LogLevel? level) => switch (level) {
  LogLevel.error || LogLevel.critical => kit.LogLevel.error,
  LogLevel.warning => kit.LogLevel.warning,
  LogLevel.info => kit.LogLevel.info,
  LogLevel.debug || null => kit.LogLevel.debug,
  LogLevel.verbose => kit.LogLevel.verbose,
};

/// Routes every talker callback into [forwardTalkerData].
///
/// talker has a single observer slot: if you already use one, call
/// [forwardTalkerData] from it instead of replacing it.
class InspectorTalkerObserver extends TalkerObserver {
  const InspectorTalkerObserver(this._inspector);

  final kit.FlutterInspector _inspector;

  @override
  void onLog(TalkerData log) => forwardTalkerData(_inspector, log);

  @override
  void onError(TalkerError err) => forwardTalkerData(_inspector, err);

  @override
  void onException(TalkerException err) => forwardTalkerData(_inspector, err);
}
```

**2c.** `example/lib/bridges/logging_bridge.dart`：

```dart
import 'package:flutter_inspector_kit/flutter_inspector_kit.dart';
import 'package:logging/logging.dart';

/// Forwards one `logging` record to [inspector] as exactly one log entry,
/// prefixed with the logger name (`[Auth] token expired`) so the source
/// module is visible and searchable on the timeline row.
void forwardLogRecord(FlutterInspector inspector, LogRecord record) {
  final name = record.loggerName;
  final message = name.isEmpty ? record.message : '[$name] ${record.message}';
  inspector.log(
    [message, record.error].nonNulls.join('\n'),
    level: _toInspectorLevel(record.level),
    stackTrace: record.stackTrace?.toString(),
  );
}

// Thresholds: Level is an open class (hosts may define their own), so only a
// range check covers every possible value.
LogLevel _toInspectorLevel(Level level) {
  if (level >= Level.SEVERE) return LogLevel.error;
  if (level >= Level.WARNING) return LogLevel.warning;
  if (level >= Level.INFO) return LogLevel.info;
  if (level >= Level.FINE) return LogLevel.debug;
  return LogLevel.verbose;
}
```

**實作注意（對照規格與上游原始碼）**：
- 三檔都**不得**在 import 前寫 `///` 檔頭註解，否則會觸發 `dangling_library_doc_comments`（`lints/recommended`），破壞 `No issues found!`。
- `nonNulls` 是 `NullableIterableExtensions` 的成員，定義在 `dart:collection`，並由 `dart:core` re-export（Dart SDK `lib/core/core.dart:182`，Dart 3.0+）。example SDK 為 `^3.10.1`，不需要額外 import。
- 規格 R7：talker 不會用 try-catch 包 observer。三個轉送函式只做字串組合加一次 `inspector.log`，不得加入任何可能拋例外的邏輯。
- 規格 §6.1 寫 `removeOutputListener` 回傳 `bool`，實查 logger 2.8.0 原始碼（`logger.dart:235`）是 `void`。測試只把它當敘述呼叫，不受影響。

**2d. 驗證**：

```bash
cd /Users/yomiry/StudioWorkspace/flutter_inspector/example && dart format lib/bridges test/log_bridges_test.dart
cd /Users/yomiry/StudioWorkspace/flutter_inspector/example && flutter test test/log_bridges_test.dart
cd /Users/yomiry/StudioWorkspace/flutter_inspector/example && flutter analyze
```

預期：
- `dart format` 跑完沒有錯誤。它可能改動排版（例如 talker 的 `nonNulls.where(...).join` 折行），**一律以 format 後的內容為準**，Task 4 從這裡複製。
- `flutter test` 結尾為 `+13: All tests passed!`。
- `flutter analyze` 輸出 `No issues found!`。

---

### Task 3 · example 接線與觸發按鈕

| 項目 | 內容 |
|:---|:---|
| 寫入路徑 | `example/lib/main.dart`、`example/lib/demos/log_bridges_demo.dart` |
| 並行性 | ✅ 可與 Task 4 並行（寫入路徑不重疊）；依賴 Task 2 |
| 預估行數 | main.dart +~25、demo ~50 |
| 公共 API | 否 |

**3a. 新增** `example/lib/demos/log_bridges_demo.dart`：

```dart
import 'package:logger/logger.dart' show Logger;
import 'package:logging/logging.dart' as logging;
import 'package:talker/talker.dart' show Talker;

/// Sends one record per level through logger, talker and logging, plus one
/// error with a stack trace each, so the bridges wired in `main()` can be
/// checked in the Console tab: level colours, red error rows and
/// `⚡ Errors only`.
class LogBridgesDemo {
  LogBridgesDemo(this._talker);

  final Talker _talker;
  final Logger _logger = Logger();
  final logging.Logger _log = logging.Logger('Demo');

  void emitAll() {
    final error = StateError('Demo: bridged error');
    final stackTrace = StackTrace.current;

    _logger
      ..t('logger trace')
      ..d('logger debug')
      ..i('logger info')
      ..w('logger warning')
      ..e('logger error')
      ..f('logger fatal')
      ..e('logger caught', error: error, stackTrace: stackTrace);

    _talker
      ..verbose('talker verbose')
      ..debug('talker debug')
      ..info('talker info')
      ..warning('talker warning')
      ..error('talker error')
      ..critical('talker critical')
      ..handle(error, stackTrace, 'talker caught');

    _log
      ..finest('logging finest')
      ..finer('logging finer')
      ..fine('logging fine')
      ..config('logging config')
      ..info('logging info')
      ..warning('logging warning')
      ..severe('logging severe')
      ..shout('logging shout')
      ..severe('logging caught', error, stackTrace);
  }
}
```

**3b. 修改** `example/lib/main.dart`（三處 Edit）：

① 把**第 1–4 行**（兩行 package import、空行、`import 'demos/inappwebview_demo.dart';`）整段換成下面這段。原第 4 行已併入，所以不會產生 `duplicate_import`；原第 5–9 行的其餘 demos import 不動：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_inspector_kit/flutter_inspector_kit.dart';
import 'package:logger/logger.dart' show Logger;
import 'package:logging/logging.dart' as logging;
import 'package:talker/talker.dart' show Talker;

import 'bridges/logger_bridge.dart';
import 'bridges/logging_bridge.dart';
import 'bridges/talker_bridge.dart';
import 'demos/inappwebview_demo.dart';
import 'demos/log_bridges_demo.dart';
```

② 在 `final GlobalKey<NavigatorState> navigatorKey = ...;` 下一行加：

```dart
late final Talker talker;
```

在 `main()` 的 `captureLifecycleEvents: true,\n  );` 與 `runApp(const MyApp());` 之間插入：

```dart
  // Bridge existing loggers into the Console timeline (README: "Bridge
  // existing loggers"). Every hook is synchronous, so a bridged record keeps
  // its place among network / navigation / database events. Wire them once.
  Logger.addOutputListener((event) => forwardLoggerEvent(inspector, event));
  talker = Talker(observer: InspectorTalkerObserver(inspector));
  // logging's root defaults to INFO, which drops CONFIG and below; lowered so
  // every demo level reaches the timeline. Whatever the host mutes stays muted.
  logging.Logger.root.level = logging.Level.ALL;
  logging.Logger.root.onRecord.listen((r) => forwardLogRecord(inspector, r));
```

③ `_MyHomePageState`：
- 在 `late final InAppWebViewDemo _inAppWebViewDemo;` 下加 `late final LogBridgesDemo _logBridgesDemo;`。
- 在 `_inAppWebViewDemo = InAppWebViewDemo(inspector);` 下加 `_logBridgesDemo = LogBridgesDemo(talker);`。
- 在 `child: const Text('Trigger Widget Build Error'),\n              ),` 之後（`Column.children` 結尾 `],` 之前）加：

```dart
              const SizedBox(height: 20),
              ElevatedButton(
                // One record per level through logger, talker and logging,
                // plus one stack-traced error each, all via the bridges wired
                // in main(). Check colours, red rows and ⚡ Errors only.
                onPressed: _logBridgesDemo.emitAll,
                child: const Text('Emit Bridged Logs'),
              ),
```

**3c. 驗證**：

```bash
cd /Users/yomiry/StudioWorkspace/flutter_inspector/example && dart format lib/main.dart lib/demos/log_bridges_demo.dart
cd /Users/yomiry/StudioWorkspace/flutter_inspector/example && flutter analyze
```

預期：`dart format` 回報 `0 changed`（若有改動，以 format 結果為準，但三條接線行必須維持單行，不可被折行）；`flutter analyze` 輸出 `No issues found!`。

---

### Task 4 · README 接線食譜

| 項目 | 內容 |
|:---|:---|
| 寫入路徑 | `README.md` |
| 並行性 | ✅ 可與 Task 3 並行（寫入路徑不重疊）；依賴 Task 2 **format 後**的 bridge 檔 |
| 預估行數 | +~115 |
| 公共 API | 否（文件） |

**4a.** 在 `README.md` 的 `Available levels: \`verbose\`, \`debug\`, \`info\`, \`warning\`, \`error\`.` 這一行之後、`### Read the merged timeline` 之前插入下列內容。三個 `<<...>>` 佔位處要**整檔原樣貼上** Task 2 format 後的檔案內容，不得手打（因此 bridge 檔的任何修改都會自動同步到 README，再由 4b 的 `diff` 把關）：

````markdown
### Bridge existing loggers

Already logging through [`logger`](https://pub.dev/packages/logger), [`talker`](https://pub.dev/packages/talker) or [`logging`](https://pub.dev/packages/logging)? Leave every call site alone. Wire one synchronous hook in `main()`, right after building the inspector, and each record becomes exactly **one** entry on the Console timeline, interleaved with network, navigation and database events.

Nothing is added to this package: the forwarding code lives in your app, so `flutter_inspector_kit` never depends on these libraries. Each recipe below is a file to copy as is, plus one wiring line. The same files are compiled and tested in [`example/lib/bridges/`](example/lib/bridges/) (verified with logger 2.8.0, talker 5.1.20 and logging 1.3.0).

Each hook sits after that library's own gate, so records it drops never reach the timeline: `Logger.level` or your `LogFilter` for logger, the `TalkerFilter` and the `enabled` flag for talker, `Logger.root.level` for logging. talker's log *level* is the exception (see its notes below).

#### `package:logger`

```dart
<<example/lib/bridges/logger_bridge.dart 全文>>
```

```dart
Logger.addOutputListener((event) => forwardLoggerEvent(inspector, event));
```

- The listener runs after your filter and printer. The default `DevelopmentFilter` drops everything in release builds, so nothing is forwarded there either.
- One event, one entry: the text comes from the structured `LogEvent`, not the printer's output lines, so ANSI colours and box borders never reach the Console. Extras a custom printer adds (prefixes, class names) are not forwarded.
- The listener list is static and process-wide, so register it once. Registering it twice forwards every record twice.

#### `package:talker`

```dart
<<example/lib/bridges/talker_bridge.dart 全文>>
```

```dart
final talker = Talker(observer: InspectorTalkerObserver(inspector));
```

- talker exports its own `LogLevel`, which clashes with this package's. That's why the import above uses `as kit`.
- talker's log level (`TalkerLoggerSettings.level`) only governs console output and history. It is applied *after* observers run, so it does **not** keep records off the timeline. To exclude levels, filter by key before observers, e.g. `Talker(filter: TalkerFilter(disabledKeys: [TalkerKey.verbose, TalkerKey.debug]))`, or check `data.logLevel` in your own observer before calling `forwardTalkerData`.
- talker has a single observer slot (`Talker(observer:)` / `talker.configure(observer:)`). If you already use one (to report to Crashlytics, say), keep it and call `forwardTalkerData(inspector, data)` from its `onLog`, `onError` and `onException`.
- Don't bridge through `talker.stream`: it delivers on a later microtask, after other timeline events have already been stamped, so entries would land out of order.

#### `package:logging`

```dart
<<example/lib/bridges/logging_bridge.dart 全文>>
```

```dart
Logger.root.onRecord.listen((r) => forwardLogRecord(inspector, r));
```

- `Logger.root` defaults to `Level.INFO`, so `CONFIG`, `FINE`, `FINER` and `FINEST` records are never emitted until you lower it (`Logger.root.level = Level.ALL;`).
- With `hierarchicalLoggingEnabled` at its default (`false`), the root receives every named logger's records, including those from third-party packages that log through `logging`.

#### Notes for all three

| Inspector | `logger` | `talker` | `logging` |
|---|---|---|---|
| `error` | `error`, `fatal` | `error`, `critical` | `SEVERE`, `SHOUT` |
| `warning` | `warning` | `warning` | `WARNING` |
| `info` | `info` | `info` | `INFO` |
| `debug` | `debug` | `debug`, no level | `FINE`, `CONFIG` |
| `verbose` | `trace` | `verbose` | `FINER`, `FINEST` |

- `fatal`, `critical` and `SHOUT` fold into `error`, the top level here. They still get a red row and still match `⚡ Errors only`.
- `logger` and `logging` both export `Logger` and `Level`. In a file that imports both, prefix one (`import 'package:logging/logging.dart' as logging;`), as [`example/lib/main.dart`](example/lib/main.dart) does.
- Bridged records share the 500-entry log buffer with your other logs. Leaving `trace` or `FINEST` on can push older context out, so keep your app's level at what you actually need.
- With `captureUncaughtErrors: true`, an error that your own `FlutterError.onError` also passes to `talker.handle()` or `logger.e()` is recorded twice. Route it through one or the other.
````

talker 等級說明的實查依據（talker 5.1.20 / talker_logger 5.1.20）：
- `talker.dart:433` 先呼叫 `_observer.onLog(data)`，`:436–441` 才進 `_logger.log(...)`，`:446` 才進 `_historyFilter`。
- `_historyFilter` 就是 `_logger.filter`（`:61`）。
- `TalkerLogger` 的 filter 是 `LogLevelFilter(settings.level)`（`talker_logger/lib/src/logger.dart:18`），由 `log()` 在 `:54` 套用。
- observer 之前只有 `settings.enabled`（`:418`）與 `_isApprovedByFilter`（`:421`，即 `TalkerFilter`）兩道閘。
- `TalkerFilter({enabledKeys, disabledKeys, searchQuery})` 依 `TalkerData.key` 過濾（`filter.dart`）。`TalkerKey.verbose` / `.debug` 等常數由 `talker` 匯出（`talker_key.dart`）。

**4b. 驗證（逐字一致，驗收 5）**：

```bash
cd /Users/yomiry/StudioWorkspace/flutter_inspector && for pkg in logger talker logging; do
  awk -v h="#### \`package:$pkg\`" '
    $0 == h { found = 1; next }
    found && /^```dart$/ { inblock = 1; next }
    inblock && /^```$/ { exit }
    inblock { print }
  ' README.md | diff - "example/lib/bridges/${pkg}_bridge.dart" && echo "$pkg: identical"
done
```

預期：只輸出三行 `logger: identical`、`talker: identical`、`logging: identical`，沒有任何 diff 內容。

---

### Task 5 · 總驗收（不寫檔）

| 項目 | 內容 |
|:---|:---|
| 寫入路徑 | 無 |
| 並行性 | ❌ 必須等 Task 3、4 都完成 |
| 預估行數 | 0 |
| 公共 API | 否 |

逐項執行，每項都要貼出原文輸出作為證據：

| # | 對應驗收 | 指令 | 預期 |
|:-:|:---|:---|:---|
| 1 | 6–14 | `cd /Users/yomiry/StudioWorkspace/flutter_inspector/example && flutter test test/log_bridges_test.dart` | `+13: All tests passed!` |
| 2 | 4 | `cd /Users/yomiry/StudioWorkspace/flutter_inspector/example && flutter analyze` | `No issues found!` |
| 3 | — | `cd /Users/yomiry/StudioWorkspace/flutter_inspector/example && dart format --output=none --set-exit-if-changed lib/bridges lib/demos/log_bridges_demo.dart lib/main.dart test/log_bridges_test.dart` | `0 changed`，exit 0 |
| 4 | 5 | Task 4b 的 awk + diff 迴圈 | 三行 `identical` |
| 5 | 5 | 接線行比對（見下方指令） | 三行 `OK` |
| 6 | 3 | `cd /Users/yomiry/StudioWorkspace/flutter_inspector && flutter test` | `+606: All tests passed!`（數量不變） |
| 7 | 3 | `cd /Users/yomiry/StudioWorkspace/flutter_inspector && flutter analyze lib/ test/` | `7 issues found`，全部是 info，與既有基準一致 |
| 8 | 1、2 | `cd /Users/yomiry/StudioWorkspace/flutter_inspector && git status --porcelain -- lib/ test/ pubspec.yaml CHANGELOG.md` | 空輸出（用 `status` 而非 `diff`，連未追蹤的新檔也一併抓出） |
| 9 | 範圍 | `cd /Users/yomiry/StudioWorkspace/flutter_inspector && git status --porcelain` | 只出現：`M README.md`、`M example/lib/main.dart`、`M example/pubspec.yaml`、`?? example/lib/bridges/`、`?? example/lib/demos/log_bridges_demo.dart`、`?? example/test/log_bridges_test.dart`，以及兩份 docs（feature / plan） |
| 10 | 15 | 手動：`cd /Users/yomiry/StudioWorkspace/flutter_inspector/example && flutter run`，點 **Emit Bridged Logs**，再開 Console | 見下方清單 |

**刻意不跑** `cd example && flutter test`（整個目錄）：既有的 `widget_test.dart` 樣板已經會失敗（規格 R10），跑整個目錄會混入與本功能無關的紅燈。

接線行比對（#5）。用 awk 的 `index` 做固定字串比對，不用 `grep`（hook 會改寫成 `rtk grep`，`-q` 的 exit code 語意不可靠）：

```bash
cd /Users/yomiry/StudioWorkspace/flutter_inspector && for line in \
  'Logger.addOutputListener((event) => forwardLoggerEvent(inspector, event));' \
  'Talker(observer: InspectorTalkerObserver(inspector));' \
  'Logger.root.onRecord.listen((r) => forwardLogRecord(inspector, r));'; do
  if awk -v s="$line" 'index($0, s) { f = 1 } END { exit !f }' README.md &&
     awk -v s="$line" 'index($0, s) { f = 1 } END { exit !f }' example/lib/main.dart; then
    echo "OK: $line"
  else
    echo "MISSING: $line"
  fi
done
```

手動驗收 15 的目視清單：
- Console 只開 **Log** 來源 chip（排除 nav 等其他來源的列）後，每按一次按鈕，log 列**恰好多 23 筆**：logger 7 筆、talker 7 筆、logging 9 筆。多了代表重複接線，少了代表漏接或被宿主等級擋掉。
- 每筆都沒有 `┌` 框線、沒有 `\x1B[` 亂碼，也沒有 printer 多行碎片。只有三筆 `* caught` 是「訊息 + error」兩行（驗收 10），其餘皆單行。
- `logger fatal`、`talker critical`、`logging shout` 與三筆 `* caught` 都是紅底的 error。三筆 `* caught` 可以點開，stack trace 能在 concise / raw 間切換。
- `logging *` 那幾列以 `[Demo] ` 開頭。
- 開 `⚡ Errors only` 後，這批紀錄只剩 12 列：每個套件 1 筆 warning + 3 筆 error。

---

## 4. 刻意不做

| 項目 | 理由 |
|:---|:---|
| 共用 `LogBridge` 基底類別 / adapter registry / 可設定的等級對應表 | 三個檔的來源型別、等級模型（閾值或 enum）、接線點都不同，抽出共用只能抽出 `inspector.log(...)` 那一行 |
| logger 的 Map / Iterable 訊息交給 JSON tree 呈現 | 規格 §4.2 已排除，先用 `toString()` |
| `LogEntry.data` 承載中繼資料 | 規格 §4.2 已排除（會改變 tap affordance） |
| talker bridge 內建等級過濾 | 宿主的過濾屬於宿主的設定（`TalkerFilter` 或自家 observer），bridge 只負責轉送；README 已說明做法 |
| 修 `example/test/widget_test.dart` | 規格 R10，與本功能無關 |
| CHANGELOG 條目 / 版號 | 規格 O1 未決，本次不動四處版號 |
| 自訂 logging `Level('AUDIT', 850)` 的測試 | 閾值邏輯已經由 8 個標準等級完整覆蓋各區間邊界，再加只是重複驗證同一條 `if` |

---

## 5. 風險

| # | 風險 | 處置 |
|:-:|:---|:---|
| 1 | `dart format` 把接線行折行，README 那一行就不再是子字串 | 接線行已控制在 80 字元內（logger 76、logging 77）；Task 3c 與 Task 5 #5 會攔截 |
| 2 | README 複製時手誤 | Task 4b 用 `diff` 機械比對；README 佔位處明令整檔貼上 |
| 3 | 上游 API 漂移（logger 3.x / talker 6.x） | `pubspec` 用 caret 鎖住大版本；`example` 能編譯 + 13 個測試就是 README 的守門（規格 R8） |
| 4 | 新相依與 example 既有相依衝突 | Task 1a 的 `pub get` 會先暴露。talker 是純 Dart，遞移相依為 `talker_logger ^5.1.20`，後者再帶 `ansicolor ^2.0.2` 與 `web ^1.1.0`（實查兩者的 `pubspec.yaml`） |
| 5 | 範例 `main()` 把 logging root 調成 `ALL` 導致洗版 | 只影響 example，而且正是規格 R2 要在 README 提醒的行為；註解已說明 |
| 6 | 宿主以為調 talker 的 log level 就能讓 Inspector 靜音 | README talker 段明寫 level 不擋 observer，並給出 `TalkerFilter` 與自家 observer 兩種做法 |

回滾：全部改動都在 example 與 README，刪掉新檔並 revert 三個修改檔即可，套件本體零殘留。

---

## 6. 執行方式

依賴關係與並行點見 §3。

- **Subagent-driven（建議）**：單一 implementer 依序跑 T1 → T5。總量約 480 行，大多是可直接貼上的程式碼，序列執行的成本很低。
- **Parallel session**：T2 完成後，開兩個 session 分別跑 T3、T4，兩邊都完成後再跑 T5。

**不 commit**（使用者未授權），完成後交由使用者檢視。

---

## 7. 相對於規格的偏離與補充

| # | 項目 | 說明 |
|:-:|:---|:---|
| 1 | README 逐字範圍與 logging 接線參數名 | 見 §1.2 前兩列：README 區塊含 import 整檔一致；logging 接線行用 `r` |
| 2 | example `main()` 把 `logging` root 調成 `Level.ALL` | 驗收 15 要求每個等級各送一筆，但 INFO 預設會擋掉 CONFIG 以下（CONFIG / FINE / FINER / FINEST）。README 照規格 §4.1 說明這個預設值 |
| 3 | bridge 檔放在新目錄 `example/lib/bridges/` | 規格 §9 提到 `demos/` 是 demo 慣例。轉送檔屬於宿主端整合碼，照 `kv/` 的慣例另開目錄；觸發 UI 仍放在 `demos/` |
| 4 | 規格 §6.1 的事實勘誤 | `Logger.removeOutputListener` 在 logger 2.8.0 的回傳型別是 `void`，不是 `bool`（`logger.dart:235`）。不影響任何設計決定 |
| 5 | 驗收 7 的斷言形式 | 用 `message == 'hello'` 相等斷言取代逐字元 `isNot(contains(...))`，涵蓋範圍更大 |
| 6 | 驗收 14 加正向對照 | 同一個 test 再送 `w('kept')`，斷言結果恰好是 `['kept']`，避免 listener 沒接上時 `isEmpty` 也通過。測試總數仍是 13 |
| 7 | 規格 §6.2 / 故事 5 漏記 talker 的等級語意 | 故事 5 把 talker 的宿主過濾寫成「filter / `enabled`」，這點正確，但兩處都沒說明 talker 的等級設定（`TalkerLoggerSettings.level`）只作用在 console 與 history，而且在 observer **之後**才套用（`talker.dart:433` 對 `:436–446`）。所以「調低 talker level 就能讓 Inspector 靜音」不成立。程式碼不變，README talker 段補上說明與兩種替代做法（`TalkerFilter(disabledKeys: ...)`、自家 observer 依 `data.logLevel` 判斷），另外新增風險 #6 |
