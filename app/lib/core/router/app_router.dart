import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/calendar/presentation/calendar_screen.dart';
import '../../features/collections/presentation/collection_detail_screen.dart';
import '../../features/event_detail/presentation/event_detail_screen.dart';
import '../../features/favorites/presentation/favorites_screen.dart';
import '../../features/follows/presentation/my_follows_screen.dart';
import '../../features/home/presentation/home_screen.dart';
import '../../features/interests/presentation/interests_screen.dart';
import '../../features/map/presentation/map_screen.dart';
import '../../features/notifications/presentation/notification_settings_screen.dart';
import '../../features/onboarding/presentation/onboarding_screen.dart';
import '../../features/planning/presentation/evening_plan_screen.dart';
import '../../features/persons/presentation/ensemble_detail_screen.dart';
import '../../features/persons/presentation/person_detail_screen.dart';
import '../../features/profile/presentation/profile_screen.dart';
import '../../features/search/presentation/search_screen.dart';
import '../../features/venues/presentation/venue_detail_screen.dart';
import '../../features/works/presentation/work_detail_screen.dart';
import '../time/munich_time.dart';
import '../widgets/app_shell.dart';

/// Routing-Baum nach docs/05-navigation-structure.md.
/// Deep-Link-Schema: muc-classical://event/{slug} etc. (§3 im selben Dokument).
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

GoRouter buildAppRouter({String initialLocation = '/home'}) => GoRouter(
  navigatorKey: rootNavigatorKey,
  initialLocation: initialLocation,
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) =>
          AppShell(navigationShell: navigationShell),
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/home',
              builder: (context, state) => const HomeScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/search',
              builder: (context, state) => const SearchScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/map',
              builder: (context, state) => const MapScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/calendar',
              builder: (context, state) => const CalendarScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/profile',
              builder: (context, state) => const ProfileScreen(),
            ),
          ],
        ),
      ],
    ),
    GoRoute(
      path: '/event/:slug',
      name: 'event-detail',
      parentNavigatorKey: rootNavigatorKey,
      builder: (context, state) =>
          EventDetailScreen(slug: state.pathParameters['slug']!),
    ),
    GoRoute(
      path: '/person/:slug',
      parentNavigatorKey: rootNavigatorKey,
      builder: (context, state) =>
          PersonDetailScreen(slug: state.pathParameters['slug']!),
    ),
    GoRoute(
      path: '/ensemble/:slug',
      parentNavigatorKey: rootNavigatorKey,
      builder: (context, state) =>
          EnsembleDetailScreen(slug: state.pathParameters['slug']!),
    ),
    GoRoute(
      path: '/venue/:slug',
      parentNavigatorKey: rootNavigatorKey,
      builder: (context, state) =>
          VenueDetailScreen(slug: state.pathParameters['slug']!),
    ),
    GoRoute(
      path: '/evening-plan',
      parentNavigatorKey: rootNavigatorKey,
      builder: (context, state) {
        final dateParam = state.uri.queryParameters['date'];
        final day = dateParam != null
            ? (DateTime.tryParse(dateParam) ?? MunichTime.now())
            : MunichTime.now();
        return EveningPlanScreen(day: day);
      },
    ),
    GoRoute(
      path: '/collection/:slug',
      parentNavigatorKey: rootNavigatorKey,
      builder: (context, state) =>
          CollectionDetailScreen(slug: state.pathParameters['slug']!),
    ),
    GoRoute(
      path: '/work/:id',
      parentNavigatorKey: rootNavigatorKey,
      builder: (context, state) =>
          WorkDetailScreen(workId: state.pathParameters['id']!),
    ),
    GoRoute(
      path: '/favorites',
      parentNavigatorKey: rootNavigatorKey,
      builder: (context, state) => const FavoritesScreen(),
    ),
    GoRoute(
      path: '/interests',
      parentNavigatorKey: rootNavigatorKey,
      builder: (context, state) => const InterestsScreen(),
    ),
    GoRoute(
      path: '/follows',
      parentNavigatorKey: rootNavigatorKey,
      builder: (context, state) => const MyFollowsScreen(),
    ),
    GoRoute(
      path: '/notification-settings',
      parentNavigatorKey: rootNavigatorKey,
      builder: (context, state) => const NotificationSettingsScreen(),
    ),
    GoRoute(
      path: '/onboarding',
      parentNavigatorKey: rootNavigatorKey,
      builder: (context, state) => const OnboardingScreen(),
    ),
  ],
);
