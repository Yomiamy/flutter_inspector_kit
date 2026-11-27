import 'redaction.dart';

/// Default maximum length for a single parameter string value before truncation.
const int kDefaultMaxRoutingParamStringLength = 100;

/// Default maximum number of routing parameters recorded per navigation event.
const int kDefaultMaxRoutingParamEntries = 20;

/// Substrings that identify a routing parameter key as potentially sensitive.
/// Compared case-insensitively.
const Set<String> _kSensitiveSubstrings = {
  'password',
  'token',
  'secret',
  'apikey',
  'api_key',
  'auth',
  'credential',
  'access_token',
  'privkey',
  'private_key',
};

const Set<String> _kSensitiveWords = {'pin', 'key'};

final RegExp _kSensitiveCamelBoundary = RegExp(r'[a-z](Pin|PIN|Key|KEY)[A-Z]');

/// Normalized-key suffixes naming status or expiry metadata, not a credential.
const Set<String> _kMetadataSuffixes = {
  '_type',
  '_expires_in',
  '_expires_at',
  '_expired',
  '_expiry',
  '_mode',
  '_method',
  '_provider',
  '_step',
  '_status',
  '_required',
  '_enabled',
};

/// Captures the rest of a boolean-flag key such as `is_authenticated`.
final RegExp _kBooleanPrefix = RegExp(r'^(?:is|has|can|should)_(.*)$');

/// A boolean-flag rest ending in one of these is a multi-word credential name
/// (e.g. `has_secret_token`), so it stays on the strict path.
const Set<String> _kSecretNameSuffixes = {
  '_token',
  '_password',
  '_secret',
  '_key',
  '_apikey',
  '_credential',
  '_pin',
};

final RegExp _kCamelHump = RegExp(r'([a-z0-9])([A-Z])');

/// Returns true if [key] is recognized as containing sensitive data.
///
/// Status/expiry metadata (`token_type`, `authStatus`) and single-word boolean
/// flags (`is_authenticated`, `hasPassword`) are let through first.
bool isSensitiveRoutingKey(String key) {
  final normalized = _normalizeKey(key);
  if (_kMetadataSuffixes.any(normalized.endsWith)) return false;
  final rest = _kBooleanPrefix.firstMatch(normalized)?[1];
  if (rest != null && !_kSecretNameSuffixes.any(rest.endsWith)) return false;
  // Raw key on purpose: normalizing erases the PIN boundary in `userPINCode`.
  final lower = key.toLowerCase();
  for (final pattern in _kSensitiveSubstrings) {
    if (lower.contains(pattern)) return true;
  }
  for (final word in _kSensitiveWords) {
    if (lower == word ||
        lower.endsWith('_$word') ||
        lower.startsWith('${word}_') ||
        lower.contains('_${word}_') ||
        lower.endsWith('-$word') ||
        lower.startsWith('$word-') ||
        lower.contains('-$word-')) {
      return true;
    }
    // Match camelCase prefix (e.g. pinCode, keyCode)
    if (lower.startsWith(word) &&
        key.length > word.length &&
        _isAsciiUpper(key[word.length])) {
      return true;
    }
  }
  if (key.endsWith('Pin') ||
      key.endsWith('Key') ||
      key.endsWith('PIN') ||
      key.endsWith('KEY')) {
    return true;
  }
  if (key.contains(_kSensitiveCamelBoundary)) {
    return true;
  }
  return false;
}

/// `tokenExpiresIn` / `token-expires-in` → `token_expires_in`.
String _normalizeKey(String key) => key
    .replaceAllMapped(_kCamelHump, (m) => '${m[1]}_${m[2]}')
    .replaceAll('-', '_')
    .toLowerCase();

bool _isAsciiUpper(String ch) {
  final code = ch.codeUnitAt(0);
  return code >= 65 && code <= 90;
}

/// Extracts the query parameters carried by [routeName]
/// (e.g. `/order?id=1&from=push`) as a sanitized, bounded map.
///
/// Guardrails (shared with [extractArgParams]):
/// - Truncates string values exceeding [maxStringLength] characters (appending `'...'`).
/// - Caps the total number of entries to [maxEntries].
/// - When [redact] is true, masks sensitive parameter keys with [kRedactedValue].
///
/// Returns an unmodifiable map if any parameters were found, or `null` if empty.
Map<String, String>? extractQueryParams({
  String? routeName,
  bool redact = true,
  int maxStringLength = kDefaultMaxRoutingParamStringLength,
  int maxEntries = kDefaultMaxRoutingParamEntries,
}) {
  final raw = routeName != null && routeName.contains('?')
      ? _queryOf(Uri.tryParse(routeName))
      : const <String, String>{};
  return _sanitize(
    raw,
    redact: redact,
    maxStringLength: maxStringLength,
    maxEntries: maxEntries,
  );
}

/// Extracts the parameters carried by route [arguments] as a sanitized,
/// bounded map, kept apart from [extractQueryParams] so the UI can tell
/// which channel a value came through.
///
/// - A [Uri], or a [String] containing `?`, yields its query parameters.
/// - A [Map] yields its scalar entries ([String], [num], [bool], null);
///   any other value is substituted with `'<complex>'`.
///
/// Applies the same guardrails as [extractQueryParams].
Map<String, String>? extractArgParams({
  Object? arguments,
  bool redact = true,
  int maxStringLength = kDefaultMaxRoutingParamStringLength,
  int maxEntries = kDefaultMaxRoutingParamEntries,
}) {
  final raw = switch (arguments) {
    final Uri uri => _queryOf(uri),
    final String s when s.contains('?') => _queryOf(Uri.tryParse(s)),
    final Map map => _scalarEntries(map),
    _ => const <String, String>{},
  };
  return _sanitize(
    raw,
    redact: redact,
    maxStringLength: maxStringLength,
    maxEntries: maxEntries,
  );
}

Map<String, String> _queryOf(Uri? uri) {
  try {
    if (uri != null && uri.hasQuery) return uri.queryParameters;
  } catch (_) {
    // Malformed percent-encoding throws on access; treat as no query.
  }
  return const {};
}

Map<String, String> _scalarEntries(Map map) {
  final raw = <String, String>{};
  try {
    for (final entry in map.entries) {
      if (entry.key == null) continue;
      final val = entry.value;
      raw[entry.key.toString()] =
          val == null || val is String || val is num || val is bool
          ? '$val'
          : '<complex>';
    }
  } catch (_) {
    // Fallback gracefully on custom map errors.
  }
  return raw;
}

Map<String, String>? _sanitize(
  Map<String, String> raw, {
  required bool redact,
  required int maxStringLength,
  required int maxEntries,
}) {
  final sanitized = <String, String>{};
  for (final MapEntry(:key, :value) in raw.entries) {
    if (sanitized.length >= maxEntries) break;
    sanitized[key] = redact && isSensitiveRoutingKey(key)
        ? kRedactedValue
        : value.length > maxStringLength
        ? '${value.substring(0, maxStringLength)}...'
        : value;
  }
  return sanitized.isEmpty ? null : Map<String, String>.unmodifiable(sanitized);
}
