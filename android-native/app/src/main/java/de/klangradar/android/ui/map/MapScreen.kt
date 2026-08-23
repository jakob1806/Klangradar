package de.klangradar.android.ui.map

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Place
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.lifecycle.viewmodel.compose.viewModel
import de.klangradar.android.KlangradarApp
import de.klangradar.android.domain.model.VenueLocation

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MapScreen(app: KlangradarApp) {
    Scaffold(topBar = { TopAppBar(title = { Text("Karte") }) }) { padding ->
        if (app.isUsingPreviewData) {
            Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) {
                Text("Supabase noch nicht konfiguriert", style = MaterialTheme.typography.bodyMedium)
            }
            return@Scaffold
        }

        val viewModel: MapViewModel = viewModel(factory = MapViewModel.factory(app))
        val state by viewModel.uiState.collectAsState()
        val context = LocalContext.current

        when (val current = state) {
            MapUiState.Loading -> Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) {
                CircularProgressIndicator()
            }
            is MapUiState.Failed -> Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Text(current.message, style = MaterialTheme.typography.bodyMedium)
                    Button(onClick = { viewModel.refresh() }) { Text("Erneut versuchen") }
                }
            }
            is MapUiState.Loaded -> LazyColumn(Modifier.fillMaxSize().padding(padding)) {
                items(current.venues, key = { it.id }) { venue ->
                    VenueRow(venue) { openInMapsApp(context, venue) }
                }
            }
        }
    }
}

@Composable
private fun VenueRow(venue: VenueLocation, onClick: () -> Unit) {
    ListItem(
        headlineContent = { Text(venue.name) },
        supportingContent = venue.addressCity?.let { { Text(it) } },
        leadingContent = { Icon(Icons.Filled.Place, contentDescription = null) },
        modifier = Modifier.clickable(onClick = onClick)
    )
}

private fun openInMapsApp(context: Context, venue: VenueLocation) {
    val label = Uri.encode(venue.name)
    val uri = Uri.parse("geo:${venue.lat},${venue.lng}?q=${venue.lat},${venue.lng}($label)")
    val intent = Intent(Intent.ACTION_VIEW, uri)
    try {
        context.startActivity(intent)
    } catch (_: ActivityNotFoundException) {
        // No maps app installed — silently ignore, same non-fatal fallback
        // philosophy as ios-native's missing-provider guards.
    }
}
