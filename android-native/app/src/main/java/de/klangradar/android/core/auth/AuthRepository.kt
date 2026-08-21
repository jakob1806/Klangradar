package de.klangradar.android.core.auth

import de.klangradar.android.core.network.SupabaseJson
import de.klangradar.android.core.network.SupabaseRestClient
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

sealed interface AuthState {
    data object Unavailable : AuthState
    data object Loading : AuthState
    data class Anonymous(val session: AuthSession) : AuthState
    data class Authenticated(val session: AuthSession) : AuthState
    data class Failed(val message: String) : AuthState
}

/**
 * Mirrors ios-native's AuthService.swift session lifecycle, most
 * importantly the refresh-token request-deduplication fix for the
 * "permanent lockout after logout" bug (see ios-native/CLAUDE.md history):
 * concurrent callers awaiting a session while a refresh is already in
 * flight share the same in-flight request instead of each independently
 * consuming the same one-time refresh token, where the second caller would
 * otherwise get "Refresh Token Not Found" and fail permanently.
 */
class AuthRepository(
    private val client: SupabaseRestClient,
    private val sessionStore: SessionStore
) {
    private var cachedSession: AuthSession? = null
    private val refreshMutex = Mutex()
    private var refreshDeferred: Deferred<AuthSession>? = null

    suspend fun restoreOrCreateSession(): AuthSession {
        cachedSession?.let { if (it.hasComfortableValidity()) return it }

        val persisted = sessionStore.load()
        if (persisted != null && persisted.hasComfortableValidity()) {
            cachedSession = persisted
            return persisted
        }

        if (persisted != null) {
            val refreshed = runCatching { deduplicatedRefresh(persisted.refreshToken) }.getOrNull()
            if (refreshed != null) return refreshed
            // Refresh token already consumed/invalid — clear it and fall back
            // to an anonymous session instead of retrying the same dead
            // token forever (the exact bug that was fixed on iOS).
            cachedSession = null
            sessionStore.clear()
        }

        return signInAnonymously()
    }

    /** Only the first ("leader") caller performs the network call; concurrent
     *  followers await the same in-flight [Deferred] instead of racing the
     *  same one-time refresh token. */
    private suspend fun deduplicatedRefresh(refreshToken: String): AuthSession {
        var leader: CompletableDeferred<AuthSession>? = null
        val awaitable: Deferred<AuthSession> = refreshMutex.withLock {
            refreshDeferred ?: CompletableDeferred<AuthSession>().also {
                refreshDeferred = it
                leader = it
            }
        }

        val ownRequest = leader ?: return awaitable.await()

        try {
            val body = buildJsonObject { put("refresh_token", refreshToken) }
            val raw = client.auth("token?grant_type=refresh_token", body)
            val session = SupabaseJson.decodeFromString(AuthSession.serializer(), raw)
            persist(session)
            ownRequest.complete(session)
        } catch (t: Throwable) {
            ownRequest.completeExceptionally(t)
            throw t
        } finally {
            refreshMutex.withLock { refreshDeferred = null }
        }
        return ownRequest.await()
    }

    suspend fun signInAnonymously(): AuthSession {
        val raw = client.auth("signup", buildJsonObject { put("data", buildJsonObject { }) })
        val session = SupabaseJson.decodeFromString(AuthSession.serializer(), raw)
        persist(session)
        return session
    }

    suspend fun signUp(email: String, password: String): AuthSession {
        val body = buildJsonObject {
            put("email", email)
            put("password", password)
        }
        val raw = client.auth("signup", body)
        val session = SupabaseJson.decodeFromString(AuthSession.serializer(), raw)
        persist(session)
        return session
    }

    suspend fun signInWithPassword(email: String, password: String): AuthSession {
        val body = buildJsonObject {
            put("email", email)
            put("password", password)
        }
        val raw = client.auth("token?grant_type=password", body)
        val session = SupabaseJson.decodeFromString(AuthSession.serializer(), raw)
        persist(session)
        return session
    }

    suspend fun requestPasswordReset(email: String) {
        client.auth("recover", buildJsonObject { put("email", email) })
    }

    suspend fun signOut(): AuthSession {
        val token = cachedSession?.accessToken
        runCatching { client.auth("logout", null, accessToken = token) }
        cachedSession = null
        sessionStore.clear()
        // The app is never truly "logged out" — always at least anonymous,
        // same as RootTabView's post-sign-out behavior on iOS.
        return signInAnonymously()
    }

    private fun persist(session: AuthSession) {
        cachedSession = session
        sessionStore.save(session)
    }

    private fun AuthSession.hasComfortableValidity(): Boolean {
        val nowPlusMargin = System.currentTimeMillis() / 1000 + 60
        return expirationEpochSeconds > nowPlusMargin
    }
}
