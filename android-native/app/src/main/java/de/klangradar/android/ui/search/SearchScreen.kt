package de.klangradar.android.ui.search

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.LibraryMusic
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Place
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Groups
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import de.klangradar.android.KlangradarApp
import de.klangradar.android.domain.model.EntityKind
import de.klangradar.android.domain.model.SearchHit

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SearchScreen(app: KlangradarApp) {
    Scaffold(topBar = { TopAppBar(title = { Text("Suche") }) }) { padding ->
        if (app.isUsingPreviewData) {
            Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) {
                Text("Supabase noch nicht konfiguriert", style = MaterialTheme.typography.bodyMedium)
            }
            return@Scaffold
        }

        val viewModel: SearchViewModel = viewModel(factory = SearchViewModel.factory(app))
        val query by viewModel.query.collectAsState()
        val state by viewModel.uiState.collectAsState()

        Column(Modifier.fillMaxSize().padding(padding)) {
            OutlinedTextField(
                value = query,
                onValueChange = viewModel::onQueryChange,
                modifier = Modifier.fillMaxWidth().padding(16.dp),
                placeholder = { Text("Personen, Ensembles, Orte, Werke …") },
                leadingIcon = { Icon(Icons.Filled.Search, contentDescription = null) },
                singleLine = true
            )

            when (val current = state) {
                SearchUiState.Idle -> Unit
                SearchUiState.Loading -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator()
                }
                is SearchUiState.Failed -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    Text(current.message, style = MaterialTheme.typography.bodyMedium)
                }
                is SearchUiState.Loaded -> {
                    if (current.hits.isEmpty()) {
                        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                            Text("Keine Treffer", style = MaterialTheme.typography.bodyMedium)
                        }
                    } else {
                        LazyColumn {
                            items(current.hits, key = { it.id }) { hit -> SearchResultRow(hit) }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun SearchResultRow(hit: SearchHit) {
    ListItem(
        headlineContent = { Text(hit.title) },
        supportingContent = hit.subtitle?.let { { Text(it) } },
        leadingContent = { Icon(iconFor(hit.kind), contentDescription = null) }
    )
}

private fun iconFor(kind: EntityKind?) = when (kind) {
    EntityKind.PERSON -> Icons.Filled.Person
    EntityKind.ENSEMBLE -> Icons.Filled.Groups
    EntityKind.VENUE -> Icons.Filled.Place
    EntityKind.WORK -> Icons.Filled.LibraryMusic
    null -> Icons.Filled.Search
}
