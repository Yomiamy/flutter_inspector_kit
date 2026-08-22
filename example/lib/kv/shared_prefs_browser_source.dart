import 'package:flutter_inspector_kit/flutter_inspector_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Exposes [SharedPreferences] to the inspector's Storage tab.
///
/// Mirrors the adapter documented in the package README — the package itself
/// ships no key-value implementation and takes no dependency on
/// `shared_preferences`; the host app injects one.
class SharedPrefsBrowserSource implements KeyValueBrowserSource {
  SharedPrefsBrowserSource(this._prefs);

  final SharedPreferences _prefs;

  @override
  String get name => 'SharedPreferences';

  @override
  Future<List<KeyValueEntry>> listAll() async {
    return _prefs.getKeys().map((key) {
      final value = _prefs.get(key);
      return KeyValueEntry(key: key, value: value, type: _typeOf(value));
    }).toList();
  }

  @override
  Future<void> setValue(String key, Object? value) async {
    // The value arrives already parsed into the entry's original type.
    switch (value) {
      case final String v:
        await _prefs.setString(key, v);
      case final int v:
        await _prefs.setInt(key, v);
      case final double v:
        await _prefs.setDouble(key, v);
      case final bool v:
        await _prefs.setBool(key, v);
      case final List<String> v:
        await _prefs.setStringList(key, v);
    }
  }

  @override
  Future<void> remove(String key) => _prefs.remove(key);

  @override
  Future<void> clear() => _prefs.clear();

  KeyValueType _typeOf(Object? value) => switch (value) {
    int() => KeyValueType.int,
    double() => KeyValueType.double,
    bool() => KeyValueType.bool,
    List<String>() => KeyValueType.stringList,
    _ => KeyValueType.string,
  };
}
