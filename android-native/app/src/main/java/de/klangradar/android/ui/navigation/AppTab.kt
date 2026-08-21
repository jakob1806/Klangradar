package de.klangradar.android.ui.navigation

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Map
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Search
import androidx.compose.ui.graphics.vector.ImageVector

/** Mirrors ios-native's RootTabView tab order exactly: Home, Search, Map,
 *  Calendar, Profile (see App/RootTabView.swift). */
enum class AppTab(val route: String, val label: String, val icon: ImageVector) {
    Home("home", "Home", Icons.Filled.Home),
    Search("search", "Suche", Icons.Filled.Search),
    Map("map", "Karte", Icons.Filled.Map),
    Calendar("calendar", "Kalender", Icons.Filled.CalendarMonth),
    Profile("profile", "Profil", Icons.Filled.Person)
}
