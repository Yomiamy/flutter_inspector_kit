import '../models/network_entry.dart';

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
