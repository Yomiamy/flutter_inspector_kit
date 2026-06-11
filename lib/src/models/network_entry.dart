import 'dart:convert';

import 'package:flutter/foundation.dart';

/// Maximum number of bytes (characters) retained for a request/response body
/// before truncation. Bodies larger than this are cut and marked.
const int kNetworkBodyMaxLength = 10 * 1024;

/// Marker appended to a body that has been truncated.
const String kTruncatedMarker = '...[truncated]';

/// An immutable record of an HTTP request/response, displayed in the Network
/// tab.
///
/// An entry starts incomplete ([isComplete] == false) when only the request is
/// known, and is later replaced by a completed entry once the response or error
/// arrives.
@immutable
class NetworkEntry {
  /// Creates a network entry. [timestamp] defaults to the moment of creation.
  NetworkEntry({
    required this.method,
    required this.url,
    this.statusCode,
    this.duration,
    this.requestHeaders,
    this.requestBody,
    this.responseHeaders,
    this.responseBody,
    this.error,
    this.isComplete = false,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  /// When the request started.
  final DateTime timestamp;

  /// HTTP method, e.g. `GET`, `POST`.
  final String method;

  /// Full request URL.
  final String url;

  /// HTTP status code of the response, if received.
  final int? statusCode;

  /// Round-trip duration, if the request has completed.
  final Duration? duration;

  /// Request headers.
  final Map<String, dynamic>? requestHeaders;

  /// Request body (already truncated to [kNetworkBodyMaxLength]).
  final String? requestBody;

  /// Response headers.
  final Map<String, dynamic>? responseHeaders;

  /// Response body (already truncated to [kNetworkBodyMaxLength]).
  final String? responseBody;

  /// Error message if the request failed.
  final String? error;

  /// Whether the response or error has been recorded.
  final bool isComplete;

  /// Truncates [body] to [kNetworkBodyMaxLength] characters, appending
  /// [kTruncatedMarker] when truncation occurs. Returns `null` for `null` input.
  static String? truncateBody(String? body) {
    if (body == null) return null;
    if (body.length <= kNetworkBodyMaxLength) return body;
    return body.substring(0, kNetworkBodyMaxLength) + kTruncatedMarker;
  }

  /// Returns a copy of this entry with the given fields replaced.
  NetworkEntry copyWith({
    DateTime? timestamp,
    String? method,
    String? url,
    int? statusCode,
    Duration? duration,
    Map<String, dynamic>? requestHeaders,
    String? requestBody,
    Map<String, dynamic>? responseHeaders,
    String? responseBody,
    String? error,
    bool? isComplete,
  }) {
    return NetworkEntry(
      timestamp: timestamp ?? this.timestamp,
      method: method ?? this.method,
      url: url ?? this.url,
      statusCode: statusCode ?? this.statusCode,
      duration: duration ?? this.duration,
      requestHeaders: requestHeaders ?? this.requestHeaders,
      requestBody: requestBody ?? this.requestBody,
      responseHeaders: responseHeaders ?? this.responseHeaders,
      responseBody: responseBody ?? this.responseBody,
      error: error ?? this.error,
      isComplete: isComplete ?? this.isComplete,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is NetworkEntry &&
        other.timestamp == timestamp &&
        other.method == method &&
        other.url == url &&
        other.statusCode == statusCode &&
        other.duration == duration &&
        mapEquals(other.requestHeaders, requestHeaders) &&
        other.requestBody == requestBody &&
        mapEquals(other.responseHeaders, responseHeaders) &&
        other.responseBody == responseBody &&
        other.error == error &&
        other.isComplete == isComplete;
  }

  @override
  int get hashCode => Object.hash(
    timestamp,
    method,
    url,
    statusCode,
    duration,
    requestBody,
    responseBody,
    error,
    isComplete,
  );

  /// Number of UTF-8 bytes in the (possibly truncated) request body.
  int get requestSizeBytes =>
      requestBody == null ? 0 : utf8.encode(requestBody!).length;

  /// Number of UTF-8 bytes in the (possibly truncated) response body.
  int get responseSizeBytes =>
      responseBody == null ? 0 : utf8.encode(responseBody!).length;

  /// Query parameters parsed from [url]. Empty when the URL has none.
  Map<String, String> get queryParameters {
    final parsed = Uri.tryParse(url);
    return parsed?.queryParameters ?? const <String, String>{};
  }

  /// The request `content-type` header value, if present (case-insensitive).
  String? get requestContentType =>
      _headerValue(requestHeaders, 'content-type');

  /// The response `content-type` header value, if present (case-insensitive).
  String? get responseContentType =>
      _headerValue(responseHeaders, 'content-type');

  /// Whether the request body looks like JSON.
  bool get isRequestJson => _looksLikeJson(requestBody, requestContentType);

  /// Whether the response body looks like JSON.
  bool get isResponseJson => _looksLikeJson(responseBody, responseContentType);

  /// Whether either body was truncated to fit [kNetworkBodyMaxLength].
  bool get isTruncated =>
      (requestBody?.endsWith(kTruncatedMarker) ?? false) ||
      (responseBody?.endsWith(kTruncatedMarker) ?? false);

  static String? _headerValue(Map<String, dynamic>? headers, String name) {
    if (headers == null) return null;
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == name) return entry.value?.toString();
    }
    return null;
  }

  static bool _looksLikeJson(String? body, String? contentType) {
    if (body == null || body.isEmpty) return false;
    if (contentType != null && contentType.toLowerCase().contains('json')) {
      return true;
    }
    final trimmed = body.trimLeft();
    return trimmed.startsWith('{') || trimmed.startsWith('[');
  }

  @override
  String toString() =>
      'NetworkEntry($method $url, status: $statusCode, complete: $isComplete)';
}
