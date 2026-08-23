package de.klangradar.android.data.repository

import de.klangradar.android.core.network.SupabaseJson
import de.klangradar.android.core.network.SupabaseRestClient
import de.klangradar.android.domain.model.ConcertEvent
import de.klangradar.android.domain.model.GenreOption
import de.klangradar.android.domain.model.GenreRow
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.put

/**
 * Mirrors ios-native's UserRepository RPC-backed home modules
 * (`recommended_events`/`discovery_events`/`popular_events`, all taking a
 * single `p_result_limit` int param). `popular_events` doesn't require a
 * signed-in user; discovery/recommended are more useful once personalized,
 * but the RPCs themselves don't require an access token beyond the anon
 * key already sent by SupabaseRestClient.
 */
class UserRepository(private val client: SupabaseRestClient) {
    private val genreRowSerializer = ListSerializer(GenreRow.serializer())
    private val idOnlySerializer = ListSerializer(IdOnly.serializer())

    suspend fun genreOptions(): List<GenreOption> {
        val raw = client.get(table = "genres", queryItems = listOf("select" to "id,label_de", "order" to "sort_order.asc"))
        return SupabaseJson.decodeFromString(genreRowSerializer, raw)
            .mapNotNull { row -> row.labelDe?.let { GenreOption(id = row.id, label = it) } }
    }

    suspend fun selectedGenreIds(userId: String, token: String): Set<String> {
        val raw = client.get(
            table = "profile_interest_genres",
            queryItems = listOf("select" to "genre_id", "user_id" to "eq.$userId"),
            accessToken = token
        )
        return SupabaseJson.decodeFromString(idOnlySerializer, raw).map { it.genreId }.toSet()
    }

    suspend fun setGenreInterest(genreId: String, selected: Boolean, userId: String, token: String) {
        if (selected) {
            val body = buildJsonObject {
                put("user_id", userId)
                put("genre_id", genreId)
            }
            client.insert("profile_interest_genres", body, accessToken = token)
        } else {
            client.delete(
                "profile_interest_genres",
                filters = listOf("user_id" to "eq.$userId", "genre_id" to "eq.$genreId"),
                accessToken = token
            )
        }
    }

    @kotlinx.serialization.Serializable
    private data class IdOnly(@kotlinx.serialization.SerialName("genre_id") val genreId: String)

    suspend fun recommendedEvents(limit: Int, accessToken: String?): List<ConcertEvent> =
        homeEvents("recommended_events", limit, accessToken)

    suspend fun discoveryEvents(limit: Int, accessToken: String?): List<ConcertEvent> =
        homeEvents("discovery_events", limit, accessToken)

    suspend fun popularEvents(limit: Int, accessToken: String?): List<ConcertEvent> =
        homeEvents("popular_events", limit, accessToken)

    private suspend fun homeEvents(function: String, limit: Int, accessToken: String?): List<ConcertEvent> {
        val raw = client.rpc(function, buildJsonObject { put("p_result_limit", limit) }, accessToken)
        val rows = SupabaseJson.parseToJsonElement(raw).jsonArray
        return rows.map { row -> SupabaseJson.decodeFromJsonElement(ConcertEvent.serializer(), patchHomeEventRow(row.jsonObject)) }
    }

    /** These RPC rows nest `venues` without always populating its inner
     *  `id` (falls back to the row's own `venue_id`) and can omit `status`
     *  entirely — same normalization ios-native's UserRepository.homeEvents
     *  applies before constructing ConcertEvent. */
    private fun patchHomeEventRow(row: JsonObject): JsonObject {
        val venueId = row["venue_id"].stringOrNull()
        val venuesElement = row["venues"]
        val patchedVenues = if (venuesElement is JsonObject) {
            val innerId = venuesElement["id"].stringOrNull()
            if (innerId.isNullOrBlank() && !venueId.isNullOrBlank()) {
                JsonObject(venuesElement.toMutableMap().apply { put("id", JsonPrimitive(venueId)) })
            } else venuesElement
        } else venuesElement

        val patched = row.toMutableMap()
        if (patchedVenues != null) patched["venues"] = patchedVenues
        if (row["status"] == null || row["status"] is JsonNull) patched["status"] = JsonPrimitive("scheduled")
        return JsonObject(patched)
    }

    private fun JsonElement?.stringOrNull(): String? {
        val primitive = this as? JsonPrimitive ?: return null
        if (primitive is JsonNull) return null
        return primitive.content
    }
}
