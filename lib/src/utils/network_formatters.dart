import 'dart:convert';

import '../models/network_entry.dart';
import '../models/timestamped_entry.dart';
import 'redaction.dart';

/// Pure formatting helpers for the Network inspector. No Flutter dependencies,
/// so everything here is unit-testable in isolation.

/// The four essentials needed to replay an HTTP request.
///
/// Deliberately free of any Dio / http-client dependency so that this file
/// stays pure-formatting and fully unit-testable.
class ReplayRequest {
  const ReplayRequest({
    required this.method,
    required this.url,
    this.headers,
    this.body,
  });

  /// HTTP method, e.g. `GET`, `POST`.
  final String method;

  /// Full request URL.
  final String url;

  /// Request headers (may be `null` when the original request had none).
  final Map<String, dynamic>? headers;

  /// Request body (may be `null` when the original request had none).
  /// Raw, un-escaped.
  final String? body;
}

/// Extracts the four replay-relevant fields from [entry] without any escaping.
ReplayRequest buildReplayRequest(NetworkEntry entry) {
  return ReplayRequest(
    method: entry.method,
    url: entry.url,
    headers: entry.requestHeaders,
    body: entry.requestBody,
  );
}

/// Formats a byte count into a human-readable string, e.g. `0 B`, `1.2 KB`,
/// `3.4 MB`.
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB', 'TB'];
  var size = bytes / 1024;
  var unitIndex = 0;
  while (size >= 1024 && unitIndex < units.length - 1) {
    size /= 1024;
    unitIndex++;
  }
  return '${size.toStringAsFixed(1)} ${units[unitIndex]}';
}

/// Pretty-prints [body] with two-space indentation when it is valid JSON.
/// Returns [body] unchanged when it is null/empty or not parseable as JSON.
String prettyJson(String? body) {
  if (body == null || body.isEmpty) return body ?? '';
  try {
    final decoded = json.decode(body);
    return const JsonEncoder.withIndent('  ').convert(decoded);
  } on FormatException {
    return body;
  }
}

/// Projects [entry] onto a single dense line for the diagnostic report's
/// `## Timeline` section:
/// `[HH:mm:ss.mmm] [NET] {method} {path} → {status} ({duration}ms)`, or
/// `... {method} {path} ✗ {errorType}` for a transport failure (no status code).
///
/// Deliberately shows only the URL *path* — never the query string — so
/// query-param secrets can't leak into the timeline. The full, redacted
/// request/response stays in the `## Network` detail section.
String buildNetworkOneLiner(NetworkEntry entry) {
  // A malformed URL (Uri.tryParse == null, e.g. an unclosed IPv6 bracket) must
  // not fall back to the raw string — that would drag the query, exactly what
  // this projection exists to hide, into the timeline. Cut the fallback at the
  // first query/fragment separator and flatten newlines instead.
  final path =
      Uri.tryParse(entry.url)?.path ??
      entry.url.split(RegExp(r'[?#]')).first.replaceAll(RegExp(r'[\r\n]'), ' ');
  final b = StringBuffer('[${entry.displayTime}] [NET] ${entry.method} $path ');

  if (entry.statusCode == null && entry.errorType != null) {
    b.write('✗ ${entry.errorType!.name}');
  } else {
    b.write('→ ${entry.statusCode ?? 'N/A'}');
    if (entry.duration != null) {
      b.write(' (${entry.duration!.inMilliseconds}ms)');
    }
  }
  return b.toString();
}

/// Builds an executable `curl` command reproducing [entry]'s request.
///
/// When [redact] is true (the secure default), sensitive request headers
/// (see [redactHeaders]) are masked before serialisation.
String buildCurl(NetworkEntry entry, {bool redact = true}) {
  final req = buildReplayRequest(entry);
  final buffer = StringBuffer('curl');
  buffer.write(" -X ${req.method.toUpperCase()}");

  final headers = redact && req.headers != null
      ? redactHeaders(req.headers!)
      : req.headers;
  if (headers != null) {
    for (final h in headers.entries) {
      final value = h.value?.toString().replaceAll("'", r"'\''") ?? '';
      buffer.write(" -H '${h.key}: $value'");
    }
  }

  final body = req.body;
  if (body != null && body.isNotEmpty) {
    final escaped = body.replaceAll("'", r"'\''");
    buffer.write(" --data '$escaped'");
  }

  final escapedUrl = req.url.replaceAll("'", r"'\''");
  buffer.write(" '$escapedUrl'");
  return buffer.toString();
}

/// Builds a full plain-text export of [entry] covering general info, request,
/// response, and error sections.
///
/// When [redact] is true (the secure default), sensitive request/response
/// headers (see [redactHeaders]) are masked before serialisation.
String buildPlainText(NetworkEntry entry, {bool redact = true}) {
  final b = StringBuffer()
    ..writeln('=== General ===')
    ..writeln('Method: ${entry.method}')
    ..writeln('URL: ${entry.url}')
    ..writeln('Status: ${entry.statusCode ?? 'Pending'}')
    ..writeln('Duration: ${entry.duration?.inMilliseconds ?? '-'} ms')
    ..writeln('Request size: ${formatBytes(entry.requestSizeBytes)}')
    ..writeln('Response size: ${formatBytes(entry.responseSizeBytes)}')
    ..writeln('Timestamp: ${entry.timestamp.toIso8601String()}');

  final query = entry.queryParameters;
  if (query.isNotEmpty) {
    b.writeln('\n=== Query Parameters ===');
    query.forEach((k, v) => b.writeln('$k: $v'));
  }

  b.writeln('\n=== Request Headers ===');
  _writeHeaders(b, entry.requestHeaders, redact: redact);
  if (entry.requestBody != null && entry.requestBody!.isNotEmpty) {
    b
      ..writeln('\n=== Request Body ===')
      ..writeln(
        entry.isRequestJson ? prettyJson(entry.requestBody) : entry.requestBody,
      );
  }

  b.writeln('\n=== Response Headers ===');
  _writeHeaders(b, entry.responseHeaders, redact: redact);
  if (entry.responseBody != null && entry.responseBody!.isNotEmpty) {
    b
      ..writeln('\n=== Response Body ===')
      ..writeln(
        entry.isResponseJson
            ? prettyJson(entry.responseBody)
            : entry.responseBody,
      );
  }

  if (entry.error != null || entry.errorType != null) {
    b.writeln('\n=== Error ===');
    if (entry.errorType != null) {
      b.writeln('Error Type: ${entry.errorType!.name}');
    }
    if (entry.error != null) {
      b.writeln(entry.error);
    }
  }
  final st = entry.errorStackTrace;
  if (st != null && st.isNotEmpty) {
    b
      ..writeln('\n=== Stack Trace ===')
      ..writeln(st);
  }

  return b.toString().trimRight();
}

void _writeHeaders(
  StringBuffer b,
  Map<String, dynamic>? headers, {
  bool redact = true,
}) {
  if (headers == null || headers.isEmpty) {
    b.writeln('(none)');
    return;
  }
  final shown = redact ? redactHeaders(headers) : headers;
  shown.forEach((k, v) => b.writeln('$k: $v'));
}
