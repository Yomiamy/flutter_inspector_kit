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
