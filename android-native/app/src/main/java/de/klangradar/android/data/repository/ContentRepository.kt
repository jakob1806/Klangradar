package de.klangradar.android.data.repository

import de.klangradar.android.core.network.SupabaseJson
import de.klangradar.android.core.network.SupabaseRestClient
import de.klangradar.android.domain.model.EntityKind
import de.klangradar.android.domain.model.SearchHit
import de.klangradar.android.domain.model.SearchHitRow
import de.klangradar.android.domain.model.VenueLocation
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

/** Mirrors ios-native's ContentRepository (search_all/venues_with_latlng RPCs). */
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

    @Serializable
    private data class IdOnly(val id: String)
}
