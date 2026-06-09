import '../inspectors/database_inspector.dart';
import '../inspectors/log_inspector.dart';
import '../inspectors/navigator_inspector.dart';
import '../inspectors/network_inspector.dart';

/// Internal registry holding instances of the four fixed inspectors.
class InspectorRegistry {
  /// Creates a registry with inspectors initialized to the given [bufferSize].
  InspectorRegistry({int bufferSize = 500})
      : log = LogInspector(bufferSize: bufferSize),
        network = NetworkInspector(bufferCapacity: bufferSize),
        navigator = NavigatorInspector(bufferCapacity: bufferSize),
        database = DatabaseInspector(bufferCapacity: bufferSize);

  /// Inspector for console logs.
  final LogInspector log;

  /// Inspector for network requests.
  final NetworkInspector network;

  /// Inspector for navigation events.
  final NavigatorInspector navigator;

  /// Inspector for database operations.
  final DatabaseInspector database;
}
