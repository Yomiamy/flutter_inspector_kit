import 'package:flutter/widgets.dart';

import '../models/database_browser_source.dart';
import '../models/database_entry.dart';
import '../models/database_operation.dart';
import '../models/log_entry.dart';
import '../sources/operation_log_source.dart';
import '../models/log_level.dart';
import '../models/navigator_entry.dart';
import '../models/network_entry.dart';
import '../notifications/network_notifier.dart';
import '../observers/navigator_observer.dart';
import '../ui/dashboard/dashboard_modal.dart';
import '../ui/widgets/inspector_fab.dart';
import 'inspector_registry.dart';

/// The core entry point for the Flutter Inspector.
class FlutterInspector {
  /// Package version.
  static const String version = '0.2.0';

  /// Creates a new FlutterInspector instance.
  ///
  /// This should typically be instantiated once at app startup and retained
  /// globally. It maintains its own internal buffers and state.
  FlutterInspector({
    this.customTab,
    this.customTabTitle = 'Custom',
    this.magicalTapCount = 5,
    this.showNetworkNotification = false,
    this.navigatorKey,
    int bufferSize = 500,
    NetworkNotifier? notifier,
    List<DatabaseBrowserSource>? databaseSources,
  }) : _registry = InspectorRegistry(bufferSize: bufferSize) {
    _navigatorObserver = FlutterInspectorNavigatorObserver(_registry.navigator);
    _operationLogSource = OperationLogSource(_registry.database);
    if (databaseSources != null) {
      _customDatabaseSources.addAll(databaseSources);
    }
    if (showNetworkNotification) {
      _notifier =
          notifier ?? NetworkNotifier(onTap: _openNetworkFromNotification);
      _notifier!.init();
      _registry.network.onAdd = (entry, total) {
        _notifier!.showOrUpdate(entry, total);
      };
    }
  }

  /// Optional widget for a 5th tab in the dashboard.
  final Widget? customTab;

  /// The title of the custom tab.
  final String customTabTitle;

  /// How many consecutive taps trigger the dashboard via MagicalTap.
  final int magicalTapCount;

  /// Whether to surface a live system notification summarising network calls.
  /// Defaults to `false` so apps opt in explicitly (and avoid permission
  /// prompts they didn't ask for).
  final bool showNetworkNotification;

  /// Optional navigator key used to open the dashboard from a notification tap
  /// (US-3). When supplied alongside [showNetworkNotification], tapping the
  /// network notification opens the dashboard on the Network tab. Without it,
  /// the tap is a no-op since there is no [BuildContext] to route from.
  final GlobalKey<NavigatorState>? navigatorKey;

  NetworkNotifier? _notifier;

  final InspectorRegistry _registry;
  late final FlutterInspectorNavigatorObserver _navigatorObserver;
  late final OperationLogSource _operationLogSource;
  final List<DatabaseBrowserSource> _customDatabaseSources = [];

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

  /// Retrieves the registered database browser sources.
  List<DatabaseBrowserSource> get databaseSources =>
      List.unmodifiable([_operationLogSource, ..._customDatabaseSources]);

  /// Registers a database browser source.
  void registerDatabaseSource(DatabaseBrowserSource source) {
    _customDatabaseSources.add(source);
  }

  OverlayEntry? _overlayEntry;

  /// Mounts the FAB overlay onto the screen.
  void attach({required BuildContext context, bool visible = true}) {
    if (_overlayEntry != null) return;
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;
    _overlayEntry = OverlayEntry(
      builder: (context) =>
          InspectorFab(onTap: () => openDashboard(context), visible: visible),
    );
    overlay.insert(_overlayEntry!);
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
    _registry.log.add(
      LogEntry(
        message: message,
        level: level,
        stackTrace: stackTrace,
        data: data,
      ),
    );
  }

  /// Records a network request or response, returning the stored entry.
  ///
  /// Pass the entry returned for the pending request as [replaces] when
  /// logging its completed counterpart, so the pending entry is updated in
  /// place instead of producing a duplicate list item.
  NetworkEntry logNetwork(NetworkEntry entry, {NetworkEntry? replaces}) {
    return _registry.network.add(entry, replaces: replaces);
  }

  /// Records a database operation.
  void database(
    DatabaseOperation operation,
    String tableName, {
    Map<String, dynamic>? data,
    int? affectedRows,
  }) {
    _registry.database.add(
      DatabaseEntry(
        operation: operation,
        tableName: tableName,
        data: data,
        affectedRows: affectedRows,
      ),
    );
  }

  /// Opens the full-screen dashboard modal.
  ///
  /// [initialIndex] selects the starting tab: Console (0), Network (1),
  /// Navigator (2), Database (3).
  void openDashboard(BuildContext context, {int initialIndex = 0}) {
    DashboardModal.show(context, this, initialIndex: initialIndex);
  }

  /// Opens the dashboard on the Network tab in response to a notification tap.
  /// Requires [navigatorKey] to have a mounted context; otherwise a no-op.
  void _openNetworkFromNotification() {
    final context = navigatorKey?.currentContext;
    if (context == null) return;
    openDashboard(context, initialIndex: 1);
  }
}
