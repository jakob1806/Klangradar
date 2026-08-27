package de.klangradar.android.core.config

import de.klangradar.android.BuildConfig

/**
 * Mirrors ios-native's APIConfiguration: reads SUPABASE_URL/SUPABASE_ANON_KEY
 * (wired from local.properties into BuildConfig, see app/build.gradle.kts)
 * and falls back to `null` — never a crash — so the app can fall back to
 * preview/sample data when no backend is configured, same as
 * AppEnvironment.isUsingPreviewData on iOS.
 */
data class ApiConfig(val baseUrl: String, val anonKey: String) {
    companion object {
        fun load(): ApiConfig? {
            val url = BuildConfig.SUPABASE_URL.trim()
            val key = BuildConfig.SUPABASE_ANON_KEY.trim()
            if (url.isEmpty() || key.isEmpty()) return null
            if (!url.startsWith("http://") && !url.startsWith("https://")) return null
            return ApiConfig(baseUrl = url.trimEnd('/'), anonKey = key)
        }
    }
}
