package de.klangradar.android.ui.interests

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import de.klangradar.android.KlangradarApp
import de.klangradar.android.core.auth.AuthRepository
import de.klangradar.android.data.repository.UserRepository
import de.klangradar.android.domain.model.GenreOption
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

sealed interface InterestsUiState {
    data object Loading : InterestsUiState
    data class Failed(val message: String) : InterestsUiState
    data class Loaded(val options: List<GenreOption>, val selected: Set<String>) : InterestsUiState
}

class InterestsViewModel(
    private val authRepository: AuthRepository,
    private val userRepository: UserRepository
) : ViewModel() {
    private val _uiState = MutableStateFlow<InterestsUiState>(InterestsUiState.Loading)
    val uiState: StateFlow<InterestsUiState> = _uiState.asStateFlow()

    private var userId: String? = null
    private var accessToken: String? = null

    init {
        refresh()
    }

    fun refresh() {
        viewModelScope.launch {
            _uiState.value = InterestsUiState.Loading
            try {
                val session = authRepository.restoreOrCreateSession()
                userId = session.user.id
                accessToken = session.accessToken
                val options = userRepository.genreOptions()
                val selected = userRepository.selectedGenreIds(session.user.id, session.accessToken)
                _uiState.value = InterestsUiState.Loaded(options, selected)
            } catch (t: Throwable) {
                _uiState.value = InterestsUiState.Failed(t.message ?: "Unbekannter Fehler")
            }
        }
    }

    fun toggle(genreId: String, selected: Boolean) {
        val current = _uiState.value as? InterestsUiState.Loaded ?: return
        val uid = userId ?: return
        val token = accessToken ?: return
        val newSelected = if (selected) current.selected + genreId else current.selected - genreId
        _uiState.value = current.copy(selected = newSelected)
        viewModelScope.launch {
            runCatching { userRepository.setGenreInterest(genreId, selected, uid, token) }
        }
    }

    companion object {
        fun factory(app: KlangradarApp): ViewModelProvider.Factory = viewModelFactory {
            initializer {
                InterestsViewModel(
                    authRepository = requireNotNull(app.authRepository),
                    userRepository = requireNotNull(app.userRepository)
                )
            }
        }
    }
}
