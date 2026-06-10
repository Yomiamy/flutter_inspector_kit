import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../models/network_entry.dart';

/// Shows a single, continuously-updated system notification summarising network
/// activity (latest call + total count). Disabled by default; the owner enables
/// it explicitly. All platform calls degrade safely: if initialisation or
/// permission fails, the notifier silently becomes a no-op instead of crashing.
class NetworkNotifier {
  /// Creates a notifier. Pass a custom [plugin] in tests to avoid the platform.
  NetworkNotifier({
    FlutterLocalNotificationsPlugin? plugin,
    this.onTap,
  }) : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  /// Invoked when the user taps the notification (payload routing handled by
  /// the owner, e.g. opening the Network tab).
  final VoidCallback? onTap;

  final FlutterLocalNotificationsPlugin _plugin;

  static const int _notificationId = 0x6E657477; // 'netw'
  static const String _channelId = 'flutter_inspector_network';
  static const String _channelName = 'Network Inspector';

  bool _initialized = false;
  bool _available = false;

  /// Whether the notifier successfully initialised and can post notifications.
  bool get isAvailable => _available;

  /// Initialises the plugin and requests notification permission so the host
  /// app does not have to. Safe to call once; repeat calls are no-ops. On any
  /// failure the notifier stays a no-op.
  ///
  /// Permission is requested at init time. A denied permission is the user's
  /// choice, not a failure: the notifier stays available (show() simply has no
  /// visible effect) so a later grant in system settings takes effect without
  /// re-initialising.
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      const settings = InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
        macOS: DarwinInitializationSettings(),
      );
      await _plugin.initialize(
        settings: settings,
        onDidReceiveNotificationResponse: (_) => onTap?.call(),
      );
      _available = true;
      // Permission is requested after the notifier is marked available, in its
      // own guard: a denied or failed request is the user's/platform's concern,
      // not a reason to disable the notifier entirely.
      await _requestPermission();
    } catch (e) {
      _available = false;
      debugPrint('[FlutterInspector] notification init failed: $e');
    }
  }

  /// Requests notification permission on each platform that needs it. Wrapped in
  /// its own guard so a missing platform implementation (e.g. in tests) or a
  /// denied request never disables the notifier — it only affects whether the
  /// notification is actually shown.
  Future<void> _requestPermission() async {
    try {
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
      await _plugin
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);
      await _plugin
          .resolvePlatformSpecificImplementation<
              MacOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    } catch (e) {
      debugPrint('[FlutterInspector] notification permission request failed: $e');
    }
  }

  /// Posts or updates the single network notification with [entry] and the
  /// running [totalCount]. No-op when the notifier is unavailable.
  Future<void> showOrUpdate(NetworkEntry entry, int totalCount) async {
    if (!_available) return;
    try {
      final status = entry.isComplete
          ? '${entry.statusCode ?? entry.error ?? '-'}'
          : 'Pending';
      const androidDetails = AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: 'Live HTTP activity captured by Flutter Inspector',
        importance: Importance.low,
        priority: Priority.low,
        ongoing: true,
        onlyAlertOnce: true,
        showWhen: false,
      );
      const details = NotificationDetails(
        android: androidDetails,
        iOS: DarwinNotificationDetails(presentSound: false),
        macOS: DarwinNotificationDetails(presentSound: false),
      );
      await _plugin.show(
        id: _notificationId,
        title: 'Network · $totalCount calls',
        body: '[${entry.method}] ${entry.url} · $status',
        notificationDetails: details,
      );
    } catch (e) {
      debugPrint('[FlutterInspector] notification update failed: $e');
    }
  }

  /// Cancels the network notification, if any.
  Future<void> cancel() async {
    if (!_available) return;
    try {
      await _plugin.cancel(id: _notificationId);
    } catch (_) {
      // ignore
    }
  }
}
