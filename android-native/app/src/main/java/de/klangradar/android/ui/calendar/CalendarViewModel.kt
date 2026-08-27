package de.klangradar.android.ui.calendar

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import de.klangradar.android.KlangradarApp
import de.klangradar.android.core.auth.AuthRepository
import de.klangradar.android.core.util.FlexibleDate
import de.klangradar.android.data.repository.EventRepository
import de.klangradar.android.domain.model.ConcertEvent
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import java.time.LocalDate

data class CalendarDay(val date: LocalDate, val events: List<ConcertEvent>)

sealed interface CalendarUiState {
    data object Loading : CalendarUiState
    data class Failed(val message: String) : CalendarUiState
    data class Loaded(val days: List<CalendarDay>) : CalendarUiState
}

class CalendarViewModel(
    private val authRepository: AuthRepository,
    private val eventRepository: EventRepository
) : ViewModel() {
    private val _uiState = MutableStateFlow<CalendarUiState>(CalendarUiState.Loading)
    val uiState: StateFlow<CalendarUiState> = _uiState.asStateFlow()

    init {
        refresh()
    }

    fun refresh() {
        viewModelScope.launch {
            _uiState.value = CalendarUiState.Loading
            try {
                val token = authRepository.restoreOrCreateSession().accessToken
                val events = eventRepository.allUpcomingEvents(accessToken = token)
                val days = events
                    .mapNotNull { event -> FlexibleDate.localDate(event.startDatetime)?.let { it to event } }
                    .groupBy({ it.first }, { it.second })
                    .toSortedMap()
                    .map { (date, dayEvents) -> CalendarDay(date, dayEvents) }
                _uiState.value = CalendarUiState.Loaded(days)
            } catch (t: Throwable) {
                _uiState.value = CalendarUiState.Failed(t.message ?: "Unbekannter Fehler")
            }
        }
    }

    companion object {
        fun factory(app: KlangradarApp): ViewModelProvider.Factory = viewModelFactory {
            initializer {
                CalendarViewModel(
                    authRepository = requireNotNull(app.authRepository),
                    eventRepository = requireNotNull(app.eventRepository)
                )
            }
        }
    }
}
