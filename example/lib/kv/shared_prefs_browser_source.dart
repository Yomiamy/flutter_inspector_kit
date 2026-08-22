import 'package:flutter_inspector_kit/flutter_inspector_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Exposes [SharedPreferences] to the inspector's Storage tab.
///
/// Mirrors the adapter documented in the package README — the package itself
/// ships no key-value implementation and takes no dependency on
/// `shared_preferences`; the host app injects one.
class SharedPrefsBrowserSource implements KeyValueBrowserSource {
  SharedPrefsBrowserSource(this._prefs, {this.name = 'SharedPreferences'});

  final SharedPreferences _prefs;

  /// Shown in the Storage tab's source selector. Pass a distinct name when
  /// registering more than one store, or they are indistinguishable there.
  @override
  final String name;

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
    final ok = switch (value) {
      final String v => await _prefs.setString(key, v),
      final int v => await _prefs.setInt(key, v),
      final double v => await _prefs.setDouble(key, v),
      final bool v => await _prefs.setBool(key, v),
      final List<String> v => await _prefs.setStringList(key, v),
      _ => false,
    };
    _check(ok, 'write $key');
  }

  @override
  Future<void> remove(String key) async {
    _check(await _prefs.remove(key), 'remove $key');
  }

  @override
  Future<void> clear() async {
    _check(await _prefs.clear(), 'clear');
  }

  /// SharedPreferences reports failure by returning false rather than throwing.
  /// Swallowing that would let the inspector log an audit trail for a write
  /// that never landed, so turn it into an exception the tab can surface.
  void _check(bool ok, String what) {
    if (!ok) throw StateError('SharedPreferences failed to $what');
  }

  KeyValueType _typeOf(Object? value) => switch (value) {
    int() => KeyValueType.int,
    double() => KeyValueType.double,
    bool() => KeyValueType.bool,
    List<String>() => KeyValueType.stringList,
    _ => KeyValueType.string,
  };
}
