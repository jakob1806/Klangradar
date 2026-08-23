package de.klangradar.android.ui.profile

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import de.klangradar.android.KlangradarApp
import de.klangradar.android.core.auth.AuthRepository
import de.klangradar.android.core.auth.AuthState
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

class ProfileViewModel(private val authRepository: AuthRepository) : ViewModel() {
    private val _state = MutableStateFlow<AuthState>(AuthState.Loading)
    val state: StateFlow<AuthState> = _state.asStateFlow()

    private val _formError = MutableStateFlow<String?>(null)
    val formError: StateFlow<String?> = _formError.asStateFlow()

    private val _formBusy = MutableStateFlow(false)
    val formBusy: StateFlow<Boolean> = _formBusy.asStateFlow()

    private val _passwordResetSent = MutableStateFlow(false)
    val passwordResetSent: StateFlow<Boolean> = _passwordResetSent.asStateFlow()

    init {
        refresh()
    }

    fun refresh() {
        viewModelScope.launch {
            _state.value = AuthState.Loading
            try {
                val session = authRepository.restoreOrCreateSession()
                _state.value = if (session.user.isAnonymous == true) {
                    AuthState.Anonymous(session)
                } else {
                    AuthState.Authenticated(session)
                }
            } catch (t: Throwable) {
                _state.value = AuthState.Failed(t.message ?: "Unbekannter Fehler")
            }
        }
    }

    fun signIn(email: String, password: String) = runForm {
        val session = authRepository.signInWithPassword(email, password)
        _state.value = AuthState.Authenticated(session)
    }

    fun signUp(email: String, password: String) = runForm {
        val session = authRepository.signUp(email, password)
        // A fresh signup account is unconfirmed/anonymous-looking until the
        // user verifies their email — surfaced as Authenticated once
        // is_anonymous is false, same check used everywhere else.
        _state.value = if (session.user.isAnonymous == true) {
            AuthState.Anonymous(session)
        } else {
            AuthState.Authenticated(session)
        }
    }

    fun requestPasswordReset(email: String) = runForm {
        authRepository.requestPasswordReset(email)
        _passwordResetSent.value = true
    }

    fun clearPasswordResetSent() {
        _passwordResetSent.value = false
    }

    fun signOut() {
        viewModelScope.launch {
            _state.value = AuthState.Loading
            try {
                val session = authRepository.signOut()
                _state.value = AuthState.Anonymous(session)
            } catch (t: Throwable) {
                _state.value = AuthState.Failed(t.message ?: "Unbekannter Fehler")
            }
        }
    }

    private fun runForm(block: suspend () -> Unit) {
        viewModelScope.launch {
            _formBusy.value = true
            _formError.value = null
            try {
                block()
            } catch (t: Throwable) {
                _formError.value = t.message ?: "Unbekannter Fehler"
            } finally {
                _formBusy.value = false
            }
        }
    }

    companion object {
        fun factory(app: KlangradarApp): ViewModelProvider.Factory = viewModelFactory {
            initializer { ProfileViewModel(requireNotNull(app.authRepository)) }
        }
    }
}
