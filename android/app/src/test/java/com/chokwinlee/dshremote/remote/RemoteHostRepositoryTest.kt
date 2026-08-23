package com.chokwinlee.dshremote.remote

import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class RemoteHostRepositoryTest {
    @Test
    fun `persists reloads and refreshes credential without duplicating host`() = runTest {
        val storage = InMemoryRemoteHostStorage()
        val repository = RemoteHostRepository(storage)
        val firstToken = "a".repeat(64)
        val secondToken = "b".repeat(64)
        val endpoint = "http://192.168.1.9:17373/"

        val first = repository.add("Office Mac", RemoteConnectionDescriptor(endpoint, firstToken))
        val updated = repository.add(null, RemoteConnectionDescriptor(endpoint, secondToken))
        val restored = RemoteHostRepository(storage)

        assertEquals(first.id, updated.id)
        assertEquals(secondToken, updated.accessToken)
        assertEquals(listOf(updated), restored.load())
    }

    @Test
    fun `removes one or all saved hosts`() = runTest {
        val storage = InMemoryRemoteHostStorage()
        val repository = RemoteHostRepository(storage)
        val first = repository.add("One", RemoteConnectionDescriptor("https://one.ts.net/", null))
        repository.add("Two", RemoteConnectionDescriptor("https://two.ts.net/", null))

        repository.remove(first.id)
        assertEquals(1, repository.hosts.value.size)
        repository.clear()
        assertTrue(repository.hosts.value.isEmpty())
        assertEquals(null, storage.read())
    }
}
