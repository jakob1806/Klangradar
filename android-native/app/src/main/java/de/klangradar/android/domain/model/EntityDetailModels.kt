package de.klangradar.android.domain.model

/** A concert event linked to an entity detail page (person/ensemble/venue/
 *  work) — mirrors ios-native's LinkedEvent, trimmed to what the Android
 *  detail screen actually renders. */
data class LinkedEvent(
    val id: String,
    val slug: String,
    val title: String,
    val startDatetime: String?,
    val imageUrl: String?,
    val venueName: String?
)

/** Mirrors ios-native's EntityDetail, trimmed for a first Android pass:
 *  no gallery/"similar items"/ensemble parent-child tree yet — see
 *  android-native/MIGRATION_STATUS.md. */
data class EntityDetail(
    val id: String,
    val kind: EntityKind,
    val slug: String?,
    val title: String,
    val subtitle: String?,
    val primaryImageUrl: String?,
    val descriptionDe: String?,
    val websiteUrl: String?,
    val addressCity: String?,
    val events: List<LinkedEvent>,
    val venueLat: Double? = null,
    val venueLng: Double? = null
)
