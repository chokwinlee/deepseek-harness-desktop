package com.chokwinlee.dshremote.platform.images

import android.content.ContentResolver
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Matrix
import android.net.Uri
import androidx.core.graphics.createBitmap
import androidx.core.graphics.scale
import androidx.exifinterface.media.ExifInterface
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.InputStream
import kotlin.math.ceil
import kotlin.math.floor
import kotlin.math.min
import kotlin.math.roundToInt
import kotlin.math.sqrt
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

data class PhotoPreparationLimits(
    val maxInputBytes: Int = 25 * 1024 * 1024,
    val maxOutputBytes: Int,
    val maxPixels: Int,
    val maxDimension: Int,
    val allowedMediaTypes: Set<String> = setOf("image/jpeg", "image/png"),
) {
    init {
        require(maxInputBytes in 1..HARD_MAX_INPUT_BYTES)
        require(maxOutputBytes in 1..HARD_MAX_OUTPUT_BYTES)
        require(maxPixels in 1..HARD_MAX_DECODE_PIXELS)
        require(maxDimension in 1..HARD_MAX_DECODE_DIMENSION)
        require(allowedMediaTypes.isNotEmpty())
    }

    companion object {
        const val HARD_MAX_INPUT_BYTES = 50 * 1024 * 1024
        const val HARD_MAX_OUTPUT_BYTES = 25 * 1024 * 1024
        const val HARD_MAX_DECODE_PIXELS = 16_777_216
        const val HARD_MAX_DECODE_DIMENSION = 8_192
    }
}

data class PreparedPhotoInput(
    val bytes: ByteArray,
    val mediaType: String,
    val width: Int,
    val height: Int,
    val displayName: String?,
)

enum class PhotoPreparationError {
    UNREADABLE_INPUT,
    INPUT_TOO_LARGE,
    INVALID_IMAGE,
    SOURCE_DIMENSIONS_UNSAFE,
    UNSUPPORTED_OUTPUT_TYPE,
    OUTPUT_TOO_LARGE,
}

class PhotoPreparationException(
    val reason: PhotoPreparationError,
    cause: Throwable? = null,
) : IllegalArgumentException(reason.name, cause)

/**
 * Bounded Photo Picker input pipeline.
 *
 * The original file is never forwarded. It is read with a byte cap, decoded with
 * a sampling bound, oriented, resized and newly encoded. New encoding strips EXIF,
 * GPS, filenames embedded by containers, and other source metadata.
 */
class PhotoInputProcessor(
    private val contentResolver: ContentResolver,
) {
    suspend fun prepare(
        uri: Uri,
        limits: PhotoPreparationLimits,
        displayName: String? = null,
    ): PreparedPhotoInput = withContext(Dispatchers.Default) {
        val source = try {
            contentResolver.openInputStream(uri)?.use {
                readAtMost(it, limits.maxInputBytes)
            }
        } catch (error: PhotoPreparationException) {
            throw error
        } catch (error: Exception) {
            throw PhotoPreparationException(PhotoPreparationError.UNREADABLE_INPUT, error)
        } ?: throw PhotoPreparationException(PhotoPreparationError.UNREADABLE_INPUT)

        val bounds = BitmapFactory.Options().also { it.inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(source, 0, source.size, bounds)
        val sourceDimensions = ImagePreflight.validateSourceDimensions(bounds.outWidth, bounds.outHeight)
        val sampleSize = ImagePreflight.calculateInSampleSize(sourceDimensions, limits)
        val decodeOptions = BitmapFactory.Options().apply {
            inPreferredConfig = Bitmap.Config.ARGB_8888
            inSampleSize = sampleSize
        }
        var working = BitmapFactory.decodeByteArray(source, 0, source.size, decodeOptions)
            ?: throw PhotoPreparationException(PhotoPreparationError.INVALID_IMAGE)

        try {
            val orientation = readOrientation(source)
            replaceBitmap(working, applyOrientation(working, orientation)).also { working = it }
            val target = ImagePreflight.targetDimensions(working.width, working.height, limits)
            if (target.width != working.width || target.height != working.height) {
                replaceBitmap(
                    working,
                    working.scale(target.width, target.height),
                ).also { working = it }
            }

            val encoded = encodeWithinLimits(working, limits) { replacement ->
                replaceBitmap(working, replacement).also { working = it }
            }
            PreparedPhotoInput(
                bytes = encoded.bytes,
                mediaType = encoded.mediaType,
                width = working.width,
                height = working.height,
                displayName = sanitizeDisplayName(displayName),
            )
        } finally {
            if (!working.isRecycled) working.recycle()
        }
    }

    private fun encodeWithinLimits(
        initial: Bitmap,
        limits: PhotoPreparationLimits,
        replaceWorkingBitmap: (Bitmap) -> Unit,
    ): EncodedImage {
        var current = initial
        val allowed = limits.allowedMediaTypes.map(::normalizeMediaType).toSet()
        val canJpeg = "image/jpeg" in allowed
        val canPng = "image/png" in allowed
        if (!canJpeg && !canPng) {
            throw PhotoPreparationException(PhotoPreparationError.UNSUPPORTED_OUTPUT_TYPE)
        }

        repeat(MAX_RESIZE_PASSES) {
            if (canPng && (current.hasAlpha() || !canJpeg)) {
                compress(current, Bitmap.CompressFormat.PNG, 100, limits.maxOutputBytes)?.let { bytes ->
                    if (bytes.size <= limits.maxOutputBytes) return EncodedImage(bytes, "image/png")
                }
            }

            if (canJpeg) {
                val jpegSource = if (current.hasAlpha()) flattenOntoWhite(current) else current
                try {
                    for (quality in JPEG_QUALITIES) {
                        compress(
                            jpegSource,
                            Bitmap.CompressFormat.JPEG,
                            quality,
                            limits.maxOutputBytes,
                        )?.let { bytes ->
                            if (bytes.size <= limits.maxOutputBytes) {
                                return EncodedImage(bytes, "image/jpeg")
                            }
                        }
                    }
                } finally {
                    if (jpegSource !== current && !jpegSource.isRecycled) jpegSource.recycle()
                }
            }

            if (current.width <= MIN_OUTPUT_DIMENSION || current.height <= MIN_OUTPUT_DIMENSION) {
                throw PhotoPreparationException(PhotoPreparationError.OUTPUT_TOO_LARGE)
            }
            val next = ImagePreflight.shrink(current.width, current.height, RESIZE_FACTOR)
            val resized = current.scale(next.width, next.height)
            if (resized === current) {
                throw PhotoPreparationException(PhotoPreparationError.OUTPUT_TOO_LARGE)
            }
            replaceWorkingBitmap(resized)
            current = resized
        }
        throw PhotoPreparationException(PhotoPreparationError.OUTPUT_TOO_LARGE)
    }

    private fun applyOrientation(bitmap: Bitmap, orientation: Int): Bitmap {
        val matrix = Matrix()
        when (orientation) {
            ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> matrix.setScale(-1f, 1f)
            ExifInterface.ORIENTATION_ROTATE_180 -> matrix.setRotate(180f)
            ExifInterface.ORIENTATION_FLIP_VERTICAL -> {
                matrix.setRotate(180f)
                matrix.postScale(-1f, 1f)
            }
            ExifInterface.ORIENTATION_TRANSPOSE -> {
                matrix.setRotate(90f)
                matrix.postScale(-1f, 1f)
            }
            ExifInterface.ORIENTATION_ROTATE_90 -> matrix.setRotate(90f)
            ExifInterface.ORIENTATION_TRANSVERSE -> {
                matrix.setRotate(-90f)
                matrix.postScale(-1f, 1f)
            }
            ExifInterface.ORIENTATION_ROTATE_270 -> matrix.setRotate(-90f)
            else -> return bitmap
        }
        return Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true)
    }

    private fun readOrientation(source: ByteArray): Int = runCatching {
        ExifInterface(ByteArrayInputStream(source)).getAttributeInt(
            ExifInterface.TAG_ORIENTATION,
            ExifInterface.ORIENTATION_NORMAL,
        )
    }.getOrDefault(ExifInterface.ORIENTATION_NORMAL)

    private fun flattenOntoWhite(bitmap: Bitmap): Bitmap = createBitmap(
        bitmap.width,
        bitmap.height,
        Bitmap.Config.ARGB_8888,
    ).also { flattened ->
        Canvas(flattened).apply {
            drawColor(Color.WHITE)
            drawBitmap(bitmap, 0f, 0f, null)
        }
        flattened.setHasAlpha(false)
    }

    private fun compress(
        bitmap: Bitmap,
        format: Bitmap.CompressFormat,
        quality: Int,
        maxBytes: Int,
    ): ByteArray? {
        val output = CappedByteArrayOutputStream(maxBytes)
        return try {
            if (bitmap.compress(format, quality, output)) output.toByteArray() else null
        } catch (_: OutputLimitReachedException) {
            null
        }
    }

    private fun replaceBitmap(previous: Bitmap, replacement: Bitmap): Bitmap {
        if (replacement !== previous && !previous.isRecycled) previous.recycle()
        return replacement
    }

    private fun readAtMost(input: InputStream, maxBytes: Int): ByteArray {
        val output = ByteArrayOutputStream(min(maxBytes, DEFAULT_BUFFER_CAPACITY))
        val buffer = ByteArray(DEFAULT_BUFFER_CAPACITY)
        var total = 0
        while (true) {
            val read = try {
                input.read(buffer)
            } catch (error: Exception) {
                throw PhotoPreparationException(PhotoPreparationError.UNREADABLE_INPUT, error)
            }
            if (read < 0) break
            total += read
            if (total > maxBytes) {
                throw PhotoPreparationException(PhotoPreparationError.INPUT_TOO_LARGE)
            }
            output.write(buffer, 0, read)
        }
        return output.toByteArray()
    }

    private data class EncodedImage(val bytes: ByteArray, val mediaType: String)

    companion object {
        private val JPEG_QUALITIES = intArrayOf(90, 82, 72, 62, 52, 42)
        private const val MAX_RESIZE_PASSES = 10
        private const val RESIZE_FACTOR = 0.82
        private const val MIN_OUTPUT_DIMENSION = 64
        private const val DEFAULT_BUFFER_CAPACITY = 16 * 1024

        internal fun normalizeMediaType(mediaType: String): String = when (mediaType.lowercase()) {
            "image/jpg" -> "image/jpeg"
            else -> mediaType.lowercase()
        }

        internal fun sanitizeDisplayName(displayName: String?): String? = displayName
            ?.map { character -> if (character.isISOControl()) '/' else character }
            ?.joinToString(separator = "")
            ?.substringAfterLast('/')
            ?.substringAfterLast('\\')
            ?.trim()
            ?.take(160)
            ?.takeIf(String::isNotEmpty)
    }
}

private class OutputLimitReachedException : RuntimeException()

private class CappedByteArrayOutputStream(
    private val maxBytes: Int,
) : ByteArrayOutputStream(min(maxBytes, 16 * 1024)) {
    override fun write(value: Int) {
        ensureCapacityFor(1)
        super.write(value)
    }

    override fun write(buffer: ByteArray, offset: Int, length: Int) {
        ensureCapacityFor(length)
        super.write(buffer, offset, length)
    }

    private fun ensureCapacityFor(additionalBytes: Int) {
        if (additionalBytes < 0 || count > maxBytes - additionalBytes) {
            throw OutputLimitReachedException()
        }
    }
}

data class ImageDimensions(val width: Int, val height: Int) {
    val pixels: Long get() = width.toLong() * height.toLong()
}

internal object ImagePreflight {
    private const val MAX_SOURCE_DIMENSION = 65_535
    private const val MAX_SOURCE_PIXELS = 300_000_000L

    fun validateSourceDimensions(width: Int, height: Int): ImageDimensions {
        if (width <= 0 || height <= 0) {
            throw PhotoPreparationException(PhotoPreparationError.INVALID_IMAGE)
        }
        val dimensions = ImageDimensions(width, height)
        if (width > MAX_SOURCE_DIMENSION || height > MAX_SOURCE_DIMENSION || dimensions.pixels > MAX_SOURCE_PIXELS) {
            throw PhotoPreparationException(PhotoPreparationError.SOURCE_DIMENSIONS_UNSAFE)
        }
        return dimensions
    }

    fun calculateInSampleSize(source: ImageDimensions, limits: PhotoPreparationLimits): Int {
        var sample = 1
        while (sampledDimensions(source, sample).let { sampled ->
                sampled.width > limits.maxDimension ||
                    sampled.height > limits.maxDimension ||
                    sampled.pixels > limits.maxPixels
            }
        ) {
            if (sample >= 1 shl 16) break
            sample *= 2
        }
        return sample
    }

    fun targetDimensions(width: Int, height: Int, limits: PhotoPreparationLimits): ImageDimensions {
        val pixels = width.toLong() * height.toLong()
        val dimensionScale = limits.maxDimension.toDouble() / maxOf(width, height)
        val pixelScale = sqrt(limits.maxPixels.toDouble() / pixels)
        val scale = min(1.0, min(dimensionScale, pixelScale))
        return ImageDimensions(
            width = maxOf(1, floor(width * scale).toInt()),
            height = maxOf(1, floor(height * scale).toInt()),
        )
    }

    private fun sampledDimensions(source: ImageDimensions, sample: Int): ImageDimensions = ImageDimensions(
        width = ceil(source.width.toDouble() / sample).toInt(),
        height = ceil(source.height.toDouble() / sample).toInt(),
    )

    fun shrink(width: Int, height: Int, factor: Double): ImageDimensions {
        require(factor > 0.0 && factor < 1.0)
        return ImageDimensions(
            width = maxOf(1, (width * factor).roundToInt()),
            height = maxOf(1, (height * factor).roundToInt()),
        )
    }
}
