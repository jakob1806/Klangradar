package de.klangradar.android.ui.favorites

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
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
import androidx.lifecycle.viewmodel.compose.viewModel
import de.klangradar.android.KlangradarApp
import de.klangradar.android.domain.model.ConcertEvent

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FavoritesScreen(app: KlangradarApp, onBack: () -> Unit) {
    val viewModel: FavoritesViewModel = viewModel(factory = FavoritesViewModel.factory(app))
    val state by viewModel.uiState.collectAsState()

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Favoriten") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Zurück")
                    }
                }
            )
        }
    ) { padding ->
        when (val current = state) {
            FavoritesUiState.Loading -> Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) {
                CircularProgressIndicator()
            }
            is FavoritesUiState.Failed -> Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Text(current.message, style = MaterialTheme.typography.bodyMedium)
                    Button(onClick = { viewModel.refresh() }) { Text("Erneut versuchen") }
                }
            }
            is FavoritesUiState.Loaded -> {
                if (current.events.isEmpty()) {
                    Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) {
                        Text("Noch keine Favoriten", style = MaterialTheme.typography.bodyMedium)
                    }
                } else {
                    LazyColumn(Modifier.fillMaxSize().padding(padding)) {
                        items(current.events, key = { it.id }) { event -> FavoriteEventRow(event) }
                    }
                }
            }
        }
    }
}

@Composable
private fun FavoriteEventRow(event: ConcertEvent) {
    ListItem(
        headlineContent = { Text(event.title) },
        supportingContent = { Text(event.venues?.name.orEmpty()) }
    )
}
