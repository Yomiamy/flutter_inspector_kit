## 1.7.0

### Added
* **WebView inline debugging**: introduced `WebViewBridgeAdapter` and injected JS bridge payload to seamlessly capture and translate a WebView's `console.*`, `window.onerror`, `fetch`, and `XMLHttpRequest` activity into the native Console and Network tabs.
* **First-class provenance metadata**: network and log entries now include `origin` (e.g., `NetworkOrigin.webview` vs `NetworkOrigin.dio`) and `pageUrl` fields, clearly distinguishing native HTTP traffic from WebView traffic in the detail views.

### Fixed
* **WebView bridge reliability**: capped raw bridge message size before JSON decoding to prevent memory spikes, and properly guarded `XHR` response text reads for non-text response types.

## 1.6.0

### Changed
* **Diagnostic report Timeline**: the exported report's separate "Logs" section is now a chronological mixed **Timeline** that interleaves log, network, navigation, and database entries by timestamp (newest first), surfacing cross-layer causality at a glance. The independent Network / Navigation / Database detail sections remain below it.
* **"Errors & warnings only" now filters the whole Timeline**: previously the toggle restricted only the log section; it now keeps error-signal entries across the entire Timeline stream (logs plus failed/errored network calls), while the detail sections are unaffected.

### Fixed
* **Timeline one-liner hardening**: report one-liners are now guarded against CRLF injection and malformed-URL leaks.

## 1.5.0

### Added
* **One-tap diagnostic report**: the dashboard app bar now has an export action that builds a single Markdown report — device/app header, current route stack, and the log / network / navigation / database sections — and hands it to the system share sheet. Three independent filters: time window (last 5m / last 1h / all), which sources to include, and an optional "errors & warnings only" toggle for the log section (off by default). Nothing is written to disk.
* **`DiagnosticInfoSource`**: optional injection point for device and app metadata (`FlutterInspector(diagnosticInfoSource: ...)`). This package stays free of any device-info plugin — hosts supply the values themselves, and the report header degrades to `N/A` when no source is registered. Follows the same host-injection shape as `DatabaseBrowserSource`.

## 1.4.0

### Added
* **Network error aggregation summary**: the Network tab now shows a collapsible banner above the call list that groups failed/errored requests by status code (falling back to error type for transport failures where `statusCode` is `null`), with a per-group count and first/last-seen time range. Tapping a group card filters the call list down to just that error; tapping again clears the filter. The banner aggregates from the same keyword/method/status-filtered list shown below it, so counts always match what's visible.

### Fixed
* **Scrollable TabBar alignment on Material 3**: the dashboard's tab bar now sets `tabAlignment: TabAlignment.start`, fixing tabs rendering centered/misaligned in scrollable mode under Material 3.

## 1.3.1

### Changed
* **Code quality & performance optimization**: Refactored major dashboard tabs (Console, Network, Navigator, Database) to eliminate large helper methods and decompose them into lightweight, specialized, and reusable private Widget classes, improving rendering efficiency.
* **UI widgets consolidation**: Extracted shared `DetailSection` (with `DetailKeyValueRow`) and `ErrorCard` widgets to eliminate cross-file duplicate code.
* **Centralized log level colors**: Moved log level color mapping from ConsoleTab's helper methods into a unified `LogLevelColor` extension.

## 1.3.0

### Added
* **Structured DioException error capture**: `FlutterInspectorDioInterceptor.onError` now preserves the machine-readable `errorType` (`DioExceptionType`) and the `errorStackTrace` (stringified stack trace) instead of discarding them.
* **Exception Details section**: the Network detail view now displays an "Exception Details" card section for failed requests. It clearly distinguishes between transport-layer failures (where the request did not reach the server, showing `statusCode == null`) and server-side responses (where the server returned an error status code). It also provides a monospace-styled, copyable stack trace for debugging.
* **Text export support**: `buildPlainText` exports now include the `Error Type` and the `Stack Trace` when present, improving the diagnostic value of shared logs.

## 1.2.1

### Fixed
* **Console tab clear button**: clearing the Console tab's merged timeline now wipes all four underlying sources (log, network, navigator, database) instead of only logs. Previously, network/navigator/database entries would reappear after clearing because they share the same buffers rendered in the Console tab's merged timeline.

## 1.2.0

### Added
* **Navigator active route stack visualization**: the Navigator tab now offers an "Active Stack" / "Event History" toggle. Active Stack derives the current route stack live from the recorded push/pop/replace/remove events and renders it top-first as vertical cards, with the current screen highlighted; Event History remains the original raw event log, unchanged.

## 1.1.0

### Added
* **Merged cross-layer timeline**: the Console tab now interleaves logs, network, navigation, and database events on a single timestamp-sorted timeline (newest first), with a filter chip per source to narrow it down. The same view is exposed programmatically via `FlutterInspector.mergedTimeline({sources})`, which returns `List<TimestampedEntry>` sorted by `timestamp` descending. Filter with the new `TimelineSource` enum (`log` / `network` / `nav` / `db`); a shared `displayTime` (`HH:mm:ss.mmm`) helper is available on every timeline entry.
* **Sensitive-data redaction**: a new `redactSensitiveData` constructor flag on `FlutterInspector` (defaults to `true`) masks sensitive headers — `Authorization`, `Cookie`, `Set-Cookie`, `X-Api-Key` (matched case-insensitively) — with `••••` across every Network share/export path (copy as cURL, copy as text, system share sheet). Secure by default; pass `redactSensitiveData: false` to opt out. Headers shown live inside the dashboard are unaffected.

### Changed
* The Console timeline is now assembled by merging the four event buffers at render time instead of mirroring network and navigation events into the Console as separate log strings. As a result, `FlutterInspectorDioInterceptor` no longer emits an extra `debug`-level Console log per request, and `FlutterInspectorNavigatorObserver` no longer mirrors route changes as `warning`-level logs (both introduced in 0.2.4) — those events still appear on the merged timeline via their own buffers, without the duplicate log entries.

## 1.0.0

### Added
* **Network Request Replay**: You can now resend captured HTTP requests directly within the Network detail view. It replays the request locally using the same Dio client (carrying the same headers, base URL, and interceptors). Replayed requests automatically show up as new entries in the Network tab, marked with a dedicated "Replay" label.

### Changed
* **Breaking Change**: `FlutterInspector` constructor no longer takes a `dio` parameter, and does not provide a default fallback Dio. To use the Network Request Replay feature, you must explicitly pass the source `Dio` instance when creating `FlutterInspectorDioInterceptor`.
* **Dio Interceptor Signature**: `FlutterInspectorDioInterceptor` now takes an optional named `sourceDio` parameter (`FlutterInspectorDioInterceptor(inspector, {sourceDio: dio})`). Without passing the `sourceDio`, the "Resend" action in the Network detail view will be disabled.

## 0.3.1

### Documentation
* Refreshed the README screenshots: re-captured the database browser view and added Uncaught Error and Database Browse captures sourced from the example app.
* Removed the legacy Database (operation-log) screenshot in favor of the Database Browse capture, and re-flowed the Screenshots grid to a clean 3-column layout.

## 0.3.0

### Added
* **Uncaught error capture (opt-in)**: pass `captureUncaughtErrors: true` to `FlutterInspector(...)` to capture uncaught errors from `FlutterError.onError`, `PlatformDispatcher.instance.onError` (including unawaited `Future` errors) and `ErrorWidget.builder` as `LogLevel.error` logs in the Console tab. Defaults to **off**; when on, every hook chains/wraps the existing host handler — errors are always forwarded downstream, never swallowed.
* **Expandable Console error logs**: tapping a Console log that carries a `stackTrace` or structured `data` now opens a detail view (`LogDetailView`) showing the message, level, timestamp, a selectable/copyable stack trace, and the structured data — with copy/share actions.
* Expandable Console rows now show a trailing chevron, matching the Network tab, so it is clear at a glance which logs open a detail view.

### Fixed
* A log carrying an empty-string `stackTrace` is no longer treated as expandable, so it neither appears tappable in the Console nor renders an empty stack-trace section in the detail view.

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
