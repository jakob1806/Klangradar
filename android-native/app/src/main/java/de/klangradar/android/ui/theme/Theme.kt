package de.klangradar.android.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable

private val LightColors = lightColorScheme(
    primary = KlangradarAccent,
    onPrimary = KlangradarIce,
    background = LightBackground,
    surface = LightSurface,
    onBackground = KlangradarDeepInk,
    onSurface = KlangradarDeepInk
)

private val DarkColors = darkColorScheme(
    primary = KlangradarAccent,
    onPrimary = KlangradarIce,
    background = DarkBackground,
    surface = DarkSurface,
    onBackground = KlangradarIce,
    onSurface = KlangradarIce
)

@Composable
fun KlangradarTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    content: @Composable () -> Unit
) {
    MaterialTheme(
        colorScheme = if (darkTheme) DarkColors else LightColors,
        typography = KlangradarTypography,
        content = content
    )
}
