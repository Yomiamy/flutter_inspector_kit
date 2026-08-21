import 'package:flutter/material.dart';

import '../../core/flutter_inspector.dart';
import '../../models/log_level.dart';
import '../../observers/inspector_route_names.dart';
import 'export_report_sheet.dart';
import 'tabs/console_tab.dart';
import 'tabs/database_tab.dart';
import 'tabs/navigator_tab.dart';
import 'tabs/network_tab.dart';
import 'tabs/storage_tab.dart';

/// The full-screen modal container for the inspector dashboard.
class DashboardModal extends StatelessWidget {
  const DashboardModal({
    required this.inspector,
    this.initialIndex = 0,
    super.key,
  });

  final FlutterInspector inspector;

  /// The tab selected when the dashboard opens. Console (0), Network (1),
  /// Navigator (2), Database (3).
  final int initialIndex;

  /// Displays the dashboard modal.
  static void show(
    BuildContext context,
    FlutterInspector inspector, {
    int initialIndex = 0,
  }) {
    showGeneralDialog(
      context: context,
      routeSettings: const RouteSettings(name: kInspectorDashboardRoute),
      pageBuilder: (context, animation, secondaryAnimation) {
        return DashboardModal(inspector: inspector, initialIndex: initialIndex);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasCustomTab = inspector.customTab != null;
    // Storage is opt-in: without a registered source the tab would be empty.
    final hasStorageTab = inspector.keyValueSources.isNotEmpty;
    final tabCount = 4 + (hasStorageTab ? 1 : 0) + (hasCustomTab ? 1 : 0);

    return DefaultTabController(
      length: tabCount,
      initialIndex: initialIndex.clamp(0, tabCount - 1),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Flutter Inspector'),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.ios_share),
              tooltip: 'Export diagnostic report',
              onPressed: () => ExportReportSheet.show(context, inspector),
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(kTextTabBarHeight),
            child: _DashboardTabBar(
              inspector: inspector,
              hasStorageTab: hasStorageTab,
              hasCustomTab: hasCustomTab,
              customTabTitle: inspector.customTabTitle,
            ),
          ),
        ),
        body: TabBarView(
          children: [
            ConsoleTab(inspector: inspector),
            NetworkTab(inspector: inspector),
            NavigatorTab(inspector: inspector),
            DatabaseTab(inspector: inspector),
            // Keep this list in the same order as the tabs above.
            if (hasStorageTab) StorageTab(inspector: inspector),
            if (hasCustomTab) inspector.customTab!,
          ],
        ),
      ),
    );
  }
}

/// The dashboard's TabBar. Subscribes to [FlutterInspector.registry]'s
/// revision notifier so the Console/Network error badges update live while
/// the dashboard is open.
///
/// This is the *only* reactive piece of the dashboard: each tab's own list
/// still refreshes manually (see the tab widgets' refresh buttons). That
/// split is intentional — a list mid-scroll must not be reflowed underneath
/// the user, but a summary badge should never lie. Do not extend this
/// notifier to drive tab list rebuilds.
class _DashboardTabBar extends StatefulWidget {
  const _DashboardTabBar({
    required this.inspector,
    required this.hasStorageTab,
    required this.hasCustomTab,
    this.customTabTitle,
  });

  final FlutterInspector inspector;
  final bool hasStorageTab;
  final bool hasCustomTab;
  final String? customTabTitle;

  @override
  State<_DashboardTabBar> createState() => _DashboardTabBarState();
}

class _DashboardTabBarState extends State<_DashboardTabBar> {
  @override
  void initState() {
    super.initState();
    // FlutterInspector.registry is @visibleForTesting because it exposes the
    // full InspectorRegistry surface; revision itself is intentionally not
    // public API (see feature spec). This is the one non-test call site.
    // ignore: invalid_use_of_visible_for_testing_member
    widget.inspector.registry.revision.addListener(_onRevisionChanged);
  }

  @override
  void didUpdateWidget(covariant _DashboardTabBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.inspector == oldWidget.inspector) return;
    // ignore: invalid_use_of_visible_for_testing_member
    oldWidget.inspector.registry.revision.removeListener(_onRevisionChanged);
    // ignore: invalid_use_of_visible_for_testing_member
    widget.inspector.registry.revision.addListener(_onRevisionChanged);
  }

  @override
  void dispose() {
    // ignore: invalid_use_of_visible_for_testing_member
    widget.inspector.registry.revision.removeListener(_onRevisionChanged);
    super.dispose();
  }

  void _onRevisionChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    // Network count must reuse NetworkEntry.isFailed — the single source of
    // truth for "did this call fail" shared with the error-summary banner,
    // the console timeline and the diagnostic report.
    final networkErrorCount = widget.inspector.networkEntries
        .where((e) => e.isFailed)
        .length;
    // Console counts only log-level error/warning, not failed network calls
    // surfaced in the merged timeline — those are already counted by the
    // Network badge, and double-counting would make the two numbers lie.
    final consoleErrorCount =
        widget.inspector.logInspector.entriesAtLevel(LogLevel.error).length +
        widget.inspector.logInspector.entriesAtLevel(LogLevel.warning).length;

    return TabBar(
      isScrollable: true,
      tabAlignment: TabAlignment.start,
      tabs: [
        Tab(
          child: _BadgeTabLabel(count: consoleErrorCount, label: 'Console'),
        ),
        Tab(
          child: _BadgeTabLabel(count: networkErrorCount, label: 'Network'),
        ),
        const Tab(text: 'Navigator'),
        const Tab(text: 'Database'),
        // Keep this list in the same order as TabBarView's children.
        if (widget.hasStorageTab) const Tab(text: 'Storage'),
        if (widget.hasCustomTab) Tab(text: widget.customTabTitle ?? 'Custom'),
      ],
    );
  }
}

/// A tab label with an error-count badge, hidden when [count] is zero.
class _BadgeTabLabel extends StatelessWidget {
  const _BadgeTabLabel({required this.count, required this.label});

  final int count;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Badge(
      isLabelVisible: count > 0,
      label: Text('$count'),
      child: Text(label),
    );
  }
}
