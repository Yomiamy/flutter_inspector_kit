import 'package:flutter/material.dart';

import '../../../../models/navigator_entry.dart';
import '../../../widgets/detail_section.dart';
import '../../../widgets/json_tree_viewer.dart';
import '../../../theme/theme.dart';

/// A full-screen view of a single [NavigatorEntry]: the destination, then its
/// URL query params, extracted argument params and the (already sanitized)
/// raw arguments, so nested values hidden as `<complex>` stay inspectable.
class NavigatorDetailView extends StatelessWidget {
  const NavigatorDetailView({required this.entry, super.key});

  final NavigatorEntry entry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${entry.action.name} ${entry.displayName}')),
      body: ListView(
        padding: ThemePadding.paddingAll12,
        children: [
          DetailSection(
            title: 'General',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DetailKeyValueRow.text('Action', entry.action.name),
                DetailKeyValueRow.text(
                  'Timestamp',
                  entry.timestamp.toIso8601String(),
                ),
                if (entry.widgetType != null)
                  DetailKeyValueRow.text('Widget', '${entry.widgetType}'),
                if (entry.routeName != null)
                  DetailKeyValueRow.text('Route', entry.routeName!),
              ],
            ),
          ),
          DetailSection(
            title: 'Params (URL query)',
            child: JsonTreeViewer(entry.queryParams, emptyLabel: '(none)'),
          ),
          DetailSection(
            title: 'Args',
            child: JsonTreeViewer(entry.argParams, emptyLabel: '(none)'),
          ),
          DetailSection(
            title: 'Raw Arguments',
            child: JsonTreeViewer(entry.arguments, emptyLabel: '(none)'),
          ),
        ],
      ),
    );
  }
}
