## Unreleased

* **Network notification heads-up banner**: Network notifications now appear as silent heads-up banners on Android (HIGH priority channel) and foreground banners on iOS, with automatic dismissal and visual feedback.
* **Notification throttling**: Consecutive network calls within a 2-second window silently update the notification content without re-alerting. After 2 seconds, the next call triggers another heads-up.
* **Android notification channel migration**: Upgraded to new channel ID `flutter_inspector_network_v2` with HIGH importance. The legacy `flutter_inspector_network` channel is automatically deleted during upgrade; any manual settings on the old channel do not carry forward.
* **Fix — no more duplicate "Pending" entries**: the Dio interceptor now updates the pending request entry in place when its response or error arrives, instead of appending a second entry. `logNetwork` gained an optional `replaces` parameter (and now returns the stored entry) so custom HTTP client integrations can do the same.

## 0.0.1

* Initial release of Flutter Inspector framework.
* Includes Console, Network, Navigator, and Database inspectors.
* In-app overlay FAB and full-screen Dashboard.
* Includes `Dio` interceptor for network traffic.
* Includes `MagicalTap` widget for gesture-based invocation.
