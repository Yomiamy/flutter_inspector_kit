// Pure redaction helpers for sensitive network data. No Flutter dependencies,
// so everything here is unit-testable in isolation.

/// Placeholder substituted for a sensitive header value. A fixed string so it
/// leaks neither the value nor its length.
const String kRedactedValue = '••••';

/// Header keys whose values are masked, compared case-insensitively.
const Set<String> kSensitiveHeaderKeys = {
  'authorization',
  'cookie',
  'set-cookie',
  'x-api-key',
};

/// Returns a copy of [headers] with the values of any sensitive keys
/// (see [kSensitiveHeaderKeys], matched case-insensitively) replaced by
/// [kRedactedValue]. Non-sensitive entries and the original key casing are
/// preserved. The input map is never mutated.
Map<String, dynamic> redactHeaders(Map<String, dynamic> headers) {
  return headers.map((key, value) {
    if (kSensitiveHeaderKeys.contains(key.toLowerCase())) {
      return MapEntry(key, kRedactedValue);
    }
    return MapEntry(key, value);
  });
}
