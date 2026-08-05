import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/generated/app_localizations.dart';

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
      _TabDestination(
        label: l10n.navHome,
        icon: Icons.home_rounded,
        outlineIcon: Icons.home_outlined,
      ),
      _TabDestination(
        label: l10n.navSearch,
        icon: Icons.search_rounded,
        outlineIcon: Icons.search_outlined,
      ),
      _TabDestination(
        label: l10n.navMap,
        icon: Icons.map_rounded,
        outlineIcon: Icons.map_outlined,
      ),
      _TabDestination(
        label: l10n.navCalendar,
        icon: Icons.calendar_month_rounded,
        outlineIcon: Icons.calendar_month_outlined,
      ),
      _TabDestination(
        label: l10n.navProfile,
        icon: Icons.person_rounded,
        outlineIcon: Icons.person_outline_rounded,
      ),
    ];

    return Scaffold(
      extendBody: true,
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: (index) => navigationShell.goBranch(
          index,
          initialLocation: index == navigationShell.currentIndex,
        ),
        destinations: [
          for (final d in destinations)
            NavigationDestination(
              icon: Icon(d.outlineIcon),
              selectedIcon: Icon(d.icon),
              label: d.label,
            ),
        ],
      ),
    );
  }
}

class _TabDestination {
  const _TabDestination({
    required this.label,
    required this.icon,
    required this.outlineIcon,
  });

  final String label;
  final IconData icon;
  final IconData outlineIcon;
}
