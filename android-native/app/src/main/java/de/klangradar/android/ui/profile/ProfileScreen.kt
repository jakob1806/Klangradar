package de.klangradar.android.ui.profile

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import de.klangradar.android.KlangradarApp
import de.klangradar.android.core.auth.AuthState

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ProfileScreen(
    app: KlangradarApp,
    onOpenFavorites: () -> Unit = {},
    onOpenFollows: () -> Unit = {},
    onOpenInterests: () -> Unit = {}
) {
    Scaffold(topBar = { TopAppBar(title = { Text("Profil") }) }) { padding ->
        if (app.isUsingPreviewData) {
            Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) {
                Text("Supabase noch nicht konfiguriert", style = MaterialTheme.typography.bodyMedium)
            }
            return@Scaffold
        }

        val viewModel: ProfileViewModel = viewModel(factory = ProfileViewModel.factory(app))
        val state by viewModel.state.collectAsState()

        Box(Modifier.fillMaxSize().padding(padding)) {
            when (val current = state) {
                AuthState.Unavailable, AuthState.Loading -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator()
                }
                is AuthState.Anonymous -> AuthForm(viewModel)
                is AuthState.Authenticated -> SignedInContent(viewModel, current, onOpenFavorites, onOpenFollows, onOpenInterests)
                is AuthState.Failed -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    Text(current.message, style = MaterialTheme.typography.bodyMedium)
                }
            }
        }
    }
}

@Composable
private fun SignedInContent(
    viewModel: ProfileViewModel,
    state: AuthState.Authenticated,
    onOpenFavorites: () -> Unit,
    onOpenFollows: () -> Unit,
    onOpenInterests: () -> Unit
) {
    Column(Modifier.fillMaxSize().padding(24.dp)) {
        Text(state.session.user.email ?: "Angemeldet", style = MaterialTheme.typography.titleMedium)
        androidx.compose.foundation.layout.Spacer(Modifier.padding(top = 20.dp))
        androidx.compose.material3.ListItem(
            headlineContent = { Text("Meine Favoriten") },
            modifier = Modifier.clickable(onClick = onOpenFavorites)
        )
        androidx.compose.material3.ListItem(
            headlineContent = { Text("Meine Follows") },
            modifier = Modifier.clickable(onClick = onOpenFollows)
        )
        androidx.compose.material3.ListItem(
            headlineContent = { Text("Interessen") },
            modifier = Modifier.clickable(onClick = onOpenInterests)
        )
        androidx.compose.foundation.layout.Spacer(Modifier.padding(top = 12.dp))
        Button(onClick = { viewModel.signOut() }) { Text("Abmelden") }
    }
}

private enum class AuthFormMode { LOGIN, SIGN_UP, FORGOT_PASSWORD }

@Composable
private fun AuthForm(viewModel: ProfileViewModel) {
    var mode by remember { mutableStateOf(AuthFormMode.LOGIN) }
    var email by remember { mutableStateOf("") }
    var password by remember { mutableStateOf("") }
    val busy by viewModel.formBusy.collectAsState()
    val error by viewModel.formError.collectAsState()
    val resetSent by viewModel.passwordResetSent.collectAsState()

    Column(
        Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(24.dp)
    ) {
        Text(
            when (mode) {
                AuthFormMode.LOGIN -> "Anmelden"
                AuthFormMode.SIGN_UP -> "Konto erstellen"
                AuthFormMode.FORGOT_PASSWORD -> "Passwort zurücksetzen"
            },
            style = MaterialTheme.typography.headlineSmall
        )
        androidx.compose.foundation.layout.Spacer(Modifier.padding(top = 16.dp))

        OutlinedTextField(
            value = email,
            onValueChange = { email = it },
            label = { Text("E-Mail") },
            singleLine = true,
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Email),
            modifier = Modifier.fillMaxWidth()
        )

        if (mode != AuthFormMode.FORGOT_PASSWORD) {
            androidx.compose.foundation.layout.Spacer(Modifier.padding(top = 12.dp))
            OutlinedTextField(
                value = password,
                onValueChange = { password = it },
                label = { Text("Passwort") },
                singleLine = true,
                visualTransformation = PasswordVisualTransformation(),
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
                modifier = Modifier.fillMaxWidth()
            )
        }

        if (resetSent && mode == AuthFormMode.FORGOT_PASSWORD) {
            androidx.compose.foundation.layout.Spacer(Modifier.padding(top = 12.dp))
            Text(
                "E-Mail zum Zurücksetzen des Passworts wurde verschickt.",
                style = MaterialTheme.typography.bodySmall
            )
        }

        error?.let {
            androidx.compose.foundation.layout.Spacer(Modifier.padding(top = 12.dp))
            Text(it, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall)
        }

        androidx.compose.foundation.layout.Spacer(Modifier.padding(top = 20.dp))
        Button(
            onClick = {
                when (mode) {
                    AuthFormMode.LOGIN -> viewModel.signIn(email.trim(), password)
                    AuthFormMode.SIGN_UP -> viewModel.signUp(email.trim(), password)
                    AuthFormMode.FORGOT_PASSWORD -> viewModel.requestPasswordReset(email.trim())
                }
            },
            enabled = !busy && email.isNotBlank() && (mode == AuthFormMode.FORGOT_PASSWORD || password.isNotBlank()),
            modifier = Modifier.fillMaxWidth()
        ) {
            Text(
                when (mode) {
                    AuthFormMode.LOGIN -> "Anmelden"
                    AuthFormMode.SIGN_UP -> "Konto erstellen"
                    AuthFormMode.FORGOT_PASSWORD -> "Link senden"
                }
            )
        }

        androidx.compose.foundation.layout.Spacer(Modifier.padding(top = 8.dp))
        when (mode) {
            AuthFormMode.LOGIN -> {
                TextButton(onClick = { mode = AuthFormMode.FORGOT_PASSWORD; viewModel.clearPasswordResetSent() }) {
                    Text("Passwort vergessen?")
                }
                TextButton(onClick = { mode = AuthFormMode.SIGN_UP }) {
                    Text("Noch kein Konto? Registrieren")
                }
            }
            AuthFormMode.SIGN_UP -> TextButton(onClick = { mode = AuthFormMode.LOGIN }) {
                Text("Bereits ein Konto? Anmelden")
            }
            AuthFormMode.FORGOT_PASSWORD -> TextButton(onClick = { mode = AuthFormMode.LOGIN }) {
                Text("Zurück zur Anmeldung")
            }
        }
    }
}
