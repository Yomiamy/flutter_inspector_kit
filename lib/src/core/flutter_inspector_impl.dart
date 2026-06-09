import 'package:flutter/widgets.dart';

import '../models/database_entry.dart';
import '../models/database_operation.dart';
import '../models/log_entry.dart';
import '../models/log_level.dart';
import '../models/navigator_entry.dart';
import '../models/network_entry.dart';
import '../observers/navigator_observer.dart';
import '../ui/dashboard/dashboard_modal.dart';
import '../ui/widgets/inspector_fab.dart';
import 'inspector_registry.dart';

/// The core entry point for the Flutter Inspector.
class FlutterInspector {
  /// Package version.
  static const String version = '0.0.1';

  /// Creates a new FlutterInspector instance.
  ///
  /// This should typically be instantiated once at app startup and retained
  /// globally. It maintains its own internal buffers and state.
  FlutterInspector({
    this.customTab,
    this.customTabTitle = 'Custom',
    this.magicalTapCount = 5,
    int bufferSize = 500,
  }) : _registry = InspectorRegistry(bufferSize: bufferSize) {
    _navigatorObserver = FlutterInspectorNavigatorObserver(_registry.navigator);
  }

  /// Optional widget for a 5th tab in the dashboard.
  final Widget? customTab;

  /// The title of the custom tab.
  final String customTabTitle;

  /// How many consecutive taps trigger the dashboard via MagicalTap.
  final int magicalTapCount;

  final InspectorRegistry _registry;
  late final FlutterInspectorNavigatorObserver _navigatorObserver;

  /// The observer to be added to MaterialApp's navigatorObservers.
  FlutterInspectorNavigatorObserver get navigatorObserver => _navigatorObserver;

  /// Exposed for internal testing.
  @visibleForTesting
  InspectorRegistry get registry => _registry;

  /// Retrieves the current console logs.
  List<LogEntry> get logEntries => _registry.log.entries;

  /// Clears all console logs.
  void clearLogs() => _registry.log.clear();

  /// Retrieves the current network logs.
  List<NetworkEntry> get networkEntries => _registry.network.entries;

  /// Clears all network logs.
  void clearNetwork() => _registry.network.clear();

  /// Retrieves the current navigator history.
  List<NavigatorEntry> get navigatorEntries => _registry.navigator.entries;

  /// Clears all navigator history.
  void clearNavigator() => _registry.navigator.clear();

  /// Retrieves the current database logs.
  List<DatabaseEntry> get databaseEntries => _registry.database.entries;

  /// Clears all database logs.
  void clearDatabase() => _registry.database.clear();

  OverlayEntry? _overlayEntry;

  /// Mounts the FAB overlay onto the screen.
  void attach({
    required BuildContext context,
    bool visible = true,
  }) {
    if (_overlayEntry != null) return;
    _overlayEntry = OverlayEntry(
      builder: (context) => InspectorFab(
        onTap: () => openDashboard(context),
        visible: visible,
      ),
    );
    Overlay.of(context).insert(_overlayEntry!);
  }

  /// Removes the FAB overlay.
  void detach() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  /// Records a log message.
  void log(
    String message, {
    LogLevel level = LogLevel.info,
    String? stackTrace,
    Map<String, dynamic>? data,
  }) {
    _registry.log.add(LogEntry(
      message: message,
      level: level,
      stackTrace: stackTrace,
      data: data,
    ));
  }

  /// Records a network request or response.
  void logNetwork(NetworkEntry entry) {
    _registry.network.add(entry);
  }

  /// Records a database operation.
  void database(
    DatabaseOperation operation,
    String tableName, {
    Map<String, dynamic>? data,
    int? affectedRows,
  }) {
    _registry.database.add(DatabaseEntry(
      operation: operation,
      tableName: tableName,
      data: data,
      affectedRows: affectedRows,
    ));
  }

  /// Opens the full-screen dashboard modal.
  void openDashboard(BuildContext context) {
    DashboardModal.show(context, this);
  }
}
