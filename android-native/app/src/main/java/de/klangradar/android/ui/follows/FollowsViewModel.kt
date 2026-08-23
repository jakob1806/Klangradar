package de.klangradar.android.ui.follows

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import de.klangradar.android.KlangradarApp
import de.klangradar.android.core.auth.AuthRepository
import de.klangradar.android.data.repository.FollowKind
import de.klangradar.android.data.repository.FollowsRepository
import de.klangradar.android.domain.model.FollowedEntity
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

data class MyFollows(
    val persons: List<FollowedEntity> = emptyList(),
    val ensembles: List<FollowedEntity> = emptyList(),
    val venues: List<FollowedEntity> = emptyList()
)

sealed interface FollowsUiState {
    data object Loading : FollowsUiState
    data class Failed(val message: String) : FollowsUiState
    data class Loaded(val follows: MyFollows) : FollowsUiState
}

class FollowsViewModel(
    private val authRepository: AuthRepository,
    private val followsRepository: FollowsRepository
) : ViewModel() {
    private val _uiState = MutableStateFlow<FollowsUiState>(FollowsUiState.Loading)
    val uiState: StateFlow<FollowsUiState> = _uiState.asStateFlow()

    private var userId: String? = null
    private var accessToken: String? = null

    init {
        refresh()
    }

    fun refresh() {
        viewModelScope.launch {
            _uiState.value = FollowsUiState.Loading
            try {
                val session = authRepository.restoreOrCreateSession()
                userId = session.user.id
                accessToken = session.accessToken
                loadFollows(session.user.id, session.accessToken)
            } catch (t: Throwable) {
                _uiState.value = FollowsUiState.Failed(t.message ?: "Unbekannter Fehler")
            }
        }
    }

    private suspend fun loadFollows(userId: String, token: String) {
        val follows = MyFollows(
            persons = followsRepository.followed(FollowKind.PERSON, userId, token),
            ensembles = followsRepository.followed(FollowKind.ENSEMBLE, userId, token),
            venues = followsRepository.followed(FollowKind.VENUE, userId, token)
        )
        _uiState.value = FollowsUiState.Loaded(follows)
    }

    fun unfollow(kind: FollowKind, entityId: String) {
        val uid = userId ?: return
        val token = accessToken ?: return
        viewModelScope.launch {
            runCatching { followsRepository.setFollow(kind, entityId, selected = false, userId = uid, token = token) }
            loadFollows(uid, token)
        }
    }

    fun setNotify(kind: FollowKind, entityId: String, notify: Boolean) {
        val uid = userId ?: return
        val token = accessToken ?: return
        viewModelScope.launch {
            runCatching { followsRepository.setNotify(kind, entityId, notify, uid, token) }
            loadFollows(uid, token)
        }
    }

    companion object {
        fun factory(app: KlangradarApp): ViewModelProvider.Factory = viewModelFactory {
            initializer {
                FollowsViewModel(
                    authRepository = requireNotNull(app.authRepository),
                    followsRepository = requireNotNull(app.followsRepository)
                )
            }
        }
    }
}
