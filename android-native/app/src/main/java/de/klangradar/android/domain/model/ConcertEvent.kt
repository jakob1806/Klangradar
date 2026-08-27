package de.klangradar.android.domain.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * Mirrors ios-native's ConcertEvent.swift field-for-field (exact snake_case
 * PostgREST/RPC keys) so both native clients decode the same backend
 * response shape identically — see android-native/CLAUDE.md for the
 * source-of-truth query (EventRepository.upcomingEvents).
 */
@Serializable
data class ConcertEvent(
    val id: String,
    val slug: String,
    val title: String,
    val subtitle: String? = null,
    @SerialName("start_datetime") val startDatetime: String? = null,
    @SerialName("venue_detail") val venueDetail: String? = null,
    @SerialName("image_urls") val imageUrls: List<String>? = null,
    val status: String? = null,
    val category: String? = null,
    @SerialName("is_free") val isFree: Boolean? = null,
    val venues: VenueSummary? = null,
    @SerialName("event_genres") val eventGenres: List<EventGenreEntry>? = null,
    @SerialName("event_participants") val eventParticipants: List<EventParticipant>? = null
) {
    val genreLabels: List<String>
        get() = eventGenres.orEmpty().mapNotNull { it.genres?.let { g -> g.labelDe ?: g.slug } }

    /** Priority: own image_urls → participant photo → venue photo — a
     *  simplified version of iOS's fuller gallery-fallback chain (which
     *  additionally layers in bulk-resolved gallery images; see
     *  MIGRATION_STATUS.md for what's not yet ported). */
    val primaryImageUrl: String?
        get() = imageUrls?.firstOrNull { it.isNotBlank() }
            ?: eventParticipants.orEmpty().firstNotNullOfOrNull { it.persons?.photoUrl ?: it.ensembles?.photoUrl }
            ?: venues?.photoUrl
}

@Serializable
data class VenueSummary(
    val id: String,
    val name: String,
    @SerialName("photo_url") val photoUrl: String? = null
)

@Serializable
data class EventGenreEntry(val genres: GenreSummary? = null)

@Serializable
data class GenreSummary(
    val id: String,
    val slug: String? = null,
    @SerialName("label_de") val labelDe: String? = null
)

@Serializable
data class EventParticipant(
    val persons: ParticipantPhoto? = null,
    val ensembles: ParticipantPhoto? = null
)

/** Persons expose `full_name`, ensembles expose `name` — both map onto
 *  [displayName] so calling code doesn't need to branch on which one. */
@Serializable
data class ParticipantPhoto(
    val id: String? = null,
    @SerialName("full_name") val fullName: String? = null,
    val name: String? = null,
    @SerialName("photo_url") val photoUrl: String? = null
) {
    val displayName: String? get() = fullName ?: name
}
