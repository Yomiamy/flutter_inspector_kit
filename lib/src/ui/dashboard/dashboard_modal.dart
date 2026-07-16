import 'package:flutter/material.dart';

import '../../core/flutter_inspector.dart';
import 'export_report_sheet.dart';
import 'tabs/console_tab.dart';
import 'tabs/database_tab.dart';
import 'tabs/navigator_tab.dart';
import 'tabs/network_tab.dart';

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
      routeSettings: const RouteSettings(name: 'flutter_inspector_dashboard'),
      pageBuilder: (context, animation, secondaryAnimation) {
        return DashboardModal(inspector: inspector, initialIndex: initialIndex);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasCustomTab = inspector.customTab != null;
    final tabCount = hasCustomTab ? 5 : 4;

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
            if (hasCustomTab) inspector.customTab!,
          ],
        ),
      ),
    );
  }
}

class _DashboardTabBar extends StatelessWidget {
  const _DashboardTabBar({required this.hasCustomTab, this.customTabTitle});

  final bool hasCustomTab;
  final String? customTabTitle;

  @override
  Widget build(BuildContext context) {
    return TabBar(
      isScrollable: true,
      tabAlignment: TabAlignment.start,
      tabs: [
        const Tab(text: 'Console'),
        const Tab(text: 'Network'),
        const Tab(text: 'Navigator'),
        const Tab(text: 'Database'),
        if (hasCustomTab) Tab(text: customTabTitle ?? 'Custom'),
      ],
    );
  }
}
