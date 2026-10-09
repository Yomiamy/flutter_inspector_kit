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

const Set<String> _kSensitiveWords = {
  'pin',
  'key',
};

/// Returns true if [key] is recognized as containing sensitive data.
bool isSensitiveRoutingKey(String key) {
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
  }
  if (key.endsWith('Pin') || key.endsWith('Key')) {
    return true;
  }
  return false;
}

/// Extracts a sanitized, bounded map of scalar routing parameters from
/// [routeName] and [arguments].
///
/// Features:
/// 1. Query parameters extraction:
///    - If [routeName] contains `?`, parses it as a URI and extracts query parameters.
///    - If [arguments] is a [Uri], extracts its query parameters.
///    - If [arguments] is a [String] containing `?`, attempts to parse as URI and extract query parameters.
/// 2. Scalar arguments extraction:
///    - If [arguments] is a [Map], extracts entries with primitive values ([String], [num], [bool]).
///    - Non-primitive or complex objects are substituted with `'<complex>'`.
/// 3. Guardrails:
///    - Truncates string values exceeding [maxStringLength] characters (appending `'...'`).
///    - Caps the total number of entries to [maxEntries].
///    - When [redact] is true, masks sensitive parameter keys with [kRedactedValue].
///
/// Returns an unmodifiable map if any parameters were found, or `null` if empty.
Map<String, String>? extractRoutingParams({
  String? routeName,
  Object? arguments,
  bool redact = true,
  int maxStringLength = kDefaultMaxRoutingParamStringLength,
  int maxEntries = kDefaultMaxRoutingParamEntries,
}) {
  final rawMap = <String, String>{};

  // 1. Extract from routeName if it contains query parameters.
  if (routeName != null && routeName.contains('?')) {
    try {
      final uri = Uri.tryParse(routeName);
      if (uri != null && uri.hasQuery) {
        rawMap.addAll(uri.queryParameters);
      }
    } catch (_) {
      // Ignore malformed URI queries gracefully.
    }
  }

  // 2. Extract from arguments.
  if (arguments != null) {
    if (arguments is Uri) {
      try {
        if (arguments.hasQuery) {
          rawMap.addAll(arguments.queryParameters);
        }
      } catch (_) {}
    } else if (arguments is String && arguments.contains('?')) {
      try {
        final uri = Uri.tryParse(arguments);
        if (uri != null && uri.hasQuery) {
          rawMap.addAll(uri.queryParameters);
        }
      } catch (_) {}
    } else if (arguments is Map) {
      try {
        for (final entry in arguments.entries) {
          if (entry.key == null) continue;
          final key = entry.key.toString();
          final val = entry.value;
          if (val == null) {
            rawMap[key] = 'null';
          } else if (val is String || val is num || val is bool) {
            rawMap[key] = val.toString();
          } else {
            rawMap[key] = '<complex>';
          }
        }
      } catch (_) {
        // Fallback gracefully on custom map errors.
      }
    }
  }

  if (rawMap.isEmpty) return null;

  // 3. Apply capping, truncation, and redaction.
  final sanitized = <String, String>{};
  for (final entry in rawMap.entries) {
    if (sanitized.length >= maxEntries) break;

    final key = entry.key;
    var value = entry.value;

    if (redact && isSensitiveRoutingKey(key)) {
      value = kRedactedValue;
    } else if (value.length > maxStringLength) {
      value = '${value.substring(0, maxStringLength)}...';
    }

    sanitized[key] = value;
  }

  if (sanitized.isEmpty) return null;
  return Map<String, String>.unmodifiable(sanitized);
}

/// Strips query parameters from [routeName] when [redact] is true.
String? redactRouteQuery(String? routeName, {required bool redact}) {
  if (!redact || routeName == null) return routeName;
  final queryStart = routeName.indexOf('?');
  return queryStart < 0 ? routeName : routeName.substring(0, queryStart);
}

/// Redacts sensitive entries from route arguments if [arguments] is a Map.
/// When [redact] is false or arguments is not a Map, returns [arguments] as-is.
Object? redactRoutingArguments(Object? arguments, {required bool redact}) {
  if (!redact || arguments == null) return arguments;
  if (arguments is Map) {
    return {
      for (final entry in arguments.entries)
        entry.key: (entry.key != null && isSensitiveRoutingKey(entry.key.toString()))
            ? kRedactedValue
            : entry.value,
    };
  }
  return arguments;
}

