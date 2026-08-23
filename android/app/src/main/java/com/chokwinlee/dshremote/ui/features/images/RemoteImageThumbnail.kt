package com.chokwinlee.dshremote.ui.features.images

import android.graphics.BitmapFactory
import android.graphics.ImageDecoder
import android.os.Build
import androidx.core.net.toUri
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Image
import androidx.compose.material3.Icon
import androidx.compose.runtime.Composable
import androidx.compose.runtime.State
import androidx.compose.runtime.getValue
import androidx.compose.runtime.produceState
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.chokwinlee.dshremote.ui.theme.RemoteTheme
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/** Small best-effort URI preview; failures fall back to an icon and never block the conversation. */
@Composable
fun RemoteImageThumbnail(
    uri: String?,
    contentDescription: String?,
    modifier: Modifier = Modifier,
) {
    val bitmap by rememberUriBitmap(uri = uri, targetDimension = 320)
    Box(
        modifier = modifier
            .size(42.dp)
            .clip(RoundedCornerShape(9.dp))
            .background(RemoteTheme.colors.userMessage),
        contentAlignment = Alignment.Center,
    ) {
        if (bitmap != null) {
            Image(
                bitmap = bitmap!!.asImageBitmap(),
                contentDescription = contentDescription,
                modifier = Modifier.fillMaxSize(),
                contentScale = ContentScale.Crop,
            )
        } else {
            Icon(
                imageVector = Icons.Default.Image,
                contentDescription = contentDescription,
                tint = RemoteTheme.colors.accent,
                modifier = Modifier.size(20.dp),
            )
        }
    }
}

/** Bounded in-app image rendering used by message galleries and the full-screen preview. */
@Composable
fun RemoteImagePreview(
    uri: String?,
    contentDescription: String?,
    modifier: Modifier = Modifier,
    contentScale: ContentScale = ContentScale.Fit,
) {
    val bitmap by rememberUriBitmap(uri = uri, targetDimension = 1_600)
    Box(
        modifier = modifier.background(RemoteTheme.colors.codeSurface),
        contentAlignment = Alignment.Center,
    ) {
        if (bitmap != null) {
            Image(
                bitmap = bitmap!!.asImageBitmap(),
                contentDescription = contentDescription,
                modifier = Modifier.fillMaxSize(),
                contentScale = contentScale,
            )
        } else {
            Icon(
                imageVector = Icons.Default.Image,
                contentDescription = contentDescription,
                tint = RemoteTheme.colors.accent,
                modifier = Modifier.size(34.dp),
            )
        }
    }
}

@Composable
private fun rememberUriBitmap(
    uri: String?,
    targetDimension: Int,
): State<android.graphics.Bitmap?> {
    val context = LocalContext.current
    return produceState(initialValue = null, uri, targetDimension) {
        value = if (uri.isNullOrBlank()) null else withContext(Dispatchers.IO) {
            runCatching {
                val parsed = uri.toUri()
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                    ImageDecoder.decodeBitmap(
                        ImageDecoder.createSource(context.contentResolver, parsed),
                    ) { decoder, info, _ ->
                        val sample = (
                            maxOf(info.size.width, info.size.height) / targetDimension
                        ).coerceAtLeast(1)
                        decoder.setTargetSampleSize(sample)
                    }
                } else {
                    context.contentResolver.openInputStream(parsed)?.use(BitmapFactory::decodeStream)
                }
            }.getOrNull()
        }
    }
}
