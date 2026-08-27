package de.klangradar.android.domain.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/** Mirrors ios-native's EntityKind (ContentModels.swift). */
enum class EntityKind(val apiValue: String) {
    PERSON("person"), ENSEMBLE("ensemble"), VENUE("venue"), WORK("work");

    companion object {
        fun fromApiValue(value: String?): EntityKind? = entries.firstOrNull { it.apiValue == value }
    }
}

/** One row from the `search_all` RPC (see ios-native's ContentRepository.search). */
@Serializable
data class SearchHitRow(
    val id: String,
    @SerialName("result_type") val resultType: String? = null,
    val slug: String? = null,
    val title: String? = null,
    val subtitle: String? = null
)

data class SearchHit(
    val id: String,
    val kind: EntityKind?,
    val slug: String?,
    val title: String,
    val subtitle: String?
)

/** One row from the `venues_with_latlng` RPC. */
@Serializable
data class VenueLocation(
    val id: String,
    val name: String,
    val slug: String? = null,
    val lat: Double,
    val lng: Double,
    @SerialName("address_city") val addressCity: String? = null
)
