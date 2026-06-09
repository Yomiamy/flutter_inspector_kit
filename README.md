# Flutter Inspector

A multi-inspector tool integration for Flutter. It provides an in-app overlay to inspect logs, network requests, navigator events, and database operations.

## Features
- **Console Inspector**: View application logs with different severity levels.
- **Network Inspector**: Intercept and view HTTP requests and responses (via Dio).
- **Navigator Inspector**: Track route pushes, pops, and replacements.
- **Database Inspector**: Track database operations (e.g. SQLite queries).

## Installation

Add `flutter_inspector` to your `pubspec.yaml`:

```yaml
dependencies:
  flutter_inspector: ^0.0.1
```

## Usage

Create a single instance of `FlutterInspector` and integrate it into your app:

```dart
import 'package:flutter_inspector/flutter_inspector.dart';

final inspector = FlutterInspector();

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorObservers: [inspector.navigatorObserver], // 1. Add navigator observer
      builder: (context, child) {
        // 2. Wrap your app with the MagicalTap widget to easily open the dashboard
        return FlutterInspectorMagicalTap(
          onTap: () => inspector.openDashboard(context),
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: MyHomePage(),
    );
  }
}
```

To enable the floating action button overlay (FAB), attach the inspector after the app has loaded:

```dart
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      inspector.attach(context: context);
    });
  }
```

### Dio Interceptor
To track network requests with `dio`, add the interceptor to your `Dio` instance:

```dart
final dio = Dio();
dio.interceptors.add(FlutterInspectorDioInterceptor(inspector));
```
