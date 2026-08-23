package com.chokwinlee.dshremote.app

import java.io.File
import java.io.IOException
import java.security.MessageDigest
import java.util.Locale
import java.util.UUID

internal class AttachmentCacheLimitException : IllegalArgumentException()

/** Stable, bounded cache for attachments explicitly opened by the user. */
internal class AttachmentFileCache(
    private val directory: File,
    private val maxBytes: Long = DEFAULT_MAX_BYTES,
    private val maxEntries: Int = DEFAULT_MAX_ENTRIES,
    private val clockMillis: () -> Long = System::currentTimeMillis,
) {
    init {
        require(maxBytes > 0)
        require(maxEntries > 0)
    }

    @Synchronized
    fun get(
        key: String,
        mediaType: String,
        expectedBytes: Long,
    ): File? {
        ensureDirectory()
        val file = fileFor(key, mediaType)
        if (!file.isFile || file.length() != expectedBytes) {
            if (file.exists()) file.delete()
            return null
        }
        check(file.setLastModified(clockMillis())) { "Unable to update attachment cache access time" }
        prune(protected = file)
        return file
    }

    @Synchronized
    fun put(
        key: String,
        mediaType: String,
        bytes: ByteArray,
    ): File {
        if (bytes.size.toLong() > maxBytes) throw AttachmentCacheLimitException()
        ensureDirectory()
        val target = fileFor(key, mediaType)
        val temporary = File(directory, ".${target.name}.${UUID.randomUUID()}.tmp")
        try {
            temporary.outputStream().use { output -> output.write(bytes) }
            if (target.exists() && !target.delete()) {
                throw IOException("Unable to replace cached attachment")
            }
            if (!temporary.renameTo(target)) {
                temporary.copyTo(target, overwrite = true)
                temporary.delete()
            }
            check(target.setLastModified(clockMillis())) { "Unable to timestamp cached attachment" }
            prune(protected = target)
            return target
        } finally {
            if (temporary.exists()) temporary.delete()
        }
    }

    private fun ensureDirectory() {
        check((directory.isDirectory || directory.mkdirs()) && directory.isDirectory) {
            "Unable to create attachment cache"
        }
        directory.listFiles()
            .orEmpty()
            .filter { it.name.startsWith('.') && it.name.endsWith(".tmp") }
            .forEach(File::delete)
    }

    private fun prune(protected: File? = null) {
        val files = directory.listFiles()
            .orEmpty()
            .filter { it.isFile && it.name.startsWith(FILE_PREFIX) }
            .sortedWith(compareBy<File> { it.lastModified() }.thenBy { it.name })
            .toMutableList()
        var totalBytes = files.sumOf(File::length)
        while (files.size > maxEntries || totalBytes > maxBytes) {
            val candidate = files.firstOrNull { it != protected }
                ?: throw AttachmentCacheLimitException()
            val length = candidate.length()
            if (!candidate.delete()) throw IOException("Unable to prune attachment cache")
            files.remove(candidate)
            totalBytes -= length
        }
    }

    private fun fileFor(key: String, mediaType: String): File {
        val digest = MessageDigest.getInstance("SHA-256")
            .digest(key.toByteArray(Charsets.UTF_8))
            .joinToString(separator = "") { byte ->
                "%02x".format(Locale.ROOT, byte.toInt() and 0xff)
            }
        return File(directory, "$FILE_PREFIX$digest.${extension(mediaType)}")
    }

    private fun extension(mediaType: String): String = when (mediaType.lowercase(Locale.ROOT)) {
        "image/png" -> "png"
        "image/gif" -> "gif"
        "image/webp" -> "webp"
        else -> "jpg"
    }

    companion object {
        const val DEFAULT_MAX_BYTES = 64L * 1024L * 1024L
        const val DEFAULT_MAX_ENTRIES = 24
        private const val FILE_PREFIX = "attachment-"
    }
}
