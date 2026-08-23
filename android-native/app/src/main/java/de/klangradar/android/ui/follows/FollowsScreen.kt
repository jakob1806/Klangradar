package de.klangradar.android.ui.follows

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
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import de.klangradar.android.KlangradarApp
import de.klangradar.android.data.repository.FollowKind
import de.klangradar.android.domain.model.FollowedEntity

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FollowsScreen(app: KlangradarApp, onBack: () -> Unit) {
    val viewModel: FollowsViewModel = viewModel(factory = FollowsViewModel.factory(app))
    val state by viewModel.uiState.collectAsState()

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Meine Follows") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Zurück")
                    }
                }
            )
        }
    ) { padding ->
        when (val current = state) {
            FollowsUiState.Loading -> Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) {
                CircularProgressIndicator()
            }
            is FollowsUiState.Failed -> Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Text(current.message, style = MaterialTheme.typography.bodyMedium)
                    Button(onClick = { viewModel.refresh() }) { Text("Erneut versuchen") }
                }
            }
            is FollowsUiState.Loaded -> {
                val follows = current.follows
                if (follows.persons.isEmpty() && follows.ensembles.isEmpty() && follows.venues.isEmpty()) {
                    Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) {
                        Text("Noch nichts gefolgt", style = MaterialTheme.typography.bodyMedium)
                    }
                } else {
                    LazyColumn(Modifier.fillMaxSize().padding(padding)) {
                        section("Personen", follows.persons, FollowKind.PERSON, viewModel)
                        section("Ensembles", follows.ensembles, FollowKind.ENSEMBLE, viewModel)
                        section("Orte", follows.venues, FollowKind.VENUE, viewModel)
                    }
                }
            }
        }
    }
}

private fun androidx.compose.foundation.lazy.LazyListScope.section(
    title: String,
    entities: List<FollowedEntity>,
    kind: FollowKind,
    viewModel: FollowsViewModel
) {
    if (entities.isEmpty()) return
    item(key = "header-$title") {
        Text(
            title,
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.SemiBold,
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 10.dp)
        )
    }
    items(entities, key = { "$kind-${it.id}" }) { entity ->
        FollowRow(entity, onUnfollow = { viewModel.unfollow(kind, entity.id) }, onNotifyChange = { viewModel.setNotify(kind, entity.id, it) })
    }
}

@Composable
private fun FollowRow(entity: FollowedEntity, onUnfollow: () -> Unit, onNotifyChange: (Boolean) -> Unit) {
    ListItem(
        headlineContent = { Text(entity.name) },
        trailingContent = {
            androidx.compose.foundation.layout.Row(verticalAlignment = Alignment.CenterVertically) {
                Switch(checked = entity.notifyNewEvents, onCheckedChange = onNotifyChange)
                androidx.compose.material3.TextButton(onClick = onUnfollow) { Text("Entfolgen") }
            }
        }
    )
}
