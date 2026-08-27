package de.klangradar.android.core.util

import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter

/** Mirrors ios-native's FlexibleDateParser: handles both a bare Postgres
 *  `date` column (`yyyy-MM-dd`, no time) and a full ISO-8601 timestamp. */
object FlexibleDate {
    private val zone = ZoneId.of("Europe/Berlin")

    fun parseInstant(value: String?): Instant? {
        if (value.isNullOrBlank()) return null
        return runCatching { Instant.parse(value) }.getOrNull()
            ?: runCatching { LocalDate.parse(value).atStartOfDay(zone).toInstant() }.getOrNull()
    }

    fun localDate(value: String?): LocalDate? = parseInstant(value)?.atZone(zone)?.toLocalDate()

    fun formatDayHeader(date: LocalDate): String =
        date.format(DateTimeFormatter.ofPattern("EEEE, d. MMMM", java.util.Locale.GERMAN))

    fun formatTime(instant: Instant): String =
        instant.atZone(zone).format(DateTimeFormatter.ofPattern("HH:mm"))
}
