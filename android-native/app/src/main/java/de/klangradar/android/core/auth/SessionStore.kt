package de.klangradar.android.core.auth

import android.content.Context
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import de.klangradar.android.core.network.SupabaseJson

/**
 * Keystore-backed encrypted persistence for the Supabase session — the
 * Android equivalent of ios-native's KeychainStore.swift (same
 * "de.klangradar" service naming, same single-entry semantics).
 */
class SessionStore(context: Context) {
    private val masterKey = MasterKey.Builder(context)
        .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
        .build()

    private val prefs = EncryptedSharedPreferences.create(
        context,
        "de.klangradar.session",
        masterKey,
        EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
        EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
    )

    fun save(session: AuthSession) {
        prefs.edit().putString(KEY, SupabaseJson.encodeToString(AuthSession.serializer(), session)).apply()
    }

    fun load(): AuthSession? {
        val raw = prefs.getString(KEY, null) ?: return null
        return runCatching { SupabaseJson.decodeFromString(AuthSession.serializer(), raw) }.getOrNull()
    }

    fun clear() {
        prefs.edit().remove(KEY).apply()
    }

    private companion object {
        const val KEY = "supabase-session"
    }
}
