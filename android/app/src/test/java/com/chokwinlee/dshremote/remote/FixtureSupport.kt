package com.chokwinlee.dshremote.remote

import java.io.File

internal fun remoteFixture(name: String): String {
    val relative = "test/fixtures/remote-v1/$name"
    val candidates = listOf(
        File(relative),
        File("../$relative"),
        File("../../$relative"),
        File(System.getProperty("user.dir"), relative),
        File(System.getProperty("user.dir"), "../$relative"),
    )
    return candidates.firstOrNull(File::isFile)?.readText()
        ?: error("Unable to locate shared fixture $relative from ${System.getProperty("user.dir")}")
}
