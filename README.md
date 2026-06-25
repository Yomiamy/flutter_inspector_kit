# 🔍 Flutter Inspector

In-app, multi-inspector debugging overlay for Flutter apps — logs, network, navigation, and database, all behind one unified API.

## 📦 Features

- 🪵 **Console**: capture logs across five severity levels, with optional structured data and stack traces
- 📡 **Network**: intercept HTTP traffic via Dio, inspect structured request/response details, search/filter, share as cURL
- 🧭 **Navigator**: track route pushes, pops, and replacements automatically
- 🗄️ **Database**: record insert / update / delete / query operations with affected-row counts and payloads
- 👆 **Magical tap & floating button**: open the dashboard with a hidden multi-tap gesture or a draggable in-app FAB
- 🔔 **Live notification (opt-in)**: a system notification that summarises the latest API call and the running total

## 📱 Screenshots

|Home|Console|Network|
|---|---|---|
|<img width="200" src="https://github.com/Yomiamy/flutter_inspector_kit/blob/main/doc/screenshots/home.png?raw=true"/>|<img width="200" src="https://github.com/Yomiamy/flutter_inspector_kit/blob/main/doc/screenshots/console.png?raw=true"/>|<img width="200" src="https://github.com/Yomiamy/flutter_inspector_kit/blob/main/doc/screenshots/network.png?raw=true"/>|

|Network Detail|Navigator|Uncaught Error|
|---|---|---|
|<img width="200" src="https://github.com/Yomiamy/flutter_inspector_kit/blob/main/doc/screenshots/network_detail.png?raw=true"/>|<img width="200" src="https://github.com/Yomiamy/flutter_inspector_kit/blob/main/doc/screenshots/navigator.png?raw=true"/>|<img width="200" src="https://github.com/Yomiamy/flutter_inspector_kit/blob/main/doc/screenshots/uncaught_error.png?raw=true"/>|

|Database Browse|||
|---|---|---|
|<img width="200" src="https://github.com/Yomiamy/flutter_inspector_kit/blob/main/doc/screenshots/database_browse.png?raw=true"/>|||

## 🪚 Usage

### Add to pubspec.yaml

```yaml
dependencies:
  flutter_inspector_kit: ^1.0.0
```

Then run `flutter pub get`.

### Initialize

Create a single shared `FlutterInspector` instance and wire it into your app. Register the navigator observer to track routes, and wrap your app in `FlutterInspectorMagicalTap` so a hidden gesture can open the dashboard from anywhere.

```dart
import 'package:flutter/material.dart';
import 'package:flutter_inspector_kit/flutter_inspector_kit.dart';

final inspector = FlutterInspector();

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      // 1. Track navigation events
      navigatorObservers: [inspector.navigatorObserver],
      // 2. A hidden gesture opens the dashboard from anywhere
      builder: (context, child) {
        return FlutterInspectorMagicalTap(
          onTap: () => inspector.openDashboard(context),
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: const MyHomePage(),
    );
  }
}
```

That's it? Yes, that's it.

### Floating button

Prefer a visible trigger? Attach the inspector once the first frame is built to show a draggable floating button that opens the dashboard.

```dart
@override
void initState() {
  super.initState();
  WidgetsBinding.instance.addPostFrameCallback((_) {
    inspector.attach(context: context);
  });
}
```

Remove it again with `inspector.detach()`.

### Log network requests

#### With Dio

Add the interceptor to your `Dio` instance and every request/response is captured automatically. Pass the `sourceDio` instance to enable the **Resend (Replay)** feature in the Network detail view.

```dart
final dio = Dio();
dio.interceptors.add(FlutterInspectorDioInterceptor(inspector, sourceDio: dio));
```

##### Multiple Dio Instances

If your app uses multiple `Dio` instances (e.g., `authDio` for authenticated API calls, `publicDio` for public assets), register the interceptor on each instance and make sure to pass the respective instance as `sourceDio`:

```dart
// Authenticated API client
final authDio = Dio();
authDio.interceptors.add(FlutterInspectorDioInterceptor(inspector, sourceDio: authDio));

// Public API client
final publicDio = Dio();
publicDio.interceptors.add(FlutterInspectorDioInterceptor(inspector, sourceDio: publicDio));
```

This guarantees that replaying a request in the Network detail view uses the exact same `Dio` instance, maintaining the correct baseUrl, interceptors, and authentication state.

#### With other HTTP clients

Build a `NetworkEntry` yourself and pass it in:

```dart
inspector.logNetwork(entry);
```

To show an in-flight request that later resolves, log the pending entry first, then log the completed one with `replaces` so it updates in place instead of duplicating:

```dart
final pending = inspector.logNetwork(NetworkEntry(method: 'GET', url: url));
// ...after the response arrives:
inspector.logNetwork(completedEntry, replaces: pending);
```

### Inside the Network tab

- **Search & filter**: filter the call list by URL, method, or status code (case-insensitive); method and status (`2xx`/`3xx`/`4xx`/`5xx`/`Failed`) chips narrow it further.
- **Call details**: tap any call for a structured view — General (method, URL, status with color coding, duration, request/response sizes), Query Parameters, Headers, and JSON-pretty bodies. Truncated bodies are clearly marked.
- **Sharing**: copy the call as a runnable `cURL` command, copy the full details as text, or open the system share sheet (native via `share_plus`, web via the browser Web Share API — falls back to the clipboard when unavailable).
- **Replay / Resend**: for requests captured with a `sourceDio` provided to the interceptor, you can trigger a "Resend" action in the detail view to replay the request locally using the same Dio client (carrying the same headers, base URL, and interceptors). Replayed requests automatically show up as new entries with a dedicated "Replay" label.

### Live notification (opt-in)

A continuously-updated system notification can summarise the latest call and the running total. It is **disabled by default** — enable it explicitly:

```dart
final inspector = FlutterInspector(showNetworkNotification: true);
```

Once enabled, the inspector requests notification permission for you when it initialises — the host app does not need to add any permission-handling code.

**Notification behaviour**:

- **Android**: appears as a silent heads-up banner (no sound or vibration) when a new API call arrives. The banner animates in and dismisses automatically. Subsequent calls within a 2-second window silently update the notification content without re-alerting. After 2 seconds, the next call triggers another heads-up alert.
- **iOS / macOS**: displays a foreground banner when a new API call arrives, throttled the same way as Android. **This requires one line of setup in your `AppDelegate` — see [Required iOS / macOS setup](#required-ios--macos-setup) below.** Without it, iOS silently suppresses the foreground banner (the entry is still delivered to Notification Center).
- The notification uses a dedicated high-priority Android channel (`flutter_inspector_network_v2`) — if you upgrade from an earlier version, the old notification channel is automatically deleted and will not appear in system settings.

To make **tapping the notification open the dashboard on the Network tab**, pass a `navigatorKey` that is also wired into your `MaterialApp`:

```dart
final navigatorKey = GlobalKey<NavigatorState>();

final inspector = FlutterInspector(
  showNetworkNotification: true,
  navigatorKey: navigatorKey,
);

MaterialApp(navigatorKey: navigatorKey, /* ... */);
```

Without a `navigatorKey` the notification still shows; tapping it is simply a no-op since there is no navigation context to route from.

<details>
<summary>Android setup (required)</summary>

`flutter_local_notifications` relies on Java 8+ APIs, so your app's Gradle module must enable [core library desugaring](https://developer.android.com/studio/write/java8-support#library-desugaring) — this is needed whether or not notifications are enabled, otherwise the app will not build. In `android/app/build.gradle.kts`:

```kotlin
android {
    defaultConfig {
        multiDexEnabled = true
    }
    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
```

Also ensure a notification icon exists at `@mipmap/ic_launcher` (default Flutter apps already have it). On Android 13+ the `POST_NOTIFICATIONS` runtime permission is requested automatically when the inspector initialises.

</details>

#### Required iOS / macOS setup

On iOS / macOS, the user is prompted for notification permission when the inspector initialises. The permission alone is **not** enough to show a banner while your app is in the **foreground**: the system only presents a foreground notification when a `UNUserNotificationCenterDelegate` returns it from `willPresentNotification`.

##### iOS Setup
`FlutterAppDelegate` on iOS already implements that forwarding and conforms to `UNUserNotificationCenterDelegate`, so your host app only needs to assign it in `AppDelegate.swift`:

```swift
import UserNotifications // add this import

// ...inside application(_:didFinishLaunchingWithOptions:), before `return super...`:
if #available(iOS 10.0, *) {
  UNUserNotificationCenter.current().delegate = self as UNUserNotificationCenterDelegate
}
```

##### macOS Setup
Unlike iOS, `FlutterAppDelegate` on macOS does **not** conform to `UNUserNotificationCenterDelegate`. You must explicitly declare compliance and implement the callback in `macos/Runner/AppDelegate.swift`:

```swift
import UserNotifications // add this import

@main
class AppDelegate: FlutterAppDelegate, UNUserNotificationCenterDelegate {
  override func applicationDidFinishLaunching(_ notification: Notification) {
    UNUserNotificationCenter.current().delegate = self
    super.applicationDidFinishLaunching(notification)
  }

  // Handle foreground notifications on macOS
  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    completionHandler([.alert, .sound])
  }
}
```

See [`example/ios/Runner/AppDelegate.swift`](example/ios/Runner/AppDelegate.swift) and [`example/macos/Runner/AppDelegate.swift`](example/macos/Runner/AppDelegate.swift) for working references. **Without this setup no foreground banner appears on iOS / macOS** — the notification is still delivered silently to Notification Center, and tapping it still works.

If permission is denied or the platform isn't supported, the notifier degrades silently to a no-op — it never crashes your app.

### Log messages

```dart
inspector.log('User signed in', level: LogLevel.info);

inspector.log(
  'Payment failed',
  level: LogLevel.error,
  data: {'orderId': 'A123', 'amount': 4200},
  stackTrace: stackTrace.toString(),
);
```

Available levels: `verbose`, `debug`, `info`, `warning`, `error`.

### Uncaught error capture (opt-in)

By default you have to log errors yourself. Enable **uncaught error capture** to have the inspector automatically turn uncaught errors into `error`-level Console logs — no manual `try/catch` needed.

It is **disabled by default** so the package never touches your error handling unless you ask. Enable it on the constructor:

```dart
final inspector = FlutterInspector(captureUncaughtErrors: true);
```

This wires three standard Flutter hooks — `FlutterError.onError` (build/layout/paint errors), `PlatformDispatcher.instance.onError` (uncaught async errors, including unawaited `Future` errors), and `ErrorWidget.builder` (which widget failed to build). Together they cover framework, asynchronous and build-time errors without wrapping `runApp` in a custom zone, so there is no `Zone mismatch` to manage.

> **Errors are never swallowed.** Every hook **chains/wraps** your existing handler rather than replacing it: the inspector records the error and then forwards it downstream (your handler, or Flutter's default presentation — debug red screen / release grey screen unchanged). The capture is purely additive.

Captured errors appear as red logs in the **Console** tab. Tap any log that carries a stack trace or structured data to open a detail view with a copyable stack trace and the structured payload, plus copy/share actions.

### Track navigation

Nothing to do here — routes are tracked automatically once you register `inspector.navigatorObserver` in `navigatorObservers` (see [Initialize](#initialize)). Pushes, pops, and replacements all show up in the Navigator tab.

### Track database operations

Record database operations so you can review them in the dashboard.

```dart
inspector.database(
  DatabaseOperation.update,
  'users',
  affectedRows: 1,
  data: {'query': 'UPDATE users SET name = ? WHERE id = ?'},
);
```

Available operations: `insert`, `update`, `delete`, `query`.

### Browse database tables

You can browse tables and rows directly from the Database tab. By default, operations logged via `inspector.database(...)` are grouped into virtual tables.

To browse real databases (e.g. SQLite, ObjectBox), implement `DatabaseBrowserSource` and register it.

#### SQLite Adapter Example
Here is a complete, copy-pasteable implementation of `DatabaseBrowserSource` for `sqflite`:

```dart
import 'package:flutter_inspector_kit/flutter_inspector_kit.dart';
import 'package:sqflite/sqflite.dart';

class SqfliteBrowserSource implements DatabaseBrowserSource {
  SqfliteBrowserSource(this._db, {this.name = 'SQLite database'});

  final Database _db;

  @override
  final String name;

  @override
  Future<List<DatabaseTableInfo>> listTables() async {
    final List<Map<String, Object?>> tables = await _db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
    );

    final List<DatabaseTableInfo> result = [];
    for (final table in tables) {
      final name = table['name'] as String;
      final countResult = await _db.rawQuery('SELECT COUNT(*) as count FROM "$name"');
      final rowCount = Sqflite.firstIntValue(countResult);
      result.add(DatabaseTableInfo(name: name, rowCount: rowCount));
    }
    return result;
  }

  @override
  Future<DatabaseTablePage> fetchRows(
    String tableName, {
    int limit = 200,
    int offset = 0,
  }) async {
    final countResult = await _db.rawQuery('SELECT COUNT(*) as count FROM "$tableName"');
    final totalRows = Sqflite.firstIntValue(countResult) ?? 0;

    final List<Map<String, Object?>> queryResult = await _db.rawQuery(
      'SELECT * FROM "$tableName" LIMIT ? OFFSET ?',
      [limit, offset],
    );

    if (queryResult.isEmpty) {
      final tableInfo = await _db.rawQuery('PRAGMA table_info("$tableName")');
      final columns = tableInfo.map((info) => info['name'] as String).toList();
      return DatabaseTablePage(
        columns: columns,
        rows: const [],
        totalRows: totalRows,
      );
    }

    final columns = queryResult.first.keys.toList();
    final rows = queryResult.map((map) {
      return columns.map((col) => map[col]).toList();
    }).toList();

    return DatabaseTablePage(
      columns: columns,
      rows: rows,
      totalRows: totalRows,
    );
  }
}
```

#### ObjectBox Adapter Example
For ObjectBox, since Box/Entity represents a table and reflection is not available at runtime to convert entities to map, you can register entities manually:

```dart
import 'package:flutter_inspector_kit/flutter_inspector_kit.dart';
import 'package:objectbox/objectbox.dart';

class ObjectBoxEntityInfo<T> {
  ObjectBoxEntityInfo({
    required this.name,
    required this.box,
    required this.toMap,
  });

  final String name;
  final Box<T> box;
  final Map<String, dynamic> Function(T) toMap;
}

class ObjectBoxBrowserSource implements DatabaseBrowserSource {
  ObjectBoxBrowserSource({
    required this.entities,
    this.name = 'ObjectBox database',
  });

  final List<ObjectBoxEntityInfo> entities;

  @override
  final String name;

  @override
  Future<List<DatabaseTableInfo>> listTables() async {
    return entities.map((e) {
      return DatabaseTableInfo(
        name: e.name,
        rowCount: e.box.count(),
      );
    }).toList();
  }

  @override
  Future<DatabaseTablePage> fetchRows(
    String tableName, {
    int limit = 200,
    int offset = 0,
  }) async {
    final entityInfo = entities.firstWhere((e) => e.name == tableName);
    final totalRows = entityInfo.box.count();

    // Query with offset and limit
    final query = entityInfo.box.query().build();
    query.limit = limit;
    query.offset = offset;
    final items = query.find();
    query.close();

    if (items.isEmpty) {
      return DatabaseTablePage(
        columns: [],
        rows: const [],
        totalRows: totalRows,
      );
    }

    final maps = items.map((item) => entityInfo.toMap(item)).toList();
    final columns = maps.first.keys.toList();
    final rows = maps.map((map) => columns.map((col) => map[col]).toList()).toList();

    return DatabaseTablePage(
      columns: columns,
      rows: rows,
      totalRows: totalRows,
    );
  }
}
```

#### Registration
You can register these sources when initializing `FlutterInspector` or dynamically at runtime:

```dart
// At initialization
final inspector = FlutterInspector(
  databaseSources: [SqfliteBrowserSource(db)],
);

// Or dynamically
inspector.registerDatabaseSource(SqfliteBrowserSource(db));
```

## 🕹️ Example

A complete, runnable integration lives in the [`example/`](example/) directory:

```sh
cd example
flutter run
```

## 📄 License

This project is licensed under the terms described in the [LICENSE](LICENSE) file.
