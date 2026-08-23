package com.chokwinlee.dshremote.platform.images

import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class ImagePreflightTest {
    private val limits = PhotoPreparationLimits(
        maxOutputBytes = 2_000_000,
        maxPixels = 4_000_000,
        maxDimension = 2_048,
    )

    @Test
    fun calculatesPowerOfTwoDecodeSampleBeforeAllocation() {
        val sample = ImagePreflight.calculateInSampleSize(ImageDimensions(8_000, 6_000), limits)

        assertEquals(4, sample)
    }

    @Test
    fun targetDimensionsRespectPixelAndEdgeLimits() {
        val target = ImagePreflight.targetDimensions(4_000, 3_000, limits)

        assertTrue(target.width <= limits.maxDimension)
        assertTrue(target.height <= limits.maxDimension)
        assertTrue(target.pixels <= limits.maxPixels)
    }

    @Test
    fun rejectsAbsurdSourceDimensions() {
        val error = assertThrows(PhotoPreparationException::class.java) {
            ImagePreflight.validateSourceDimensions(65_536, 1_000)
        }

        assertEquals(PhotoPreparationError.SOURCE_DIMENSIONS_UNSAFE, error.reason)
    }

    @Test
    fun stripsPathAndControlCharactersFromDisplayName() {
        assertEquals(
            "phonephoto.jpg",
            PhotoInputProcessor.sanitizeDisplayName("/private/photo\u0000phonephoto.jpg"),
        )
    }
}
