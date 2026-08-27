package de.klangradar.android.ui.search

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import de.klangradar.android.KlangradarApp
import de.klangradar.android.data.repository.ContentRepository
import de.klangradar.android.domain.model.SearchHit
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

sealed interface SearchUiState {
    data object Idle : SearchUiState
    data object Loading : SearchUiState
    data class Loaded(val hits: List<SearchHit>) : SearchUiState
    data class Failed(val message: String) : SearchUiState
}

class SearchViewModel(private val repository: ContentRepository) : ViewModel() {
    private val _query = MutableStateFlow("")
    val query: StateFlow<String> = _query.asStateFlow()

    private val _uiState = MutableStateFlow<SearchUiState>(SearchUiState.Idle)
    val uiState: StateFlow<SearchUiState> = _uiState.asStateFlow()

    private var debounceJob: Job? = null

    fun onQueryChange(value: String) {
        _query.value = value
        debounceJob?.cancel()
        if (value.isBlank()) {
            _uiState.value = SearchUiState.Idle
            return
        }
        debounceJob = viewModelScope.launch {
            delay(300)
            runSearch(value)
        }
    }

    private suspend fun runSearch(value: String) {
        _uiState.value = SearchUiState.Loading
        try {
            _uiState.value = SearchUiState.Loaded(repository.search(value, limit = 30))
        } catch (t: Throwable) {
            _uiState.value = SearchUiState.Failed(t.message ?: "Unbekannter Fehler")
        }
    }

    companion object {
        fun factory(app: KlangradarApp): ViewModelProvider.Factory = viewModelFactory {
            initializer { SearchViewModel(requireNotNull(app.contentRepository)) }
        }
    }
}
