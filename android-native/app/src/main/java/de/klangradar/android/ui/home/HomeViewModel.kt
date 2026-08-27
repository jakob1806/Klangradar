package de.klangradar.android.ui.home

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import de.klangradar.android.KlangradarApp
import de.klangradar.android.core.auth.AuthRepository
import de.klangradar.android.data.repository.EventRepository
import de.klangradar.android.data.repository.FollowsRepository
import de.klangradar.android.data.repository.UserRepository
import de.klangradar.android.domain.model.ConcertEvent
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

sealed interface HomeUiState {
    data object Loading : HomeUiState
    data class Failed(val message: String) : HomeUiState
    data class Loaded(
        val events: List<ConcertEvent>,
        val recommended: List<ConcertEvent> = emptyList(),
        val popular: List<ConcertEvent> = emptyList(),
        val discovery: List<ConcertEvent> = emptyList(),
        val favoriteIds: Set<String> = emptySet()
    ) : HomeUiState
}

/** Mirrors ios-native's HomeViewModel.refresh(): bootstraps a session, then
 *  fetches upcomingEvents + the three RPC-backed modules (plus the current
 *  user's favorite ids, for the heart toggle on each card) in parallel. */
class HomeViewModel(
    private val authRepository: AuthRepository,
    private val eventRepository: EventRepository,
    private val userRepository: UserRepository,
    private val followsRepository: FollowsRepository
) : ViewModel() {
    private val _uiState = MutableStateFlow<HomeUiState>(HomeUiState.Loading)
    val uiState: StateFlow<HomeUiState> = _uiState.asStateFlow()

    private var userId: String? = null
    private var accessToken: String? = null

    init {
        refresh()
    }

    fun refresh() {
        viewModelScope.launch {
            _uiState.value = HomeUiState.Loading
            try {
                val session = authRepository.restoreOrCreateSession()
                val token = session.accessToken
                userId = session.user.id
                accessToken = token
                coroutineScope {
                    val eventsDeferred = async { eventRepository.upcomingEvents(limit = 100, accessToken = token) }
                    val recommendedDeferred = async { runCatching { userRepository.recommendedEvents(16, token) }.getOrDefault(emptyList()) }
                    val popularDeferred = async { runCatching { userRepository.popularEvents(16, token) }.getOrDefault(emptyList()) }
                    val discoveryDeferred = async { runCatching { userRepository.discoveryEvents(16, token) }.getOrDefault(emptyList()) }
                    val favoritesDeferred = async {
                        runCatching { followsRepository.favoriteEventIds(session.user.id, token) }.getOrDefault(emptySet())
                    }
                    _uiState.value = HomeUiState.Loaded(
                        events = eventsDeferred.await(),
                        recommended = recommendedDeferred.await(),
                        popular = popularDeferred.await(),
                        discovery = discoveryDeferred.await(),
                        favoriteIds = favoritesDeferred.await()
                    )
                }
            } catch (t: Throwable) {
                _uiState.value = HomeUiState.Failed(t.message ?: "Unbekannter Fehler")
            }
        }
    }

    fun toggleFavorite(eventId: String) {
        val current = _uiState.value as? HomeUiState.Loaded ?: return
        val uid = userId ?: return
        val token = accessToken ?: return
        val isFavorite = eventId in current.favoriteIds
        _uiState.value = current.copy(
            favoriteIds = if (isFavorite) current.favoriteIds - eventId else current.favoriteIds + eventId
        )
        viewModelScope.launch {
            runCatching { followsRepository.setFavorite(eventId, !isFavorite, uid, token) }
        }
    }

    companion object {
        fun factory(app: KlangradarApp): ViewModelProvider.Factory = viewModelFactory {
            initializer {
                HomeViewModel(
                    authRepository = requireNotNull(app.authRepository),
                    eventRepository = requireNotNull(app.eventRepository),
                    userRepository = requireNotNull(app.userRepository),
                    followsRepository = requireNotNull(app.followsRepository)
                )
            }
        }
    }
}
