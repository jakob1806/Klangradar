package de.klangradar.android

import android.app.Application
import de.klangradar.android.core.auth.AuthRepository
import de.klangradar.android.core.auth.SessionStore
import de.klangradar.android.core.config.ApiConfig
import de.klangradar.android.core.network.SupabaseRestClient
import de.klangradar.android.data.repository.EventRepository
import de.klangradar.android.data.repository.UserRepository

/**
 * Manual, no-framework dependency container — mirrors ios-native's
 * AppEnvironment.swift (plain struct passed down through initializers)
 * rather than pulling in Hilt/Koin for this first foundation pass.
 *
 * [isUsingPreviewData] is true when no Supabase config is present (missing
 * local.properties), same fallback ios-native's AppEnvironment provides so
 * the app never crashes on a fresh checkout without secrets.
 */
class KlangradarApp : Application() {
    val config: ApiConfig? by lazy { ApiConfig.load() }
    val isUsingPreviewData: Boolean get() = config == null

    val restClient: SupabaseRestClient? by lazy { config?.let(::SupabaseRestClient) }
    val sessionStore: SessionStore by lazy { SessionStore(this) }
    val authRepository: AuthRepository? by lazy {
        restClient?.let { AuthRepository(it, sessionStore) }
    }
    val eventRepository: EventRepository? by lazy { restClient?.let(::EventRepository) }
    val userRepository: UserRepository? by lazy { restClient?.let(::UserRepository) }
}
