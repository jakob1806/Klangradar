package de.klangradar.android.ui.profile

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
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
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import de.klangradar.android.KlangradarApp
import de.klangradar.android.core.auth.AuthState

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ProfileScreen(app: KlangradarApp) {
    Scaffold(topBar = { TopAppBar(title = { Text("Profil") }) }) { padding ->
        if (app.isUsingPreviewData) {
            Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) {
                Text("Supabase noch nicht konfiguriert", style = MaterialTheme.typography.bodyMedium)
            }
            return@Scaffold
        }

        val viewModel: ProfileViewModel = viewModel(factory = ProfileViewModel.factory(app))
        val state by viewModel.state.collectAsState()

        Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                when (val current = state) {
                    AuthState.Unavailable, AuthState.Loading -> CircularProgressIndicator()
                    is AuthState.Anonymous -> {
                        Text("Nicht angemeldet", style = MaterialTheme.typography.titleMedium)
                        Text(
                            "Anmeldung mit E-Mail/Passwort folgt in einer späteren Session.",
                            style = MaterialTheme.typography.bodySmall
                        )
                    }
                    is AuthState.Authenticated -> {
                        Text(current.session.user.email ?: "Angemeldet", style = MaterialTheme.typography.titleMedium)
                        androidx.compose.foundation.layout.Spacer(Modifier.padding(8.dp))
                        Button(onClick = { viewModel.signOut() }) { Text("Abmelden") }
                    }
                    is AuthState.Failed -> Text(current.message, style = MaterialTheme.typography.bodyMedium)
                }
            }
        }
    }
}
