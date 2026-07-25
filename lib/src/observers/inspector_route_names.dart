import 'package:flutter/material.dart';

// Route names for the inspector's own UI. The observer filters on this
// prefix so inspector navigation never lands in the host app's Navigator
// history. Producers (dashboard UI) and the consumer (the observer) must
// share this one definition — a second copy is how the original bug happened.

/// Prefix every inspector-owned route name starts with.
///
/// Deliberately verbose and package-qualified: it must not collide with a
/// host app's own route names, which are typically path-like (`/home`) or
/// short identifiers. `startsWith` on this prefix is the whole filter.
const String kInspectorRoutePrefix = 'flutter_inspector_';

/// The dashboard modal itself.
///
/// The value is frozen: it shipped on pub.dev and users may already filter
/// on this exact string in their own NavigatorObserver.
const String kInspectorDashboardRoute = 'flutter_inspector_dashboard';

/// The log detail page, opened from a Console row.
const String kInspectorLogDetailRoute = 'flutter_inspector_log_detail';

/// The network detail page, opened from either the Console or Network tab.
const String kInspectorNetworkDetailRoute = 'flutter_inspector_network_detail';

/// The table rows page, opened from a Database tab table.
const String kInspectorTableRowsRoute = 'flutter_inspector_table_rows';

/// The cell details bottom sheet, opened from a table row.
const String kInspectorCellDetailsRoute = 'flutter_inspector_cell_details';

/// The diagnostic report export bottom sheet.
const String kInspectorExportReportRoute = 'flutter_inspector_export_report';

/// Pushes an inspector-owned page route, tagged so the navigator observer
/// can keep it out of the host app's navigation history.
///
/// Every page route opened from inside the dashboard must go through here.
/// [name] must start with [kInspectorRoutePrefix]; a stray name would
/// silently become the next pollution source, so it fails loudly in debug.
void pushInspectorRoute(
  BuildContext context,
  String name,
  WidgetBuilder builder,
) {
  assert(
    name.startsWith(kInspectorRoutePrefix),
    'Inspector route name "$name" must start with '
    '"$kInspectorRoutePrefix" or the navigator observer will leak it into '
    'the host app history.',
  );
  Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      settings: RouteSettings(name: name),
      builder: builder,
    ),
  );
}
