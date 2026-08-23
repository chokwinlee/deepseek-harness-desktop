package com.chokwinlee.dshremote.platform.security

import android.annotation.SuppressLint
import android.content.Context
import android.content.SharedPreferences
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import com.chokwinlee.dshremote.remote.RemoteHostStorage
import java.security.KeyStore
import java.security.SecureRandom
import java.util.Base64
import javax.crypto.AEADBadTagException
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Stores the complete serialized host collection as one authenticated ciphertext.
 *
 * Encrypting the whole value is deliberate: computer names and URLs can be just as
 * identifying as the bearer credential, so neither metadata nor tokens are written
 * to disk in clear text. The AES key is non-exportable and remains in Android Keystore.
 */
@SuppressLint("UseKtx") // Direct commit() results are checked; the KTX helper discards them.
class EncryptedRemoteHostStorage(
    context: Context,
    preferencesName: String = DEFAULT_PREFERENCES_NAME,
    keyAlias: String = DEFAULT_KEY_ALIAS,
) : RemoteHostStorage {
    private val preferences: SharedPreferences = context.applicationContext.getSharedPreferences(
        preferencesName,
        Context.MODE_PRIVATE,
    )
    private val cipher = AndroidKeystoreTextCipher(keyAlias)

    override suspend fun write(serializedHosts: String?) = withContext(Dispatchers.IO) {
        if (serializedHosts == null) {
            check(preferences.edit().remove(ENCRYPTED_HOSTS_KEY).commit()) {
                "Unable to remove encrypted computers"
            }
            return@withContext
        }
        require(serializedHosts.toByteArray(Charsets.UTF_8).size <= MAX_PLAINTEXT_BYTES) {
            "The saved computer list is unexpectedly large"
        }
        val encrypted = cipher.encrypt(serializedHosts)
        check(preferences.edit().putString(ENCRYPTED_HOSTS_KEY, encrypted).commit()) {
            "Unable to persist encrypted computers"
        }
    }

    override suspend fun read(): String? = withContext(Dispatchers.IO) {
        val encrypted = try {
            preferences.getString(ENCRYPTED_HOSTS_KEY, null)
        } catch (error: ClassCastException) {
            throw SecureRemoteHostStorageException(error)
        } ?: return@withContext null
        if (encrypted.length > MAX_ENVELOPE_CHARACTERS) {
            throw SecureRemoteHostStorageException()
        }

        // Fail closed without replacing the unreadable ciphertext. This prevents a
        // transient Keystore problem from silently overwriting a user's computers.
        try {
            cipher.decrypt(encrypted)
        } catch (error: Exception) {
            throw SecureRemoteHostStorageException(error)
        }
    }

    companion object {
        const val DEFAULT_PREFERENCES_NAME = "dsh_remote_secure_hosts"
        const val DEFAULT_KEY_ALIAS = "com.chokwinlee.dshremote.remote-hosts.v1"

        private const val ENCRYPTED_HOSTS_KEY = "encrypted_payload"
        private const val MAX_PLAINTEXT_BYTES = 1_048_576
        private const val MAX_ENVELOPE_CHARACTERS = 1_500_000
    }
}

/** The encrypted value is deliberately retained so the UI can offer retry or reset. */
class SecureRemoteHostStorageException(
    cause: Throwable? = null,
) : IllegalStateException("Saved computers could not be unlocked", cause)

internal interface AuthenticatedTextCipher {
    fun encrypt(plaintext: String): String
    fun decrypt(envelope: String): String
}

internal class AndroidKeystoreTextCipher(
    private val keyAlias: String,
) : AuthenticatedTextCipher {
    override fun encrypt(plaintext: String): String = AesGcmEnvelope.encrypt(
        plaintext = plaintext,
        key = getOrCreateKey(),
    )

    override fun decrypt(envelope: String): String = AesGcmEnvelope.decrypt(
        envelope = envelope,
        key = getOrCreateKey(),
    )

    @Synchronized
    private fun getOrCreateKey(): SecretKey {
        val keyStore = KeyStore.getInstance(KEYSTORE_PROVIDER).apply { load(null) }
        (keyStore.getKey(keyAlias, null) as? SecretKey)?.let { return it }

        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, KEYSTORE_PROVIDER)
        generator.init(
            KeyGenParameterSpec.Builder(
                keyAlias,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(AES_KEY_BITS)
                .setRandomizedEncryptionRequired(true)
                .setUserAuthenticationRequired(false)
                .build(),
        )
        return generator.generateKey()
    }

    private companion object {
        const val KEYSTORE_PROVIDER = "AndroidKeyStore"
        const val AES_KEY_BITS = 256
    }
}

/** Versioned, URL-safe envelope: `v1.<12-byte IV>.<ciphertext + 128-bit tag>`. */
internal object AesGcmEnvelope {
    private const val VERSION = "v1"
    private const val IV_BYTES = 12
    private const val TAG_BITS = 128
    private val encoder = Base64.getUrlEncoder().withoutPadding()
    private val decoder = Base64.getUrlDecoder()

    fun encrypt(
        plaintext: String,
        key: SecretKey,
        secureRandom: SecureRandom = SecureRandom(),
    ): String {
        val iv = ByteArray(IV_BYTES).also(secureRandom::nextBytes)
        return encryptWithIv(plaintext, key, iv)
    }

    internal fun encryptWithIv(plaintext: String, key: SecretKey, iv: ByteArray): String {
        require(iv.size == IV_BYTES) { "AES-GCM requires a 12-byte IV" }
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key, GCMParameterSpec(TAG_BITS, iv))
        cipher.updateAAD(VERSION.toByteArray(Charsets.US_ASCII))
        val ciphertext = cipher.doFinal(plaintext.toByteArray(Charsets.UTF_8))
        return listOf(VERSION, encoder.encodeToString(iv), encoder.encodeToString(ciphertext)).joinToString(".")
    }

    fun decrypt(envelope: String, key: SecretKey): String {
        val parts = envelope.split('.', limit = 4)
        require(parts.size == 3 && parts[0] == VERSION) { "Unsupported encrypted payload" }
        val iv = runCatching { decoder.decode(parts[1]) }
            .getOrElse { throw IllegalArgumentException("Invalid encrypted payload", it) }
        val ciphertext = runCatching { decoder.decode(parts[2]) }
            .getOrElse { throw IllegalArgumentException("Invalid encrypted payload", it) }
        require(iv.size == IV_BYTES && ciphertext.size >= TAG_BITS / 8) { "Invalid encrypted payload" }

        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(TAG_BITS, iv))
        cipher.updateAAD(VERSION.toByteArray(Charsets.US_ASCII))
        return try {
            cipher.doFinal(ciphertext).toString(Charsets.UTF_8)
        } catch (error: AEADBadTagException) {
            throw SecurityException("Encrypted computer data failed authentication", error)
        }
    }
}
