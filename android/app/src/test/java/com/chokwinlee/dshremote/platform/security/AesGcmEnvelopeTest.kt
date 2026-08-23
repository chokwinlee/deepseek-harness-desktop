package com.chokwinlee.dshremote.platform.security

import java.util.Base64
import javax.crypto.spec.SecretKeySpec
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class AesGcmEnvelopeTest {
    private val key = SecretKeySpec(ByteArray(32) { (it * 7).toByte() }, "AES")

    @Test
    fun roundTripEncryptsMetadataAndToken() {
        val plaintext = """[{"name":"Studio Mac","baseUrl":"https://private.ts.net/","accessToken":"${"a".repeat(64)}"}]"""
        val envelope = AesGcmEnvelope.encryptWithIv(plaintext, key, ByteArray(12) { it.toByte() })

        assertFalse(envelope.contains("Studio Mac"))
        assertFalse(envelope.contains("private.ts.net"))
        assertFalse(envelope.contains("a".repeat(64)))
        assertEquals(plaintext, AesGcmEnvelope.decrypt(envelope, key))
    }

    @Test
    fun differentInitializationVectorsProduceDifferentCiphertext() {
        val first = AesGcmEnvelope.encryptWithIv("same", key, ByteArray(12) { 1 })
        val second = AesGcmEnvelope.encryptWithIv("same", key, ByteArray(12) { 2 })

        assertNotEquals(first, second)
    }

    @Test
    fun authenticationRejectsTamperedCiphertext() {
        val envelope = AesGcmEnvelope.encryptWithIv("secret", key, ByteArray(12) { it.toByte() })
        val parts = envelope.split('.').toMutableList()
        val ciphertext = Base64.getUrlDecoder().decode(parts[2]).also { bytes ->
            bytes[bytes.lastIndex] = (bytes.last().toInt() xor 1).toByte()
        }
        parts[2] = Base64.getUrlEncoder().withoutPadding().encodeToString(ciphertext)

        assertThrows(SecurityException::class.java) {
            AesGcmEnvelope.decrypt(parts.joinToString("."), key)
        }
    }

    @Test
    fun unknownEnvelopeVersionIsRejected() {
        assertThrows(IllegalArgumentException::class.java) {
            AesGcmEnvelope.decrypt("v2.AAAA.AAAAAAAAAAAAAAAAAAAAAA", key)
        }
    }
}
