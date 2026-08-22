import 'package:flutter_inspector_kit/flutter_inspector_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../kv/shared_prefs_browser_source.dart';

/// Demonstrates browsing SharedPreferences in the inspector's Storage tab.
///
/// The Storage tab only appears once a key-value source is registered, so this
/// seed is what makes the tab show up in the example app.
class SharedPrefsDemo {
  SharedPrefsDemo(this._inspector);

  final FlutterInspector _inspector;
  bool _registered = false;

  /// Seed values covering every [KeyValueType], plus the two keys QA actually
  /// chases: a stale auth token and a stuck feature flag.
  static const _seed = <String, Object>{
    'auth_token': 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.demo',
    'feature_new_checkout': false,
    'retry_count': 3,
    'cache_ratio': 0.75,
    'recent_searches': <String>['shoes', 'jacket'],
  };

  /// Writes the seed values and registers the source with the inspector.
  ///
  /// Returns a status message for the caller to surface (e.g. via SnackBar).
  /// Idempotent: a second call after a successful registration is a no-op.
  Future<String?> seed() async {
    if (_registered) return null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('auth_token', _seed['auth_token']! as String);
      await prefs.setBool(
        'feature_new_checkout',
        _seed['feature_new_checkout']! as bool,
      );
      await prefs.setInt('retry_count', _seed['retry_count']! as int);
      await prefs.setDouble('cache_ratio', _seed['cache_ratio']! as double);
      await prefs.setStringList(
        'recent_searches',
        _seed['recent_searches']! as List<String>,
      );

      _inspector.registerKeyValueSource(SharedPrefsBrowserSource(prefs));
      _registered = true;
      return 'SharedPreferences seeded — open the Storage tab';
    } catch (e) {
      return 'SharedPreferences seeding failed: $e';
    }
  }
}
