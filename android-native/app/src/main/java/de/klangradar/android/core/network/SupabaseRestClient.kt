package de.klangradar.android.core.network

import de.klangradar.android.core.config.ApiConfig
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.JsonElement
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.HttpUrl.Companion.toHttpUrl
import java.util.concurrent.TimeUnit

class SupabaseException(val statusCode: Int, message: String) : Exception(message)

/**
 * Thin PostgREST/GoTrue HTTP client — deliberately manual (no supabase-kt
 * SDK dependency), mirroring ios-native's own hand-rolled
 * SupabaseRESTClient.swift so both native clients share the exact same
 * request shape (query params, RPC body shape, auth headers) and are easy
 * to compare side by side.
 */
class SupabaseRestClient(private val config: ApiConfig) {
    private val jsonMediaType = "application/json".toMediaType()
    private val http = OkHttpClient.Builder()
        .connectTimeout(15, TimeUnit.SECONDS)
        .readTimeout(20, TimeUnit.SECONDS)
        .build()

    /** GET against `/rest/v1/{table}`. `accessToken` falls back to the anon key. */
    suspend fun get(table: String, queryItems: List<Pair<String, String>>, accessToken: String? = null): String {
        val urlBuilder = "${config.baseUrl}/rest/v1/$table".toHttpUrl().newBuilder()
        for ((key, value) in queryItems) urlBuilder.addQueryParameter(key, value)
        val request = Request.Builder()
            .url(urlBuilder.build())
            .get()
            .authHeaders(accessToken)
            .build()
        return execute(request)
    }

    /** POST against `/rest/v1/rpc/{function}` with a JSON object body. */
    suspend fun rpc(function: String, body: JsonElement, accessToken: String? = null): String {
        val request = Request.Builder()
            .url("${config.baseUrl}/rest/v1/rpc/$function")
            .post(body.toString().toRequestBody(jsonMediaType))
            .authHeaders(accessToken)
            .build()
        return execute(request)
    }

    /** POST against `/auth/v1/{path}` (signup, token, logout, recover, resend, ...). */
    suspend fun auth(path: String, body: JsonElement?, accessToken: String? = null): String {
        val builder = Request.Builder().url("${config.baseUrl}/auth/v1/$path")
        if (body != null) {
            builder.post(body.toString().toRequestBody(jsonMediaType))
        } else {
            builder.post("".toRequestBody(jsonMediaType))
        }
        builder.authHeaders(accessToken)
        return execute(builder.build())
    }

    private fun Request.Builder.authHeaders(accessToken: String?): Request.Builder {
        header("apikey", config.anonKey)
        header("Authorization", "Bearer ${accessToken ?: config.anonKey}")
        header("Content-Type", "application/json")
        return this
    }

    private suspend fun execute(request: Request): String = withContext(Dispatchers.IO) {
        http.newCall(request).execute().use { response ->
            val bodyString = response.body?.string().orEmpty()
            if (!response.isSuccessful) {
                throw SupabaseException(response.code, bodyString.ifBlank { response.message })
            }
            bodyString
        }
    }
}
