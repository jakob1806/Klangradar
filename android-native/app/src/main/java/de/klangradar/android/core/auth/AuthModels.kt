package de.klangradar.android.core.auth

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/** Mirrors ios-native's AuthSession.swift field-for-field (snake_case wire format). */
@Serializable
data class AuthSession(
    @SerialName("access_token") val accessToken: String,
    @SerialName("refresh_token") val refreshToken: String,
    @SerialName("expires_in") val expiresIn: Long = 3600,
    @SerialName("expires_at") val expiresAt: Long? = null,
    @SerialName("token_type") val tokenType: String = "bearer",
    val user: AuthUser
) {
    /** Prefers the absolute `expires_at` (unix seconds) over `now + expires_in`. */
    val expirationEpochSeconds: Long
        get() = expiresAt ?: (System.currentTimeMillis() / 1000 + expiresIn)
}

@Serializable
data class AuthUser(
    val id: String,
    val email: String? = null,
    @SerialName("is_anonymous") val isAnonymous: Boolean? = null
)
