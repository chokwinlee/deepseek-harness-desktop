package com.chokwinlee.dshremote.remote

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.Json

/** Platform storage adapter. A SharedPreferences/DataStore implementation can be injected by the app. */
interface RemoteHostStorage {
    suspend fun write(serializedHosts: String?)
    suspend fun read(): String?
}

class InMemoryRemoteHostStorage(initial: String? = null) : RemoteHostStorage {
    private var value = initial

    override suspend fun write(serializedHosts: String?) {
        value = serializedHosts
    }

    override suspend fun read(): String? = value
}

class RemoteHostRepository(
    private val storage: RemoteHostStorage,
    private val json: Json = Json { ignoreUnknownKeys = true },
) {
    private val mutex = Mutex()
    private val mutableHosts = MutableStateFlow<List<RemoteHost>>(emptyList())
    val hosts: StateFlow<List<RemoteHost>> = mutableHosts.asStateFlow()

    suspend fun load(): List<RemoteHost> = mutex.withLock {
        val decoded = storage.read()?.let { serialized ->
            runCatching {
                json.decodeFromString(ListSerializer(RemoteHost.serializer()), serialized)
            }.getOrNull()
        }.orEmpty()
        mutableHosts.value = decoded
        decoded
    }

    suspend fun add(name: String?, connection: RemoteConnectionDescriptor): RemoteHost = mutex.withLock {
        val validated = RemoteEndpointValidator.validatedConnection(connection)
        val current = mutableHosts.value.toMutableList()
        val existingIndex = current.indexOfFirst { it.baseUrl == validated.baseUrl }
        val host = if (existingIndex >= 0) {
            current[existingIndex].copy(accessToken = validated.accessToken).also { current[existingIndex] = it }
        } else {
            val fallbackName = validated.baseUrl.substringAfter("://").substringBefore('/').substringBefore('.')
                .ifBlank { "My computer" }
            RemoteHost(
                name = name?.trim()?.takeIf(String::isNotEmpty) ?: fallbackName,
                baseUrl = validated.baseUrl,
                accessToken = validated.accessToken,
            ).also { current.add(0, it) }
        }
        persist(current)
        host
    }

    suspend fun remove(id: String) = mutex.withLock {
        persist(mutableHosts.value.filterNot { it.id == id })
    }

    suspend fun clear() = mutex.withLock {
        mutableHosts.value = emptyList()
        storage.write(null)
    }

    private suspend fun persist(value: List<RemoteHost>) {
        storage.write(json.encodeToString(ListSerializer(RemoteHost.serializer()), value))
        mutableHosts.value = value
    }
}
