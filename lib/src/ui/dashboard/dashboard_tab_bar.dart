import 'package:flutter/material.dart';

/// The TabBar used inside the Dashboard.
class DashboardTabBar extends StatelessWidget {
  const DashboardTabBar({
    required this.hasCustomTab,
    this.customTabTitle,
    super.key,
  });

  final bool hasCustomTab;
  final String? customTabTitle;

  @override
  Widget build(BuildContext context) {
    return TabBar(
      isScrollable: true,
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
