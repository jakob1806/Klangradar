package de.klangradar.android.ui.interests

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
import de.klangradar.android.KlangradarApp
import androidx.lifecycle.viewmodel.compose.viewModel

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun InterestsScreen(app: KlangradarApp, onBack: () -> Unit) {
    val viewModel: InterestsViewModel = viewModel(factory = InterestsViewModel.factory(app))
    val state by viewModel.uiState.collectAsState()

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Interessen") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Zurück")
                    }
                }
            )
        }
    ) { padding ->
        when (val current = state) {
            InterestsUiState.Loading -> Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) {
                CircularProgressIndicator()
            }
            is InterestsUiState.Failed -> Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Text(current.message, style = MaterialTheme.typography.bodyMedium)
                    Button(onClick = { viewModel.refresh() }) { Text("Erneut versuchen") }
                }
            }
            is InterestsUiState.Loaded -> LazyColumn(Modifier.fillMaxSize().padding(padding)) {
                items(current.options, key = { it.id }) { option ->
                    val checked = current.selected.contains(option.id)
                    ListItem(
                        headlineContent = { Text(option.label) },
                        trailingContent = {
                            Switch(checked = checked, onCheckedChange = { viewModel.toggle(option.id, it) })
                        }
                    )
                }
            }
        }
    }
}
