package de.klangradar.android.ui.entity

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.OpenInNew
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Check
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import coil.compose.AsyncImage
import de.klangradar.android.KlangradarApp
import de.klangradar.android.core.util.FlexibleDate
import de.klangradar.android.domain.model.EntityDetail
import de.klangradar.android.domain.model.EntityKind
import de.klangradar.android.domain.model.LinkedEvent

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun EntityDetailScreen(app: KlangradarApp, kind: EntityKind, identifier: String, onBack: () -> Unit) {
    val viewModel: EntityDetailViewModel = viewModel(factory = EntityDetailViewModel.factory(app, kind, identifier))
    val state by viewModel.uiState.collectAsState()

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(kind.germanLabel()) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Zurück")
                    }
                }
            )
        }
    ) { padding ->
        when (val current = state) {
            EntityDetailUiState.Loading -> Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) {
                CircularProgressIndicator()
            }
            is EntityDetailUiState.Failed -> Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Text(current.message, style = MaterialTheme.typography.bodyMedium)
                    Button(onClick = { viewModel.refresh() }) { Text("Erneut versuchen") }
                }
            }
            is EntityDetailUiState.Loaded -> DetailContent(current, padding, onToggleFollow = viewModel::toggleFollow)
        }
    }
}

private fun EntityKind.germanLabel() = when (this) {
    EntityKind.PERSON -> "Person"
    EntityKind.ENSEMBLE -> "Ensemble"
    EntityKind.VENUE -> "Ort"
    EntityKind.WORK -> "Werk"
}

@Composable
private fun DetailContent(state: EntityDetailUiState.Loaded, padding: PaddingValues, onToggleFollow: () -> Unit) {
    val detail = state.detail
    val uriHandler = LocalUriHandler.current

    LazyColumn(
        Modifier.fillMaxSize().padding(padding),
        contentPadding = PaddingValues(bottom = 32.dp)
    ) {
        item {
            Column(Modifier.fillMaxWidth().padding(20.dp)) {
                if (detail.kind == EntityKind.VENUE) {
                    if (!detail.primaryImageUrl.isNullOrBlank()) {
                        AsyncImage(
                            model = detail.primaryImageUrl,
                            contentDescription = detail.title,
                            contentScale = ContentScale.Crop,
                            modifier = Modifier.fillMaxWidth().height(180.dp).clip(androidx.compose.foundation.shape.RoundedCornerShape(18.dp))
                        )
                        androidx.compose.foundation.layout.Spacer(Modifier.height(14.dp))
                    }
                    Text(detail.title, style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.Bold)
                } else {
                    Row(verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                        if (!detail.primaryImageUrl.isNullOrBlank()) {
                            AsyncImage(
                                model = detail.primaryImageUrl,
                                contentDescription = detail.title,
                                contentScale = ContentScale.Crop,
                                modifier = Modifier.size(96.dp).clip(CircleShape)
                            )
                        }
                        Column {
                            Text(detail.title, style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
                            detail.subtitle?.let {
                                Text(it, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                        }
                    }
                }

                if (state.canFollow) {
                    androidx.compose.foundation.layout.Spacer(Modifier.height(14.dp))
                    if (state.isFollowing) {
                        FilledTonalButton(onClick = onToggleFollow) {
                            Icon(Icons.Filled.Check, contentDescription = null, modifier = Modifier.size(18.dp))
                            androidx.compose.foundation.layout.Spacer(Modifier.width(6.dp))
                            Text("Gefolgt")
                        }
                    } else {
                        Button(onClick = onToggleFollow) {
                            Icon(Icons.Filled.Add, contentDescription = null, modifier = Modifier.size(18.dp))
                            androidx.compose.foundation.layout.Spacer(Modifier.width(6.dp))
                            Text("Folgen")
                        }
                    }
                }

                detail.descriptionDe?.let {
                    androidx.compose.foundation.layout.Spacer(Modifier.height(16.dp))
                    Text(it, style = MaterialTheme.typography.bodyMedium)
                }

                detail.websiteUrl?.let { url ->
                    androidx.compose.foundation.layout.Spacer(Modifier.height(8.dp))
                    TextButton(onClick = { runCatching { uriHandler.openUri(url) } }) {
                        Icon(Icons.AutoMirrored.Filled.OpenInNew, contentDescription = null, modifier = Modifier.size(16.dp))
                        androidx.compose.foundation.layout.Spacer(Modifier.width(6.dp))
                        Text("Website")
                    }
                }
            }
        }

        if (detail.events.isNotEmpty()) {
            item {
                Text(
                    "Kommende Veranstaltungen",
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold,
                    modifier = Modifier.padding(horizontal = 20.dp, vertical = 8.dp)
                )
                LazyRow(
                    horizontalArrangement = Arrangement.spacedBy(14.dp),
                    contentPadding = PaddingValues(horizontal = 20.dp)
                ) {
                    items(detail.events, key = { it.id }) { event -> LinkedEventCard(event) }
                }
            }
        } else {
            item {
                Text(
                    "Aktuell nichts geplant",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(horizontal = 20.dp, vertical = 8.dp)
                )
            }
        }
    }
}

@Composable
private fun LinkedEventCard(event: LinkedEvent) {
    Card(modifier = Modifier.width(176.dp)) {
        if (!event.imageUrl.isNullOrBlank()) {
            AsyncImage(
                model = event.imageUrl,
                contentDescription = event.title,
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxWidth().height(96.dp)
            )
        }
        Column(Modifier.padding(10.dp)) {
            Text(event.title, style = MaterialTheme.typography.titleSmall, maxLines = 2, overflow = TextOverflow.Ellipsis)
            val time = FlexibleDate.parseInstant(event.startDatetime)
            if (time != null) {
                Text(
                    FlexibleDate.formatDayHeader(FlexibleDate.localDate(event.startDatetime)!!),
                    style = MaterialTheme.typography.bodySmall,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            }
        }
    }
}
