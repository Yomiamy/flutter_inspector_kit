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

const String kInspectorLogDetailRoute = 'flutter_inspector_log_detail';
const String kInspectorNetworkDetailRoute = 'flutter_inspector_network_detail';
const String kInspectorTableRowsRoute = 'flutter_inspector_table_rows';
const String kInspectorCellDetailsRoute = 'flutter_inspector_cell_details';
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
