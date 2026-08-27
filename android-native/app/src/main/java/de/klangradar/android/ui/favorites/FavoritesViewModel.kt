package de.klangradar.android.ui.favorites

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import de.klangradar.android.KlangradarApp
import de.klangradar.android.core.auth.AuthRepository
import de.klangradar.android.data.repository.FollowsRepository
import de.klangradar.android.domain.model.ConcertEvent
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

sealed interface FavoritesUiState {
    data object Loading : FavoritesUiState
    data class Failed(val message: String) : FavoritesUiState
    data class Loaded(val events: List<ConcertEvent>) : FavoritesUiState
}

class FavoritesViewModel(
    private val authRepository: AuthRepository,
    private val followsRepository: FollowsRepository
) : ViewModel() {
    private val _uiState = MutableStateFlow<FavoritesUiState>(FavoritesUiState.Loading)
    val uiState: StateFlow<FavoritesUiState> = _uiState.asStateFlow()

    init {
        refresh()
    }

    fun refresh() {
        viewModelScope.launch {
            _uiState.value = FavoritesUiState.Loading
            try {
                val session = authRepository.restoreOrCreateSession()
                val events = followsRepository.favoriteEvents(session.user.id, session.accessToken)
                _uiState.value = FavoritesUiState.Loaded(events)
            } catch (t: Throwable) {
                _uiState.value = FavoritesUiState.Failed(t.message ?: "Unbekannter Fehler")
            }
        }
    }

    companion object {
        fun factory(app: KlangradarApp): ViewModelProvider.Factory = viewModelFactory {
            initializer {
                FavoritesViewModel(
                    authRepository = requireNotNull(app.authRepository),
                    followsRepository = requireNotNull(app.followsRepository)
                )
            }
        }
    }
}
