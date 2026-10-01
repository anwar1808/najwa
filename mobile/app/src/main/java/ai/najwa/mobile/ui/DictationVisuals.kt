package ai.najwa.mobile.ui

import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.sp
import ai.najwa.mobile.R
import kotlin.math.PI
import kotlin.math.sin

/** Amiri — a classical Naskh. Used for the nūn in the app and the launcher icon. */
val NaskhFamily = FontFamily(Font(R.font.amiri_regular))

/**
 * The macOS HUD waveform, ported: a scrolling sine carrier tapered at both ends
 * whose amplitude follows the mic level. [level] is 0…1.
 */
@Composable
fun WaveView(level: Float, modifier: Modifier = Modifier, color: Color = Color(0xFFF4F4F5)) {
    val t by rememberInfiniteTransition(label = "wave").animateFloat(
        0f, (2 * PI).toFloat(),
        infiniteRepeatable(tween(900, easing = LinearEasing), RepeatMode.Restart), label = "phase",
    )
    val amp = (0.07f + 0.93f * level.coerceIn(0f, 1f))
    Canvas(modifier) {
        val w = size.width; val h = size.height
        val inset = w * 0.08f
        val midY = h / 2; val maxAmp = h * 0.42f
        val cycles = 3.2f
        val path = Path()
        var x = inset; var first = true
        while (x <= w - inset) {
            val u = (x - inset) / (w - 2 * inset)
            val taper = sin(PI * u).toFloat()
            val y = midY + maxAmp * amp * taper * sin(cycles * 2 * PI * u - t).toFloat()
            if (first) { path.moveTo(x, y); first = false } else path.lineTo(x, y)
            x += 2f
        }
        drawPath(path, color, style = Stroke(width = 5f, cap = StrokeCap.Round, join = StrokeJoin.Round))
    }
}

/** The breathing nūn: opacity 0.55…1.0 and scale 0.92…1.06, one breath ≈ 1.3 s. */
@Composable
fun BreathingNun(modifier: Modifier = Modifier, size: Float = 64f) {
    val b by rememberInfiniteTransition(label = "breath").animateFloat(
        0f, 1f, infiniteRepeatable(tween(650, easing = LinearEasing), RepeatMode.Reverse), label = "b",
    )
    Box(modifier, contentAlignment = Alignment.Center) {
        Text(
            "ن", fontFamily = NaskhFamily, fontSize = size.sp, color = Color(0xFFF4F4F5),
            modifier = Modifier.graphicsLayer {
                alpha = 0.55f + 0.45f * b
                scaleX = 0.92f + 0.14f * b; scaleY = scaleX
            },
        )
    }
}
