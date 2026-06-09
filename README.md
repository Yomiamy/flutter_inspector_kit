# flutter_inspector

A multi-inspector tool integration for Flutter.

> **Status:** early skeleton. The public API is a placeholder while the inspector
> integrations are being built out. Expect breaking changes before `1.0.0`.

## Installation

Add the package to your `pubspec.yaml`:

```yaml
dependencies:
  flutter_inspector: ^0.0.1
```

Then fetch it:

```sh
flutter pub get
```

## Usage

```dart
import 'package:flutter_inspector/flutter_inspector.dart';

void main() {
  const inspector = FlutterInspector();
  debugPrint('flutter_inspector ${FlutterInspector.version}');
}
```

A runnable example lives in [`example/`](example/).

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file
for details.
