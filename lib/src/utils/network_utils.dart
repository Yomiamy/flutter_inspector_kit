import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../models/network_entry.dart';
/// Formats [t] as a zero-padded `HH:mm:ss` local-time string.
String timeOf(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:'
    '${t.minute.toString().padLeft(2, '0')}:'
    '${t.second.toString().padLeft(2, '0')}';

/// HTTP methods offered as quick filter chips in the Network tab.
const List<String> httpMethods = ['GET', 'POST', 'PUT', 'PATCH', 'DELETE'];

/// Chip labels for each [NetworkStatusGroup] shown in the Network tab.
const Map<NetworkStatusGroup, String> statusLabels = {
  NetworkStatusGroup.success: '2xx',
  NetworkStatusGroup.redirect: '3xx',
  NetworkStatusGroup.clientError: '4xx',
  NetworkStatusGroup.serverError: '5xx',
  NetworkStatusGroup.failed: 'Failed',
};

/// Status-code ranges used for quick filtering in the Network tab.
enum NetworkStatusGroup {
  /// 1xx informational.
  informational,

  /// 2xx success.
  success,

  /// 3xx redirection.
  redirect,

  /// 4xx client error.
  clientError,

  /// 5xx server error.
  serverError,

  /// Failed requests (transport error, no status code).
  failed;

  /// Whether [statusCode]/[hasError] falls into this group.
  bool matches(int? statusCode, bool hasError) {
    switch (this) {
      case NetworkStatusGroup.failed:
        return hasError && (statusCode == null);
      case NetworkStatusGroup.informational:
        return statusCode != null && statusCode >= 100 && statusCode < 200;
      case NetworkStatusGroup.success:
        return statusCode != null && statusCode >= 200 && statusCode < 300;
      case NetworkStatusGroup.redirect:
        return statusCode != null && statusCode >= 300 && statusCode < 400;
      case NetworkStatusGroup.clientError:
        return statusCode != null && statusCode >= 400 && statusCode < 500;
      case NetworkStatusGroup.serverError:
        return statusCode != null && statusCode >= 500 && statusCode < 600;
    }
  }
}

/// An immutable filter for the Network tab: a case-insensitive [keyword] plus
/// optional method and status-group constraints.
class NetworkFilter {
  /// Creates a filter. An empty/blank [keyword] and empty sets match everything.
  const NetworkFilter({
    this.keyword = '',
    this.methods = const <String>{},
    this.statusGroups = const <NetworkStatusGroup>{},
  });

  /// Substring matched against url, method, and status code (case-insensitive).
  final String keyword;

  /// HTTP methods to include. Empty means "all methods".
  final Set<String> methods;

  /// Status groups to include. Empty means "all statuses".
  final Set<NetworkStatusGroup> statusGroups;

  /// Whether this filter would match every entry (no active constraints).
  bool get isEmpty =>
      keyword.trim().isEmpty && methods.isEmpty && statusGroups.isEmpty;

  /// Returns whether [entry] satisfies all active constraints.
  bool matches(NetworkEntry entry) {
    if (methods.isNotEmpty &&
        !methods.any((m) => m.toUpperCase() == entry.method.toUpperCase())) {
      return false;
    }

    if (statusGroups.isNotEmpty &&
        !statusGroups.any(
          (g) => g.matches(entry.statusCode, entry.error != null),
        )) {
      return false;
    }

    final kw = keyword.trim().toLowerCase();
    if (kw.isEmpty) return true;

    return entry.url.toLowerCase().contains(kw) ||
        entry.method.toLowerCase().contains(kw) ||
        (entry.statusCode?.toString().contains(kw) ?? false);
  }
}

/// Returns the subset of [entries] satisfying [filter], preserving order.
List<NetworkEntry> applyNetworkFilter(
  List<NetworkEntry> entries,
  NetworkFilter filter,
) {
  if (filter.isEmpty) return entries;
  return entries.where(filter.matches).toList(growable: false);
}

/// An aggregated group of network errors sharing the same
/// [statusCode] and [errorType].
@immutable
class NetworkErrorGroup {
  const NetworkErrorGroup({
    required this.statusCode,
    required this.errorType,
    required this.count,
    required this.firstSeen,
    required this.lastSeen,
    required this.label,
  });

  /// HTTP status code (null for transport-layer failures).
  final int? statusCode;

  /// Dio error classification (null for server-error responses).
  final DioExceptionType? errorType;

  /// Number of matching entries in the buffer.
  final int count;

  /// Timestamp of the earliest matching entry.
  final DateTime firstSeen;

  /// Timestamp of the most recent matching entry.
  final DateTime lastSeen;

  /// Human-readable label (e.g. "502 Bad Gateway", "Connection Timeout").
  final String label;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NetworkErrorGroup &&
          statusCode == other.statusCode &&
          errorType == other.errorType;

  @override
  int get hashCode => Object.hash(statusCode, errorType);
}

/// Returns a human-readable label for a [DioExceptionType].
String errorTypeLabel(DioExceptionType type) {
  return switch (type) {
    DioExceptionType.connectionTimeout => 'Connection Timeout',
    DioExceptionType.sendTimeout => 'Send Timeout',
    DioExceptionType.receiveTimeout => 'Receive Timeout',
    DioExceptionType.badCertificate => 'Bad Certificate',
    DioExceptionType.badResponse => 'Bad Response',
    DioExceptionType.cancel => 'Cancelled',
    DioExceptionType.connectionError => 'Connection Error',
    DioExceptionType.unknown => 'Unknown Error',
    _ => 'Other Error',
  };
}

/// Groups error entries by (statusCode, errorType), returning
/// groups sorted by count descending.
List<NetworkErrorGroup> aggregateNetworkErrors(List<NetworkEntry> entries) {
  final Map<String, _ErrorGroupBuilder> builders = {};

  for (final entry in entries) {
    // 1. Filter out error entries: error != null OR statusCode >= 400
    final isError = entry.error != null || (entry.statusCode != null && entry.statusCode! >= 400);
    if (!isError) continue;

    // 2. Group by (statusCode, errorType)
    final String key = '${entry.statusCode}_${entry.errorType}';
    final builder = builders.putIfAbsent(key, () => _ErrorGroupBuilder(
      statusCode: entry.statusCode,
      errorType: entry.errorType,
    ));

    builder.count++;
    if (builder.firstSeen == null || entry.timestamp.isBefore(builder.firstSeen!)) {
      builder.firstSeen = entry.timestamp;
    }
    if (builder.lastSeen == null || entry.timestamp.isAfter(builder.lastSeen!)) {
      builder.lastSeen = entry.timestamp;
    }
  }

  // 3 & 4. Build groups and sort descending by count
  final groups = builders.values.map((b) => b.build()).toList();
  groups.sort((a, b) => b.count.compareTo(a.count));

  return groups;
}

class _ErrorGroupBuilder {
  _ErrorGroupBuilder({
    this.statusCode,
    this.errorType,
  });

  final int? statusCode;
  final DioExceptionType? errorType;
  
  int count = 0;
  DateTime? firstSeen;
  DateTime? lastSeen;

  NetworkErrorGroup build() {
    String label;
    if (statusCode != null) {
      label = statusCode.toString();
    } else if (errorType != null) {
      label = errorTypeLabel(errorType!);
    } else {
      label = 'Unknown Error';
    }

    return NetworkErrorGroup(
      statusCode: statusCode,
      errorType: errorType,
      count: count,
      firstSeen: firstSeen!,
      lastSeen: lastSeen!,
      label: label,
    );
  }
}
