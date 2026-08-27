package de.klangradar.android.ui.navigation

import android.net.Uri
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.navigation.NavController
import androidx.navigation.NavDestination.Companion.hierarchy
import androidx.navigation.NavGraph.Companion.findStartDestination
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import de.klangradar.android.KlangradarApp
import de.klangradar.android.domain.model.EntityKind
import de.klangradar.android.ui.calendar.CalendarScreen
import de.klangradar.android.ui.entity.EntityDetailScreen
import de.klangradar.android.ui.favorites.FavoritesScreen
import de.klangradar.android.ui.follows.FollowsScreen
import de.klangradar.android.ui.home.HomeScreen
import de.klangradar.android.ui.interests.InterestsScreen
import de.klangradar.android.ui.map.MapScreen
import de.klangradar.android.ui.profile.ProfileScreen
import de.klangradar.android.ui.search.SearchScreen

private const val ENTITY_ROUTE = "entity/{kind}/{identifier}"

/** Navigates to an entity's detail page — `identifier` is a slug (or id
 *  when no slug exists), URL-encoded since it can end up in a path
 *  segment. Shared by Suche, Follows, and the entity detail screen itself
 *  (composer/parent-ensemble links etc.). */
fun NavController.navigateToEntity(kind: EntityKind, identifier: String) {
    navigate("entity/${kind.apiValue}/${Uri.encode(identifier)}")
}

/** Root Scaffold: bottom [NavigationBar] with real Material3 components +
 *  a [NavHost] — the Android/Compose equivalent of ios-native's
 *  RootTabView's SwiftUI TabView. */
@Composable
fun RootScaffold(app: KlangradarApp) {
    val navController = rememberNavController()

    Scaffold(
        bottomBar = {
            NavigationBar {
                val backStackEntry by navController.currentBackStackEntryAsState()
                val currentDestination = backStackEntry?.destination
                AppTab.entries.forEach { tab ->
                    val selected = currentDestination?.hierarchy?.any { it.route == tab.route } == true
                    NavigationBarItem(
                        selected = selected,
                        onClick = {
                            navController.navigate(tab.route) {
                                popUpTo(navController.graph.findStartDestination().id) { saveState = true }
                                launchSingleTop = true
                                restoreState = true
                            }
                        },
                        icon = { Icon(tab.icon, contentDescription = tab.label) },
                        label = { Text(tab.label) }
                    )
                }
            }
        }
    ) { innerPadding ->
        NavHost(
            navController = navController,
            startDestination = AppTab.Home.route,
            modifier = androidx.compose.ui.Modifier.padding(innerPadding)
        ) {
            composable(AppTab.Home.route) { HomeScreen(app) }
            composable(AppTab.Search.route) { SearchScreen(app, onSelect = { kind, identifier -> navController.navigateToEntity(kind, identifier) }) }
            composable(AppTab.Map.route) {
                MapScreen(app, onSelectVenue = { identifier -> navController.navigateToEntity(EntityKind.VENUE, identifier) })
            }
            composable(AppTab.Calendar.route) { CalendarScreen(app) }
            composable(AppTab.Profile.route) {
                ProfileScreen(
                    app,
                    onOpenFavorites = { navController.navigate("favorites") },
                    onOpenFollows = { navController.navigate("follows") },
                    onOpenInterests = { navController.navigate("interests") }
                )
            }
            composable("favorites") { FavoritesScreen(app, onBack = { navController.popBackStack() }) }
            composable("follows") {
                FollowsScreen(
                    app,
                    onBack = { navController.popBackStack() },
                    onSelect = { kind, identifier -> navController.navigateToEntity(kind, identifier) }
                )
            }
            composable("interests") { InterestsScreen(app, onBack = { navController.popBackStack() }) }
            composable(
                ENTITY_ROUTE,
                arguments = listOf(
                    navArgument("kind") { type = NavType.StringType },
                    navArgument("identifier") { type = NavType.StringType }
                )
            ) { backStackEntry ->
                val kind = EntityKind.fromApiValue(backStackEntry.arguments?.getString("kind")) ?: EntityKind.VENUE
                val identifier = Uri.decode(backStackEntry.arguments?.getString("identifier").orEmpty())
                EntityDetailScreen(app, kind, identifier, onBack = { navController.popBackStack() })
            }
        }
    }
}
