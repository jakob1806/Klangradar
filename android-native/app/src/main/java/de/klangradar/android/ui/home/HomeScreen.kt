package de.klangradar.android.ui.home

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import coil.compose.AsyncImage
import de.klangradar.android.KlangradarApp
import de.klangradar.android.domain.model.ConcertEvent

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HomeScreen(app: KlangradarApp) {
    Scaffold(topBar = { TopAppBar(title = { Text("Klangradar") }) }) { padding ->
        if (app.isUsingPreviewData) {
            NotConfiguredNotice(padding)
            return@Scaffold
        }

        val viewModel: HomeViewModel = viewModel(factory = HomeViewModel.factory(app))
        val state by viewModel.uiState.collectAsState()

        when (val current = state) {
            HomeUiState.Loading -> Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) {
                CircularProgressIndicator()
            }
            is HomeUiState.Failed -> Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Text("Laden fehlgeschlagen", style = MaterialTheme.typography.titleMedium)
                    Text(current.message, style = MaterialTheme.typography.bodyMedium)
                    Button(onClick = { viewModel.refresh() }) { Text("Erneut versuchen") }
                }
            }
            is HomeUiState.Loaded -> LazyColumn(
                modifier = Modifier.fillMaxSize().padding(padding),
                contentPadding = PaddingValues(vertical = 16.dp),
                verticalArrangement = Arrangement.spacedBy(28.dp)
            ) {
                item { EventRail("Für dich empfohlen", current.recommended) }
                item { EventRail("Beliebt in München", current.popular) }
                item { EventRail("Neu für dich entdecken", current.discovery) }
                item { EventRail("Demnächst in München", current.events) }
            }
        }
    }
}

@Composable
private fun NotConfiguredNotice(padding: PaddingValues) {
    Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Text("Supabase noch nicht konfiguriert", style = MaterialTheme.typography.titleMedium)
            Text(
                "Lege android-native/local.properties an (siehe local.properties.example).",
                style = MaterialTheme.typography.bodyMedium
            )
        }
    }
}

/** The Compose equivalent of ios-native's EventRail: a title + a
 *  horizontal, self-hiding rail of event cards (renders nothing if empty,
 *  same as EventRail's `if !events.isEmpty` on iOS). */
@Composable
fun EventRail(title: String, events: List<ConcertEvent>) {
    if (events.isEmpty()) return
    Column {
        Text(
            title,
            style = MaterialTheme.typography.titleLarge,
            modifier = Modifier.padding(horizontal = 20.dp)
        )
        androidx.compose.foundation.layout.Spacer(Modifier.height(12.dp))
        LazyRow(
            horizontalArrangement = Arrangement.spacedBy(16.dp),
            contentPadding = PaddingValues(horizontal = 20.dp)
        ) {
            items(events, key = { it.id }) { event -> EventCard(event) }
        }
    }
}

@Composable
fun EventCard(event: ConcertEvent) {
    Card(modifier = Modifier.width(196.dp)) {
        AsyncImage(
            model = event.primaryImageUrl,
            contentDescription = event.title,
            contentScale = ContentScale.Crop,
            modifier = Modifier.fillMaxWidth().height(110.dp)
        )
        Column(Modifier.padding(10.dp)) {
            Text(
                event.title,
                style = MaterialTheme.typography.titleSmall,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis
            )
            event.venues?.name?.let {
                Text(it, style = MaterialTheme.typography.bodySmall, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
        }
    }
}
