import 'package:flutter/foundation.dart';

/// The value types a key-value store can hold.
///
/// Mirrors the types `SharedPreferences` exposes natively, so a host
/// implementation never has to map an unsupported type.
enum KeyValueType { string, int, double, bool, stringList }

/// An abstract interface representing a browseable key-value store.
///
/// Implemented by the host app — the package ships no concrete implementation
/// and takes no dependency on `shared_preferences` or `flutter_secure_storage`.
abstract class KeyValueBrowserSource {
  /// The user-facing name of the source, e.g., 'SharedPreferences'.
  String get name;

  /// Lists every entry currently held by this source.
  Future<List<KeyValueEntry>> listAll();

  /// Writes [value] to [key], replacing any existing value.
  ///
  /// [value] arrives already converted to the entry's original type, so an
  /// implementation can dispatch straight to the matching setter.
  Future<void> setValue(String key, Object? value);

  /// Removes [key] from this source.
  Future<void> remove(String key);

  /// Removes every key from this source.
  Future<void> clear();
}

/// Parses user-typed [input] into [type], or returns null if it cannot.
///
/// A null result means "reject this edit" — the caller must not write it.
/// Note that an empty [KeyValueType.stringList] input parses to an empty list,
/// which is a valid value rather than a failure.
Object? parseKeyValueInput(String input, KeyValueType type) => switch (type) {
  // Kept verbatim: whitespace may be part of the intended value.
  KeyValueType.string => input,
  KeyValueType.int => int.tryParse(input.trim()),
  KeyValueType.double => double.tryParse(input.trim()),
  // Only 'true'/'false'. '1'/'0' would be ambiguous with an int edit.
  KeyValueType.bool => switch (input.trim().toLowerCase()) {
    'true' => true,
    'false' => false,
    _ => null,
  },
  KeyValueType.stringList =>
    input.isEmpty ? const <String>[] : input.split('\n'),
};

/// A single key-value pair read from a [KeyValueBrowserSource].
@immutable
class KeyValueEntry {
  const KeyValueEntry({
    required this.key,
    required this.value,
    required this.type,
  });

  /// The entry key.
  final String key;

  /// The stored value, or null if the source reported no value.
  final Object? value;

  /// The value's type, used to parse edits back into the original type.
  final KeyValueType type;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! KeyValueEntry) return false;
    if (other.key != key || other.type != type) return false;
    // stringList values are compared by content, not by identity.
    if (value is List && other.value is List) {
      return listEquals(other.value as List?, value as List?);
    }
    return other.value == value;
  }

  @override
  int get hashCode => Object.hash(
    key,
    value is List ? Object.hashAll(value as List) : value,
    type,
  );

  @override
  String toString() => 'KeyValueEntry($key, ${type.name}: $value)';
}
