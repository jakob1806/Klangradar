package de.klangradar.android.domain.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/** Row shape from `user_favorite_persons`/`_ensembles`/`_venues`, embedding
 *  the entity itself — mirrors ios-native's FollowedEntity/UserRepository
 *  follow queries (`select=notify_new_events, persons(id, full_name, slug)`
 *  and equivalents for ensembles/venues). */
@Serializable
data class FollowRow(
    @SerialName("notify_new_events") val notifyNewEvents: Boolean = true,
    val persons: FollowedEntityRef? = null,
    val ensembles: FollowedEntityRef? = null,
    val venues: FollowedEntityRef? = null
)

@Serializable
data class FollowedEntityRef(
    val id: String,
    @SerialName("full_name") val fullName: String? = null,
    val name: String? = null,
    val slug: String? = null
) {
    val displayName: String get() = fullName ?: name ?: "—"
}

data class FollowedEntity(val id: String, val name: String, val slug: String?, val notifyNewEvents: Boolean)
