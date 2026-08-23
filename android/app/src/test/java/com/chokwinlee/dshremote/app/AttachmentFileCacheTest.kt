package com.chokwinlee.dshremote.app

import java.nio.file.Files
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

class AttachmentFileCacheTest {
    private lateinit var directory: java.io.File
    private var now = 10_000L

    @Before
    fun setUp() {
        directory = Files.createTempDirectory("dsh-attachment-cache").toFile()
    }

    @After
    fun tearDown() {
        directory.deleteRecursively()
    }

    @Test
    fun `stable key reuses the same verified file`() {
        val cache = cache(maxBytes = 32, maxEntries = 4)
        val created = cache.put("host:session:image", "image/png", byteArrayOf(1, 2, 3))
        now += 1_000

        val reused = cache.get("host:session:image", "image/png", expectedBytes = 3)

        assertEquals(created, reused)
        assertEquals(1, directory.listFiles().orEmpty().count { it.name.startsWith("attachment-") })
        assertTrue(created.lastModified() >= now)
    }

    @Test
    fun `least recently used entry is evicted when count is exceeded`() {
        val cache = cache(maxBytes = 64, maxEntries = 2)
        val first = cache.put("first", "image/jpeg", byteArrayOf(1))
        now += 1_000
        val second = cache.put("second", "image/jpeg", byteArrayOf(2))
        now += 1_000
        cache.get("first", "image/jpeg", expectedBytes = 1)
        now += 1_000

        val third = cache.put("third", "image/jpeg", byteArrayOf(3))

        assertTrue(first.exists())
        assertFalse(second.exists())
        assertTrue(third.exists())
    }

    @Test
    fun `byte budget evicts old data and rejects a single oversized attachment`() {
        val cache = cache(maxBytes = 6, maxEntries = 4)
        val first = cache.put("first", "image/webp", byteArrayOf(1, 2, 3, 4))
        now += 1_000
        val second = cache.put("second", "image/webp", byteArrayOf(5, 6, 7, 8))

        assertFalse(first.exists())
        assertTrue(second.exists())
        assertNotEquals(first, second)
        assertThrows(AttachmentCacheLimitException::class.java) {
            cache.put("too-large", "image/png", ByteArray(7))
        }
    }

    private fun cache(maxBytes: Long, maxEntries: Int) = AttachmentFileCache(
        directory = directory,
        maxBytes = maxBytes,
        maxEntries = maxEntries,
        clockMillis = { now },
    )
}
