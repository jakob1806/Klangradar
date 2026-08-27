package de.klangradar.android.ui.map

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import de.klangradar.android.KlangradarApp
import de.klangradar.android.data.repository.ContentRepository
import de.klangradar.android.domain.model.VenueLocation
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

sealed interface MapUiState {
    data object Loading : MapUiState
    data class Failed(val message: String) : MapUiState
    data class Loaded(val venues: List<VenueLocation>) : MapUiState
}

/** No Google Maps API key is configured for this app yet (see
 *  android-native/CLAUDE.md), so this loads the same `venues_with_latlng`
 *  data ios-native's map uses but presents it as a list — each row opens
 *  the device's own Maps app via a `geo:` intent instead of an embedded
 *  interactive map. */
class MapViewModel(private val repository: ContentRepository) : ViewModel() {
    private val _uiState = MutableStateFlow<MapUiState>(MapUiState.Loading)
    val uiState: StateFlow<MapUiState> = _uiState.asStateFlow()

    init {
        refresh()
    }

    fun refresh() {
        viewModelScope.launch {
            _uiState.value = MapUiState.Loading
            try {
                _uiState.value = MapUiState.Loaded(
                    repository.venueLocations().sortedBy { it.name.lowercase() }
                )
            } catch (t: Throwable) {
                _uiState.value = MapUiState.Failed(t.message ?: "Unbekannter Fehler")
            }
        }
    }

    companion object {
        fun factory(app: KlangradarApp): ViewModelProvider.Factory = viewModelFactory {
            initializer { MapViewModel(requireNotNull(app.contentRepository)) }
        }
    }
}
