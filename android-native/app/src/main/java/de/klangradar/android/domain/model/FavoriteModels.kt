package de.klangradar.android.domain.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/** One row from `favorites?select=events(...)` — PostgREST nests the
 *  joined event under `events`. */
@Serializable
data class FavoriteEventRow(val events: ConcertEvent? = null)

/** One row from `favorites?select=event_id`. */
@Serializable
data class FavoriteIdRow(@SerialName("event_id") val eventId: String)
