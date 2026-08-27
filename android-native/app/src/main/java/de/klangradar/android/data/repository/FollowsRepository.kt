package de.klangradar.android.data.repository

import de.klangradar.android.core.network.SupabaseJson
import de.klangradar.android.core.network.SupabaseRestClient
import de.klangradar.android.domain.model.ConcertEvent
import de.klangradar.android.domain.model.FavoriteEventRow
import de.klangradar.android.domain.model.FavoriteIdRow
import de.klangradar.android.domain.model.FollowRow
import de.klangradar.android.domain.model.FollowedEntity
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

/** Which favorite-entity table/column a follow targets — mirrors
 *  ios-native's `UserRepository.interestStorage(_:)` mapping for the
 *  person/ensemble/venue cases (genre/work interests aren't exposed as
 *  "follows" in the UI on either client). */
enum class FollowKind(val table: String, val column: String) {
    PERSON("user_favorite_persons", "person_id"),
    ENSEMBLE("user_favorite_ensembles", "ensemble_id"),
    VENUE("user_favorite_venues", "venue_id")
}

/** Mirrors ios-native's FavoriteStore + FollowStore (event favorites, and
 *  person/ensemble/venue follows), backed by the same `favorites`/
 *  `user_favorite_*` tables. */
class FollowsRepository(private val client: SupabaseRestClient) {
    private val eventRowSerializer = ListSerializer(FavoriteEventRow.serializer())
    private val idRowSerializer = ListSerializer(FavoriteIdRow.serializer())
    private val followRowSerializer = ListSerializer(FollowRow.serializer())

    suspend fun favoriteEventIds(userId: String, token: String): Set<String> {
        val raw = client.get(
            table = "favorites",
            queryItems = listOf("select" to "event_id", "user_id" to "eq.$userId"),
            accessToken = token
        )
        return SupabaseJson.decodeFromString(idRowSerializer, raw).map { it.eventId }.toSet()
    }

    suspend fun favoriteEvents(userId: String, token: String): List<ConcertEvent> {
        val select = "events(id,slug,title,subtitle,start_datetime,image_urls,status,category,is_free," +
            "venues(id,name,photo_url),event_genres(genres(id,slug,label_de))," +
            "event_participants(persons(id,full_name,photo_url),ensembles(id,name,photo_url)))"
        val raw = client.get(
            table = "favorites",
            queryItems = listOf("select" to select, "user_id" to "eq.$userId"),
            accessToken = token
        )
        return SupabaseJson.decodeFromString(eventRowSerializer, raw).mapNotNull { it.events }
    }

    suspend fun setFavorite(eventId: String, isFavorite: Boolean, userId: String, token: String) {
        if (isFavorite) {
            val body = buildJsonObject {
                put("user_id", userId)
                put("event_id", eventId)
            }
            client.insert("favorites", body, accessToken = token)
        } else {
            client.delete(
                "favorites",
                filters = listOf("user_id" to "eq.$userId", "event_id" to "eq.$eventId"),
                accessToken = token
            )
        }
    }

    suspend fun followed(kind: FollowKind, userId: String, token: String): List<FollowedEntity> {
        val entityTable = when (kind) {
            FollowKind.PERSON -> "persons(id,full_name,slug)"
            FollowKind.ENSEMBLE -> "ensembles(id,name,slug)"
            FollowKind.VENUE -> "venues(id,name,slug)"
        }
        val raw = client.get(
            table = kind.table,
            queryItems = listOf("select" to "notify_new_events, $entityTable", "user_id" to "eq.$userId"),
            accessToken = token
        )
        val rows = SupabaseJson.decodeFromString(followRowSerializer, raw)
        return rows.mapNotNull { row ->
            val ref = when (kind) {
                FollowKind.PERSON -> row.persons
                FollowKind.ENSEMBLE -> row.ensembles
                FollowKind.VENUE -> row.venues
            } ?: return@mapNotNull null
            FollowedEntity(id = ref.id, name = ref.displayName, slug = ref.slug, notifyNewEvents = row.notifyNewEvents)
        }.sortedBy { it.name.lowercase() }
    }

    suspend fun setFollow(kind: FollowKind, entityId: String, selected: Boolean, userId: String, token: String) {
        if (selected) {
            val body = buildJsonObject {
                put("user_id", userId)
                put(kind.column, entityId)
            }
            client.insert(kind.table, body, accessToken = token)
        } else {
            client.delete(
                kind.table,
                filters = listOf("user_id" to "eq.$userId", kind.column to "eq.$entityId"),
                accessToken = token
            )
        }
    }

    suspend fun setNotify(kind: FollowKind, entityId: String, notify: Boolean, userId: String, token: String) {
        val body = buildJsonObject { put("notify_new_events", notify) }
        client.patch(
            kind.table,
            filters = listOf("user_id" to "eq.$userId", kind.column to "eq.$entityId"),
            values = body,
            accessToken = token
        )
    }
}
