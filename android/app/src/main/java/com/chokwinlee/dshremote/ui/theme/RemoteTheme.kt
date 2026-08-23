package com.chokwinlee.dshremote.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.Shapes
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

@Immutable
data class RemoteColors(
    val canvas: Color,
    val surface: Color,
    val raisedSurface: Color,
    val mutedSurface: Color,
    val userMessage: Color,
    val codeSurface: Color,
    val accent: Color,
    val accentFill: Color,
    val accentContent: Color,
    val success: Color,
    val warning: Color,
    val danger: Color,
    val reasoning: Color,
    val tool: Color,
    val hairline: Color,
    val strongHairline: Color,
)

private val LightRemoteColors = RemoteColors(
    // These roles intentionally match RemoteDesignSystem.swift on iOS.
    canvas = Color(0xFFF9FAFB),
    surface = Color(0xFFFFFFFF),
    raisedSurface = Color(0xFFF6F7F9),
    mutedSurface = Color(0xFFF1F3F6),
    userMessage = Color(0xFFEDF3FE),
    codeSurface = Color(0xFFF1F3F6),
    accent = Color(0xFF2E5CBF),
    accentFill = Color(0xFF2E5CBF),
    accentContent = Color(0xFFF8FAFE),
    success = Color(0xFF0D7833),
    warning = Color(0xFF944F00),
    danger = Color(0xFFBA2929),
    reasoning = Color(0xFF664DBA),
    tool = Color(0xFF9E470A),
    hairline = Color(0x13000000),
    strongHairline = Color(0x1F000000),
)

private val DarkRemoteColors = RemoteColors(
    canvas = Color(0xFF151517),
    surface = Color(0xFF232324),
    raisedSurface = Color(0xFF2C2C2E),
    mutedSurface = Color(0xFF353638),
    userMessage = Color(0xFF2C2C2E),
    codeSurface = Color(0xFF0F0F11),
    accent = Color(0xFF679EFE),
    accentFill = Color(0xFF3D6FCC),
    accentContent = Color(0xFFF6F8FC),
    success = Color(0xFF21C45E),
    warning = Color(0xFFF59E0A),
    danger = Color(0xFFF25959),
    reasoning = Color(0xFF8C7DF5),
    tool = Color(0xFFEB8C40),
    hairline = Color(0x17FFFFFF),
    strongHairline = Color(0x24FFFFFF),
)

private val LocalRemoteColors = staticCompositionLocalOf { LightRemoteColors }

object RemoteTheme {
    val colors: RemoteColors
        @Composable get() = LocalRemoteColors.current
}

object RemoteDimens {
    val space4 = 4.dp
    val space6 = 6.dp
    val space8 = 8.dp
    val space12 = 12.dp
    val space16 = 16.dp
    val space20 = 20.dp
    val space24 = 24.dp
    val pagePadding = 16.dp
    val sectionSpacing = 22.dp
    val rowRadius = 14.dp
    val controlRadius = 13.dp
    val focusedRadius = 20.dp
    val composerRadius = 22.dp
    val minimumTouchTarget = 48.dp
    val toolbarTouchTarget = 44.dp
    val compactRowHeight = 56.dp
}

private val RemoteTypography = Typography(
    headlineSmall = TextStyle(
        fontFamily = FontFamily.Default,
        fontWeight = FontWeight.SemiBold,
        fontSize = 22.sp,
        lineHeight = 28.sp,
        letterSpacing = (-0.18).sp,
    ),
    titleLarge = TextStyle(
        fontFamily = FontFamily.Default,
        fontWeight = FontWeight.SemiBold,
        fontSize = 20.sp,
        lineHeight = 26.sp,
        letterSpacing = (-0.10).sp,
    ),
    titleMedium = TextStyle(
        fontFamily = FontFamily.Default,
        fontWeight = FontWeight.SemiBold,
        fontSize = 16.sp,
        lineHeight = 22.sp,
    ),
    bodyLarge = TextStyle(
        fontFamily = FontFamily.Default,
        fontWeight = FontWeight.Normal,
        fontSize = 16.sp,
        lineHeight = 23.sp,
    ),
    bodyMedium = TextStyle(
        fontFamily = FontFamily.Default,
        fontWeight = FontWeight.Normal,
        fontSize = 14.sp,
        lineHeight = 20.sp,
    ),
    bodySmall = TextStyle(
        fontFamily = FontFamily.Default,
        fontWeight = FontWeight.Normal,
        fontSize = 13.sp,
        lineHeight = 18.sp,
    ),
    labelLarge = TextStyle(
        fontFamily = FontFamily.Default,
        fontWeight = FontWeight.Medium,
        fontSize = 14.sp,
        lineHeight = 20.sp,
    ),
    labelMedium = TextStyle(
        fontFamily = FontFamily.Default,
        fontWeight = FontWeight.Medium,
        fontSize = 12.sp,
        lineHeight = 17.sp,
        letterSpacing = 0.05.sp,
    ),
    labelSmall = TextStyle(
        fontFamily = FontFamily.Default,
        fontWeight = FontWeight.Normal,
        fontSize = 11.sp,
        lineHeight = 15.sp,
        letterSpacing = 0.10.sp,
    ),
)

private val RemoteShapes = Shapes(
    extraSmall = androidx.compose.foundation.shape.RoundedCornerShape(6.dp),
    small = androidx.compose.foundation.shape.RoundedCornerShape(8.dp),
    medium = androidx.compose.foundation.shape.RoundedCornerShape(12.dp),
    large = androidx.compose.foundation.shape.RoundedCornerShape(18.dp),
    extraLarge = androidx.compose.foundation.shape.RoundedCornerShape(22.dp),
)

private fun materialLightScheme(colors: RemoteColors) = lightColorScheme(
    primary = colors.accent,
    onPrimary = Color(0xFFF8FAFE),
    primaryContainer = colors.userMessage,
    onPrimaryContainer = Color(0xFF17325E),
    secondary = Color(0xFF58677B),
    onSecondary = Color(0xFFF8FAFE),
    background = colors.canvas,
    onBackground = Color(0xFF1A1F26),
    surface = colors.surface,
    onSurface = Color(0xFF1A1F26),
    surfaceVariant = colors.raisedSurface,
    onSurfaceVariant = Color(0xFF626B78),
    outline = colors.strongHairline,
    outlineVariant = colors.hairline,
    error = colors.danger,
    onError = Color(0xFFFFF8F7),
)

private fun materialDarkScheme(colors: RemoteColors) = darkColorScheme(
    primary = colors.accent,
    onPrimary = Color(0xFF101B2C),
    primaryContainer = colors.accentFill,
    onPrimaryContainer = Color(0xFFF3F6FB),
    secondary = Color(0xFFB3BECD),
    onSecondary = Color(0xFF202B39),
    background = colors.canvas,
    onBackground = Color(0xFFE8ECF2),
    surface = colors.surface,
    onSurface = Color(0xFFE8ECF2),
    surfaceVariant = colors.raisedSurface,
    onSurfaceVariant = Color(0xFFAAB3C0),
    outline = colors.strongHairline,
    outlineVariant = colors.hairline,
    error = colors.danger,
    onError = Color(0xFF321415),
)

@Composable
fun DSHRemoteTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    content: @Composable () -> Unit,
) {
    val remoteColors = if (darkTheme) DarkRemoteColors else LightRemoteColors
    androidx.compose.runtime.CompositionLocalProvider(LocalRemoteColors provides remoteColors) {
        MaterialTheme(
            colorScheme = if (darkTheme) {
                materialDarkScheme(remoteColors)
            } else {
                materialLightScheme(remoteColors)
            },
            typography = RemoteTypography,
            shapes = RemoteShapes,
        ) {
            androidx.compose.runtime.CompositionLocalProvider(
                LocalContentColor provides MaterialTheme.colorScheme.onSurface,
                content = content,
            )
        }
    }
}
