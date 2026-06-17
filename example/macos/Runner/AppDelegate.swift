import Cocoa
import FlutterMacOS
import UserNotifications

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationDidFinishLaunching(_ notification: Notification) {
    // Required for flutter_inspector's network notification: macOS only shows a
    // foreground notification banner when a UNUserNotificationCenterDelegate
    // returns it from willPresentNotification. FlutterAppDelegate forwards that
    // callback to plugins but does not assign itself as the delegate, so the host
    // app must. Uses `as?` so it degrades to nil if the SDK ever stops conforming.
    UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate
    super.applicationDidFinishLaunching(notification)
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
