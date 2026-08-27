package de.klangradar.android.ui.entity

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import de.klangradar.android.KlangradarApp
import de.klangradar.android.core.auth.AuthRepository
import de.klangradar.android.data.repository.ContentRepository
import de.klangradar.android.data.repository.FollowKind
import de.klangradar.android.data.repository.FollowsRepository
import de.klangradar.android.domain.model.EntityDetail
import de.klangradar.android.domain.model.EntityKind
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

sealed interface EntityDetailUiState {
    data object Loading : EntityDetailUiState
    data class Failed(val message: String) : EntityDetailUiState
    data class Loaded(val detail: EntityDetail, val isFollowing: Boolean, val canFollow: Boolean) : EntityDetailUiState
}

class EntityDetailViewModel(
    private val kind: EntityKind,
    private val identifier: String,
    private val authRepository: AuthRepository,
    private val contentRepository: ContentRepository,
    private val followsRepository: FollowsRepository
) : ViewModel() {
    private val _uiState = MutableStateFlow<EntityDetailUiState>(EntityDetailUiState.Loading)
    val uiState: StateFlow<EntityDetailUiState> = _uiState.asStateFlow()

    private var userId: String? = null
    private var accessToken: String? = null

    init {
        refresh()
    }

    fun refresh() {
        viewModelScope.launch {
            _uiState.value = EntityDetailUiState.Loading
            try {
                val session = authRepository.restoreOrCreateSession()
                userId = session.user.id
                accessToken = session.accessToken
                val detail = contentRepository.detail(kind, identifier)
                if (detail == null) {
                    _uiState.value = EntityDetailUiState.Failed("Nicht gefunden")
                    return@launch
                }
                val followKind = followKindFor(kind)
                val isFollowing = if (followKind != null && session.user.isAnonymous != true) {
                    runCatching {
                        followsRepository.followed(followKind, session.user.id, session.accessToken)
                            .any { it.id == detail.id }
                    }.getOrDefault(false)
                } else false
                _uiState.value = EntityDetailUiState.Loaded(
                    detail = detail,
                    isFollowing = isFollowing,
                    canFollow = followKind != null && session.user.isAnonymous != true
                )
            } catch (t: Throwable) {
                _uiState.value = EntityDetailUiState.Failed(t.message ?: "Unbekannter Fehler")
            }
        }
    }

    fun toggleFollow() {
        val current = _uiState.value as? EntityDetailUiState.Loaded ?: return
        val followKind = followKindFor(kind) ?: return
        val uid = userId ?: return
        val token = accessToken ?: return
        val newValue = !current.isFollowing
        _uiState.value = current.copy(isFollowing = newValue)
        viewModelScope.launch {
            runCatching { followsRepository.setFollow(followKind, current.detail.id, newValue, uid, token) }
        }
    }

    private fun followKindFor(kind: EntityKind): FollowKind? = when (kind) {
        EntityKind.PERSON -> FollowKind.PERSON
        EntityKind.ENSEMBLE -> FollowKind.ENSEMBLE
        EntityKind.VENUE -> FollowKind.VENUE
        EntityKind.WORK -> null
    }

    companion object {
        fun factory(app: KlangradarApp, kind: EntityKind, identifier: String): ViewModelProvider.Factory = viewModelFactory {
            initializer {
                EntityDetailViewModel(
                    kind = kind,
                    identifier = identifier,
                    authRepository = requireNotNull(app.authRepository),
                    contentRepository = requireNotNull(app.contentRepository),
                    followsRepository = requireNotNull(app.followsRepository)
                )
            }
        }
    }
}
