package de.klangradar.android.data.repository

import de.klangradar.android.core.network.SupabaseJson
import de.klangradar.android.core.network.SupabaseRestClient
import de.klangradar.android.domain.model.EntityDetail
import de.klangradar.android.domain.model.EntityKind
import de.klangradar.android.domain.model.LinkedEvent
import de.klangradar.android.domain.model.SearchHit
import de.klangradar.android.domain.model.SearchHitRow
import de.klangradar.android.domain.model.VenueLocation
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import java.util.UUID

/** Mirrors ios-native's ContentRepository (search_all/venues_with_latlng
 *  RPCs, and the person/ensemble/venue/work `detail` lookup). */
class ContentRepository(private val client: SupabaseRestClient) {
    private val hitRowSerializer = ListSerializer(SearchHitRow.serializer())
    private val venueSerializer = ListSerializer(VenueLocation.serializer())
    private val idOnlySerializer = ListSerializer(IdOnly.serializer())

    suspend fun search(query: String, limit: Int = 20): List<SearchHit> {
        val body = buildJsonObject {
            put("q", query)
            put("result_limit", limit)
        }
        val raw = client.rpc("search_all", body)
        val rows = SupabaseJson.decodeFromString(hitRowSerializer, raw)

        // Ensembles can be resolution placeholders/duplicate-merge family
        // roots that shouldn't surface in search — same extra visibility
        // check ios-native's ContentRepository.search performs.
        val ensembleIds = rows.filter { it.resultType == EntityKind.ENSEMBLE.apiValue }.map { it.id }
        val visibleEnsembleIds: Set<String> = if (ensembleIds.isEmpty()) {
            emptySet()
        } else {
            runCatching {
                val visibleRaw = client.get(
                    table = "ensembles",
                    queryItems = listOf(
                        "select" to "id",
                        "id" to "in.(${ensembleIds.joinToString(",")})",
                        "is_resolution_placeholder" to "eq.false",
                        "is_family_root" to "eq.false"
                    )
                )
                SupabaseJson.decodeFromString(idOnlySerializer, visibleRaw).map { it.id }.toSet()
            }.getOrDefault(ensembleIds.toSet())
        }

        return rows.mapNotNull { row ->
            val title = row.title ?: return@mapNotNull null
            val kind = EntityKind.fromApiValue(row.resultType)
            if (kind == EntityKind.ENSEMBLE && row.id !in visibleEnsembleIds) return@mapNotNull null
            SearchHit(id = row.id, kind = kind, slug = row.slug, title = title, subtitle = row.subtitle)
        }
    }

    suspend fun venueLocations(): List<VenueLocation> {
        val raw = client.rpc("venues_with_latlng", buildJsonObject { })
        return SupabaseJson.decodeFromString(venueSerializer, raw)
    }

    /** Fetches one entity's detail page — table/select per kind mirrors
     *  ios-native's ContentRepository.detail (composer join for works;
     *  no member_of/parent-ensemble joins yet, see MIGRATION_STATUS.md). */
    suspend fun detail(kind: EntityKind, identifier: String): EntityDetail? {
        val table = tableFor(kind)
        val select = if (kind == EntityKind.WORK) "*,composer:persons(id,slug,full_name)" else "*"
        val idColumn = if (kind == EntityKind.WORK || isUuid(identifier)) "id" else "slug"

        val raw = client.get(
            table = table,
            queryItems = listOf("select" to select, idColumn to "eq.$identifier", "limit" to "1")
        )
        val row = SupabaseJson.parseToJsonElement(raw).jsonArray.firstOrNull()?.jsonObject ?: return null
        val id = row["id"].stringOrNull() ?: return null

        val events = runCatching { linkedEvents(kind, id) }.getOrDefault(emptyList())
        val latLng = if (kind == EntityKind.VENUE) runCatching { venueLatLng(id) }.getOrNull() else null

        return EntityDetail(
            id = id,
            kind = kind,
            slug = row["slug"].stringOrNull(),
            title = titleFrom(row, kind),
            subtitle = subtitleFrom(row, kind),
            primaryImageUrl = row["photo_url"].stringOrNull() ?: row["image_url"].stringOrNull(),
            descriptionDe = row["description_de"].stringOrNull() ?: row["biography_de"].stringOrNull(),
            websiteUrl = row["website_url"].stringOrNull(),
            addressCity = row["address_city"].stringOrNull(),
            events = events,
            venueLat = latLng?.first,
            venueLng = latLng?.second
        )
    }

    private suspend fun venueLatLng(venueId: String): Pair<Double, Double>? {
        val raw = client.rpc("venue_with_latlng", buildJsonObject { put("p_id", venueId) })
        val row = SupabaseJson.parseToJsonElement(raw).jsonArray.firstOrNull()?.jsonObject ?: return null
        val lat = (row["lat"] as? JsonPrimitive)?.content?.toDoubleOrNull() ?: return null
        val lng = (row["lng"] as? JsonPrimitive)?.content?.toDoubleOrNull() ?: return null
        return lat to lng
    }

    private suspend fun linkedEvents(kind: EntityKind, entityId: String): List<LinkedEvent> {
        val eventSelect = "id,slug,title,start_datetime,image_urls,venues(id,name,photo_url)"
        val rows: List<JsonObject> = when (kind) {
            EntityKind.VENUE -> {
                val raw = client.get(
                    table = "events",
                    queryItems = listOf(
                        "select" to eventSelect,
                        "venue_id" to "eq.$entityId",
                        "status" to "neq.draft",
                        "order" to "start_datetime.asc"
                    )
                )
                SupabaseJson.parseToJsonElement(raw).jsonArray.map { it.jsonObject }
            }
            EntityKind.PERSON, EntityKind.ENSEMBLE -> {
                val table = "event_participants"
                val filterColumn = if (kind == EntityKind.PERSON) "person_id" else "ensemble_id"
                val raw = client.get(
                    table = table,
                    queryItems = listOf("select" to "events($eventSelect)", filterColumn to "eq.$entityId")
                )
                SupabaseJson.parseToJsonElement(raw).jsonArray.mapNotNull { (it.jsonObject["events"] as? JsonObject) }
            }
            EntityKind.WORK -> {
                val raw = client.get(
                    table = "event_works",
                    queryItems = listOf("select" to "events($eventSelect)", "work_id" to "eq.$entityId")
                )
                SupabaseJson.parseToJsonElement(raw).jsonArray.mapNotNull { (it.jsonObject["events"] as? JsonObject) }
            }
        }
        return rows.mapNotNull { row ->
            val id = row["id"].stringOrNull() ?: return@mapNotNull null
            val slug = row["slug"].stringOrNull() ?: return@mapNotNull null
            val title = row["title"].stringOrNull() ?: return@mapNotNull null
            val venue = row["venues"] as? JsonObject
            val imageUrl = (row["image_urls"] as? kotlinx.serialization.json.JsonArray)
                ?.firstOrNull()?.let { (it as? JsonPrimitive)?.content }
                ?: venue?.get("photo_url").stringOrNull()
            LinkedEvent(
                id = id,
                slug = slug,
                title = title,
                startDatetime = row["start_datetime"].stringOrNull(),
                imageUrl = imageUrl,
                venueName = venue?.get("name").stringOrNull()
            )
        }.sortedBy { it.startDatetime ?: "" }
    }

    private fun tableFor(kind: EntityKind) = when (kind) {
        EntityKind.PERSON -> "persons"
        EntityKind.ENSEMBLE -> "ensembles"
        EntityKind.VENUE -> "venues"
        EntityKind.WORK -> "works"
    }

    private fun titleFrom(row: JsonObject, kind: EntityKind): String = when (kind) {
        EntityKind.PERSON -> row["full_name"].stringOrNull() ?: "Unbekannte Person"
        else -> row["name"].stringOrNull() ?: row["title"].stringOrNull() ?: "Ohne Titel"
    }

    private fun subtitleFrom(row: JsonObject, kind: EntityKind): String? = when (kind) {
        EntityKind.VENUE -> row["address_city"].stringOrNull()
        EntityKind.WORK -> {
            val composer = (row["composer"] as? JsonObject)?.get("full_name").stringOrNull()
            val catalog = row["catalog_number"].stringOrNull()
            listOfNotNull(composer, catalog).joinToString(" · ").ifBlank { null }
        }
        else -> null
    }

    private fun isUuid(value: String): Boolean = runCatching { UUID.fromString(value) }.isSuccess

    private fun JsonElement?.stringOrNull(): String? {
        val primitive = this as? JsonPrimitive ?: return null
        if (primitive is JsonNull) return null
        return primitive.content
    }

    @Serializable
    private data class IdOnly(val id: String)
}
