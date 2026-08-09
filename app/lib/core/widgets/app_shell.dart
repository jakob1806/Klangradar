import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/generated/app_localizations.dart';
import 'liquid_glass/liquid_glass_navigation_bar.dart';

/// Root-Tab-Shell — hält den Navigation-State pro Tab (siehe
/// docs/05-navigation-structure.md, §1: 5 Tabs, Favoriten bewusst kein
/// eigener Tab, sondern über Profil erreichbar).
class AppShell extends StatelessWidget {
  const AppShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final destinations = [
      LiquidGlassNavDestination(
        label: l10n.navHome,
        icon: Icons.home_outlined,
        selectedIcon: Icons.home_rounded,
      ),
      LiquidGlassNavDestination(
        label: l10n.navSearch,
        icon: Icons.search_outlined,
        selectedIcon: Icons.search_rounded,
      ),
      LiquidGlassNavDestination(
        label: l10n.navMap,
        icon: Icons.map_outlined,
        selectedIcon: Icons.map_rounded,
      ),
      LiquidGlassNavDestination(
        label: l10n.navCalendar,
        icon: Icons.calendar_month_outlined,
        selectedIcon: Icons.calendar_month_rounded,
      ),
      LiquidGlassNavDestination(
        label: l10n.navProfile,
        icon: Icons.person_outline_rounded,
        selectedIcon: Icons.person_rounded,
      ),
    ];

    return Scaffold(
      extendBody: true,
      body: navigationShell,
      bottomNavigationBar: LiquidGlassNavigationBar(
        destinations: destinations,
        selectedIndex: navigationShell.currentIndex,
        onSelected: (index) => navigationShell.goBranch(
          index,
          initialLocation: index == navigationShell.currentIndex,
        ),
      ),
    );
  }
}
