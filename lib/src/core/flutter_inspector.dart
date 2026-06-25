import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../inspectors/navigator_inspector.dart';
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
  static const String version = '1.0.0';

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
    this.captureUncaughtErrors = false,
    int bufferSize = 500,
    NetworkNotifier? notifier,
    List<DatabaseBrowserSource>? databaseSources,
  }) : _registry = InspectorRegistry(bufferSize: bufferSize) {
    if (captureUncaughtErrors) setupErrorHandlers();
    _navigatorObserver = FlutterInspectorNavigatorObserver(this);
    _operationLogSource = OperationLogSource(_registry.database);
    if (databaseSources != null) {
      _customDatabaseSources.addAll(databaseSources);
    }
    if (showNetworkNotification) {
      _notifier =
          notifier ?? NetworkNotifier(onTap: _openNetworkFromNotification);
      // Wire onAdd only after init() resolves. init() never rejects (it catches
      // and swallows platform errors internally), so this callback always runs.
      // Requests that arrive before init completes are not forwarded to the
      // notifier — which is correct, since _available isn't true until init
      // succeeds, so showOrUpdate would no-op on them anyway. This just avoids
      // holding a callback that fires into an uninitialised notifier.
      _notifier!.init().then((_) {
        _registry.network.onAdd = (entry, total) {
          _notifier!.showOrUpdate(entry, total);
        };
        final entries = _registry.network.entries;
        if (entries.isNotEmpty) {
          _notifier!.showOrUpdate(entries.first, entries.length);
        }
      });
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

  /// Whether to capture uncaught errors from the three standard Flutter hooks
  /// ([FlutterError.onError], [PlatformDispatcher.instance.onError],
  /// [ErrorWidget.builder]) and turn them into [LogLevel.error] log entries.
  ///
  /// Defaults to `false` so the package never touches host error handlers
  /// unless the host opts in. When `true`, all hooks chain/wrap the existing
  /// host handler — the error is always forwarded downstream, never swallowed.
  ///
  /// Notes:
  /// - The hooks capture whatever handler is installed at construction time.
  ///   If the host installs its own [FlutterError.onError] /
  ///   [PlatformDispatcher.instance.onError] *after* constructing the inspector,
  ///   that later handler replaces the inspector's wrapper and capture silently
  ///   stops (the host always wins — nothing breaks). Construct the inspector
  ///   after installing any custom handlers.
  /// - Enable this on a single, app-wide inspector. The dedup guard is
  ///   per-instance, so creating multiple capture-enabled inspectors layers the
  ///   hooks and records the same error once per instance (host errors still
  ///   forward correctly — just duplicated logs).
  /// - The hooks are not torn down: once attached they remain for the process
  ///   lifetime ([detach] only removes the FAB overlay). The `_old*` handlers
  ///   are kept solely to chain to, not to restore.
  final bool captureUncaughtErrors;

  FlutterExceptionHandler? _oldFlutterErrorHandler;
  bool Function(Object, StackTrace)? _oldPlatformDispatcherOnError;
  bool _uncaughtErrorHandlersAttached = false;

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

  /// The navigator inspector used by [navigatorObserver] to buffer events.
  NavigatorInspector get navigatorInspector => _registry.navigator;

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

  /// Attaches the three standard Flutter error hooks, chaining/wrapping any
  /// existing host handler so errors are always forwarded downstream.
  ///
  /// Idempotent: the dedup flag ensures hooks are attached at most once, so an
  /// error never produces two log entries even when [captureUncaughtErrors] and
  /// a manual [setupErrorHandlers] call are combined.
  @visibleForTesting
  void setupErrorHandlers() {
    if (_uncaughtErrorHandlersAttached) return;
    _uncaughtErrorHandlersAttached = true;

    // 1) FlutterError.onError — chain.
    // The logging call is guarded so a failure while recording can never break
    // the chain to the host handler — the error is always forwarded downstream.
    _oldFlutterErrorHandler = FlutterError.onError;
    FlutterError.onError = (details) {
      try {
        _logFlutterError(details, source: 'flutterError');
      } catch (e, s) {
        debugPrintStack(stackTrace: s, label: 'inspector log failed: $e');
      }
      if (_oldFlutterErrorHandler != null) {
        _oldFlutterErrorHandler!(details);
      } else {
        FlutterError.presentError(details);
      }
    };

    // 2) PlatformDispatcher.instance.onError — chain.
    // The logging call is guarded so a failure while recording can never alter
    // the boolean the host handler returns (its "handled" semantics are kept).
    _oldPlatformDispatcherOnError = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (e, st) {
      try {
        log(
          e.toString(),
          level: LogLevel.error,
          stackTrace: st.toString(),
          data: {
            'source': 'platformDispatcher',
            'exceptionType': e.runtimeType.toString(),
          },
        );
      } catch (err, s) {
        debugPrintStack(stackTrace: s, label: 'inspector log failed: $err');
      }
      final old = _oldPlatformDispatcherOnError;
      return old != null ? old(e, st) : false;
    };

    // 3) ErrorWidget.builder — wrap.
    final original = ErrorWidget.builder;
    ErrorWidget.builder = (details) {
      try {
        _logFlutterError(details, source: 'errorWidget');
      } catch (e, s) {
        debugPrintStack(
          stackTrace: s,
          label: 'inspector errorWidget log failed: $e',
        );
      }
      return original(details);
    };
  }

  void _logFlutterError(
    FlutterErrorDetails details, {
    required String source,
  }) {
    final data = <String, dynamic>{
      'source': source,
      'exceptionType': details.exception.runtimeType.toString(),
    };
    final library = details.library;
    if (library != null) data['library'] = library;
    final context = details.context;
    if (context != null) data['context'] = context.toString();

    log(
      details.exceptionAsString(),
      level: LogLevel.error,
      stackTrace: details.stack?.toString(),
      data: data,
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
