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

    companion object {
        fun factory(app: KlangradarApp): ViewModelProvider.Factory = viewModelFactory {
            initializer { ProfileViewModel(requireNotNull(app.authRepository)) }
        }
    }
}
