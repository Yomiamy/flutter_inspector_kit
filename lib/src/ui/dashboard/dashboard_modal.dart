import 'package:flutter/material.dart';

import '../../core/flutter_inspector_impl.dart';
import 'dashboard_tab_bar.dart';
import 'tabs/console_tab.dart';
import 'tabs/database_tab.dart';
import 'tabs/navigator_tab.dart';
import 'tabs/network_tab.dart';

/// The full-screen modal container for the inspector dashboard.
class DashboardModal extends StatelessWidget {
  const DashboardModal({
    required this.inspector,
    super.key,
  });

  final FlutterInspector inspector;

  /// Displays the dashboard modal.
  static void show(BuildContext context, FlutterInspector inspector) {
    showGeneralDialog(
      context: context,
      pageBuilder: (context, animation, secondaryAnimation) {
        return DashboardModal(inspector: inspector);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasCustomTab = inspector.customTab != null;
    final tabCount = hasCustomTab ? 5 : 4;

    return DefaultTabController(
      length: tabCount,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Flutter Inspector'),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(kTextTabBarHeight),
            child: DashboardTabBar(
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
