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
