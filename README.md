# 🔍 Flutter Inspector

In-app, multi-inspector debugging overlay for Flutter apps — logs, network, navigation, and database, all behind one unified API.

## 📦 Features

- 🪵 **Console Inspector**: Capture app logs across five severity levels (verbose, debug, info, warning, error), with optional structured data and stack traces.
- 📡 **Network Inspector**: Intercept HTTP traffic via a Dio interceptor, then inspect structured request/response details (query params, headers, JSON-pretty bodies, sizes, status color coding), search/filter the call list, share calls as cURL/text, and surface a live system notification.
- 🧭 **Navigator Inspector**: Track route pushes, pops, and replacements automatically.
- 🗄️ **Database Inspector**: Record database operations (insert / update / delete / query) with affected-row counts and payloads.
- 👆 **Magical tap & floating button**: Open the full-screen dashboard with a hidden multi-tap gesture or a draggable in-app FAB.

## 🪚 Installation

Add `flutter_inspector` to your `pubspec.yaml`:

```yaml
dependencies:
  flutter_inspector: ^0.0.1
```

Then run:

```sh
flutter pub get
```

## 🚀 Usage

### Initialize

Create a single shared `FlutterInspector` instance and wire it into your app. Register the navigator observer to track routes, and wrap your app in `FlutterInspectorMagicalTap` so a hidden gesture can open the dashboard from anywhere.

```dart
import 'package:flutter/material.dart';
import 'package:flutter_inspector/flutter_inspector.dart';

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

### Floating button (FAB)

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

### 📡 Network — with Dio

Add the interceptor to your `Dio` instance and every request/response is captured automatically.

```dart
final dio = Dio();
dio.interceptors.add(FlutterInspectorDioInterceptor(inspector));
```

Using a different HTTP client? Build a `NetworkEntry` yourself and pass it in:

```dart
inspector.logNetwork(entry);
```

#### Inside the Network tab

- **Search & filter**: a search box filters the call list by URL, method, or status code (case-insensitive). Method and status (`2xx`/`3xx`/`4xx`/`5xx`/`Failed`) chips narrow it further.
- **Call details**: tap any call to open a structured view — General (method, URL, status with color coding, duration, request/response sizes), Query Parameters, Headers (key-value tables), and JSON-pretty bodies. Truncated bodies are clearly marked.
- **Sharing**: from the detail view, copy the call as a runnable `cURL` command, copy the full details as text, or open the system share sheet (via `share_plus`).

#### Live notification (opt-in)

A continuously-updated system notification can summarise the latest call and the running total. It is **disabled by default** — enable it explicitly:

```dart
final inspector = FlutterInspector(showNetworkNotification: true);
```

Once enabled, the inspector requests notification permission for you when it initialises — the host app does not need to add any permission-handling code.

**Notification behaviour**:
- **Android**: appears as a silent heads-up banner (no sound or vibration) when a new API call arrives. The banner animates in and dismisses automatically. Subsequent calls within a 5-second window silently update the notification content without re-alerting. After 5 seconds, the next call triggers another heads-up alert.
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

Platform setup:

- **Android (required)**: `flutter_local_notifications` relies on Java 8+ APIs, so your app's Gradle module must enable [core library desugaring](https://developer.android.com/studio/write/java8-support#library-desugaring) — this is needed whether or not notifications are enabled, otherwise the app will not build. In `android/app/build.gradle.kts`:

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
- **iOS / macOS**: the user is prompted for notification permission when the inspector initialises.

If permission is denied or the platform isn't supported, the notifier degrades silently to a no-op — it never crashes your app.

### 🪵 Logging

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

### 🗄️ Database

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

## 📱 Example

A complete, runnable integration lives in the [`example/`](example/) directory:

```sh
cd example
flutter run
```

## 📄 License

This project is licensed under the terms described in the [LICENSE](LICENSE) file.
