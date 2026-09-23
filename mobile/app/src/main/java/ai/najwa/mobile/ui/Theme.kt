package ai.najwa.mobile.ui

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

private val Scheme = darkColorScheme(
    primary = Color(0xFFF4F4F5),
    onPrimary = Color(0xFF0E0F12),
    secondary = Color(0xFF9CA3AF),
    background = Color(0xFF0E0F12),
    onBackground = Color(0xFFF4F4F5),
    surface = Color(0xFF16181D),
    onSurface = Color(0xFFF4F4F5),
    surfaceVariant = Color(0xFF1F2229),
    onSurfaceVariant = Color(0xFFB4B8C0),
    error = Color(0xFFFF7A7A),
)

@Composable
fun NajwaTheme(content: @Composable () -> Unit) {
    MaterialTheme(colorScheme = Scheme, content = content)
}
