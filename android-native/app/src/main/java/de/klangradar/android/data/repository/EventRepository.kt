package de.klangradar.android.data.repository

import de.klangradar.android.core.network.SupabaseJson
import de.klangradar.android.core.network.SupabaseRestClient
import de.klangradar.android.domain.model.ConcertEvent
import kotlinx.serialization.builtins.ListSerializer
import java.time.Instant
import java.time.format.DateTimeFormatter

/** Matches ios-native's EventRepository.upcomingEvents exactly (same select
 *  columns/embeds, same status/start_datetime filters, same ordering). */
private const val EVENT_SELECT =
    "id,slug,title,subtitle,start_datetime,venue_detail,image_urls,status,category,is_free," +
        "venues(id,name,photo_url)," +
        "event_genres(genres(id,slug,label_de))," +
        "event_participants(persons(id,full_name,photo_url),ensembles(id,name,photo_url))"

class EventRepository(private val client: SupabaseRestClient) {
    private val listSerializer = ListSerializer(ConcertEvent.serializer())

    suspend fun upcomingEvents(limit: Int, offset: Int = 0, accessToken: String? = null): List<ConcertEvent> {
        val nowIso = DateTimeFormatter.ISO_INSTANT.format(Instant.now())
        val raw = client.get(
            table = "events",
            queryItems = listOf(
                "select" to EVENT_SELECT,
                "status" to "eq.scheduled",
                "start_datetime" to "gte.$nowIso",
                "order" to "start_datetime.asc",
                "limit" to limit.toString(),
                "offset" to offset.toString()
            ),
            accessToken = accessToken
        )
        return SupabaseJson.decodeFromString(listSerializer, raw)
    }
}
