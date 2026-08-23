package de.klangradar.android.domain.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class GenreRow(val id: String, @SerialName("label_de") val labelDe: String? = null)

data class GenreOption(val id: String, val label: String)
