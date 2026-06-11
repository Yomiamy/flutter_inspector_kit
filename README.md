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

|Network Detail|Navigator|Database|
|---|---|---|
|<img width="200" src="https://github.com/Yomiamy/flutter_inspector_kit/blob/main/doc/screenshots/network_detail.png?raw=true"/>|<img width="200" src="https://github.com/Yomiamy/flutter_inspector_kit/blob/main/doc/screenshots/navigator.png?raw=true"/>|<img width="200" src="https://github.com/Yomiamy/flutter_inspector_kit/blob/main/doc/screenshots/database.png?raw=true"/>|

## 🪚 Usage

### Add to pubspec.yaml

```yaml
dependencies:
  flutter_inspector_kit: ^0.1.0
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

Add the interceptor to your `Dio` instance and every request/response is captured automatically.

```dart
final dio = Dio();
dio.interceptors.add(FlutterInspectorDioInterceptor(inspector));
```

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
- **Sharing**: copy the call as a runnable `cURL` command, copy the full details as text, or open the system share sheet (via `share_plus`).

### Live notification (opt-in)

A continuously-updated system notification can summarise the latest call and the running total. It is **disabled by default** — enable it explicitly:

```dart
final inspector = FlutterInspector(showNetworkNotification: true);
```

Once enabled, the inspector requests notification permission for you when it initialises — the host app does not need to add any permission-handling code.

**Notification behaviour**:

- **Android**: appears as a silent heads-up banner (no sound or vibration) when a new API call arrives. The banner animates in and dismisses automatically. Subsequent calls within a 2-second window silently update the notification content without re-alerting. After 2 seconds, the next call triggers another heads-up alert.
- **iOS / macOS**: displays a silent foreground banner when enabled.
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

On iOS / macOS, the user is prompted for notification permission when the inspector initialises.

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

## 🕹️ Example

A complete, runnable integration lives in the [`example/`](example/) directory:

```sh
cd example
flutter run
```

## 📄 License

This project is licensed under the terms described in the [LICENSE](LICENSE) file.
