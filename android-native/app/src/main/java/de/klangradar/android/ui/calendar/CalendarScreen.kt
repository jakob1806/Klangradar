package de.klangradar.android.ui.calendar

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
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
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import de.klangradar.android.KlangradarApp
import de.klangradar.android.core.util.FlexibleDate
import de.klangradar.android.domain.model.ConcertEvent

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CalendarScreen(app: KlangradarApp) {
    Scaffold(topBar = { TopAppBar(title = { Text("Kalender") }) }) { padding ->
        if (app.isUsingPreviewData) {
            Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) {
                Text("Supabase noch nicht konfiguriert", style = MaterialTheme.typography.bodyMedium)
            }
            return@Scaffold
        }

        val viewModel: CalendarViewModel = viewModel(factory = CalendarViewModel.factory(app))
        val state by viewModel.uiState.collectAsState()

        when (val current = state) {
            CalendarUiState.Loading -> Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) {
                CircularProgressIndicator()
            }
            is CalendarUiState.Failed -> Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Text(current.message, style = MaterialTheme.typography.bodyMedium)
                    Button(onClick = { viewModel.refresh() }) { Text("Erneut versuchen") }
                }
            }
            is CalendarUiState.Loaded -> LazyColumn(Modifier.fillMaxSize().padding(padding)) {
                current.days.forEach { day ->
                    item(key = "header-${day.date}") {
                        Text(
                            FlexibleDate.formatDayHeader(day.date).replaceFirstChar { it.uppercase() },
                            style = MaterialTheme.typography.titleMedium,
                            fontWeight = FontWeight.SemiBold,
                            modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 10.dp)
                        )
                    }
                    items(day.events, key = { it.id }) { event -> CalendarEventRow(event) }
                }
            }
        }
    }
}

@Composable
private fun CalendarEventRow(event: ConcertEvent) {
    val time = FlexibleDate.parseInstant(event.startDatetime)?.let { FlexibleDate.formatTime(it) }
    ListItem(
        headlineContent = { Text(event.title) },
        supportingContent = { Text(event.venues?.name ?: event.venueDetail.orEmpty()) },
        trailingContent = time?.let { { Text(it) } }
    )
}
