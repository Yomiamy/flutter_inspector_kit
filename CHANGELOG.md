## Unreleased

### Added
* **Uncaught error capture (opt-in)**: pass `captureUncaughtErrors: true` to `FlutterInspector(...)`, or wrap `runApp` with `FlutterInspector.runGuarded(...)`, to capture uncaught errors from `FlutterError.onError`, `PlatformDispatcher.instance.onError`, `ErrorWidget.builder` and guarded zones as `LogLevel.error` logs in the Console tab. Defaults to **off**; when on, every hook chains/wraps the existing host handler — errors are always forwarded downstream, never swallowed.
* **Expandable Console error logs**: tapping a Console log that carries a `stackTrace` or structured `data` now opens a detail view (`LogDetailView`) showing the message, level, timestamp, a selectable/copyable stack trace, and the structured data — with copy/share actions.

## 0.2.4

### Added
* Network requests and responses captured by `FlutterInspectorDioInterceptor` are now mirrored to the Console tab (at `debug` level), so HTTP traffic is visible alongside other logs.
* `FlutterInspectorNavigatorObserver` now mirrors route changes (push / pop / replace / remove) to the Console tab at `warning` level, in addition to the Navigator history.

### Changed
* Adjusted the `LogLevel.debug` text color in the Console tab to blue-grey for better visibility.

### Fixed
* Fixed the `Status` row in the Network detail view's General section so its value aligns with the other fields (Method, URL, Duration, etc.) instead of starting at an inconsistent position.

## 0.2.3

### Fixed
* Fixed foreground notification banner on macOS where the host app `AppDelegate` failed to cast to `UNUserNotificationCenterDelegate`. macOS hosts must now explicitly conform and handle the callback.
* Resolved a race condition during cold-starts where network notifications logged before the notifier finished initialization were lost.
* Fixed the `README.md` setup instructions to separate iOS and macOS delegate compliance procedures.

## 0.2.2

### Added
* `FlutterInspectorNavigatorObserver` now resolves route `widgetType` and name natively by default.
* Added support to filter out the internal `DashboardModal` route (`flutter_inspector_dashboard`) from the Navigator history logs to prevent UI noise.
* Added a `Makefile` for automated common Flutter development tasks.

### Changed
* Refactored project directory structure: renamed internal `flutter_inspector_impl.dart` to `flutter_inspector.dart` and `integrations` directory to `interceptors`.

### Fixed
* Fixed a bug in the example app where null navigator context could crash the app when attempting to open the dashboard modal.

## 0.2.1

### Fixed
* Raised `dio` lower bound to `^5.2.0` to match the actual API usage (`DioException`), fixing the pub.dev downgrade analysis.
* Restored WASM compatibility: web builds now use the browser Web Share API (`package:web`) instead of `share_plus`, and the network notifier resolves to a no-op stub on web, keeping `dart:io` out of the web import graph.
* Dismissing the web share sheet (`AbortError`) is now treated as a cancel instead of a failure, so it no longer triggers the clipboard fallback.

## 0.2.0

### Added
* Database table browser with two-level navigation (table list page and row grid view).
* Multi-direction scrolling (horizontal and vertical) in row grid view.
* Local column sorting with NULLs always sorted to the end in both directions.
* Dialog value preview and copy for individual grid cell values.
* Pagination for row grid (200 rows limit with 'Load More' button).
* Public `DatabaseBrowserSource`, `DatabaseTableInfo`, and `DatabaseTablePage` classes.
* `FlutterInspector.registerDatabaseSource` and constructor parameter `databaseSources` to dynamically registry third-party databases (e.g. SQLite, ObjectBox).

### Changed
* Redesigned Database tab from chronological operation list to database table list view.

## 0.1.0

Initial release on pub.dev (package renamed from `flutter_inspector` to `flutter_inspector_kit`).

* Console, Network, Navigator, and Database inspectors behind a single unified API.
* In-app overlay FAB and full-screen Dashboard.
* `Dio` interceptor for network traffic capture.
* `MagicalTap` widget for gesture-based invocation.
* Network notification heads-up banner: silent heads-up on Android (HIGH priority channel) and foreground banner on iOS, with automatic dismissal and visual feedback.
* Notification throttling: consecutive network calls within a 2-second window update the notification in place without re-alerting.
* Android notification channel `flutter_inspector_network_v2` (HIGH importance); the legacy `flutter_inspector_network` channel is automatically deleted during upgrade.
* Dio interceptor updates the pending request entry in place when its response or error arrives (no duplicate "Pending" entries); `logNetwork` gained an optional `replaces` parameter and returns the stored entry.
