package de.klangradar.android.core.network

import kotlinx.serialization.json.Json

/** Shared Json instance: tolerant of backend field additions (ignoreUnknownKeys). */
val SupabaseJson: Json = Json {
    ignoreUnknownKeys = true
    isLenient = true
    explicitNulls = false
}
