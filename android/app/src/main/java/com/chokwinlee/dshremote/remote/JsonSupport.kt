package com.chokwinlee.dshremote.remote

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.intOrNull

internal fun JsonElement?.objectOrNull(): JsonObject? = this as? JsonObject
internal fun JsonElement?.arrayOrNull(): JsonArray? = this as? JsonArray
internal fun JsonElement?.stringOrNull(): String? = (this as? JsonPrimitive)?.takeUnless { it is JsonNull }?.content
internal fun JsonElement?.booleanOrNull(): Boolean? = (this as? JsonPrimitive)?.booleanOrNull
internal fun JsonElement?.doubleOrNull(): Double? = (this as? JsonPrimitive)?.doubleOrNull
internal fun JsonElement?.intOrNull(): Int? {
    val primitive = this as? JsonPrimitive ?: return null
    return primitive.intOrNull ?: primitive.doubleOrNull?.takeIf { it % 1.0 == 0.0 }?.toInt()
}

internal fun textContent(value: JsonElement?): String? {
    val parts = contentTexts(value, setOf("text"))
    return parts.joinToString("\n").trim().takeIf(String::isNotEmpty)
}

internal fun reasoningContent(value: JsonElement?): String? {
    val parts = contentTexts(value, setOf("reasoning"))
    return parts.joinToString("\n").trim().takeIf(String::isNotEmpty)
}

private fun contentTexts(value: JsonElement?, acceptedTypes: Set<String>): List<String> =
    value.arrayOrNull().orEmpty().flatMap { item ->
        val block = item.objectOrNull() ?: return@flatMap emptyList()
        val type = block["type"].stringOrNull() ?: return@flatMap emptyList()
        when {
            type in acceptedTypes -> listOfNotNull(block["text"].stringOrNull())
            type == "tool-result" -> contentTexts(block["content"], acceptedTypes)
            else -> emptyList()
        }
    }

internal fun imageAttachments(value: JsonElement?): List<RemoteImageAttachment> {
    val output = mutableListOf<RemoteImageAttachment>()
    fun collect(element: JsonElement?) {
        when (element) {
            is JsonArray -> element.forEach(::collect)
            is JsonObject -> {
                if (element["type"].stringOrNull() == "image") {
                    element["attachment"].objectOrNull()?.let { attachment ->
                        val id = attachment["attachmentId"].stringOrNull()
                        val mediaType = attachment["mediaType"].stringOrNull()
                        val bytes = attachment["bytes"].intOrNull()
                        val width = attachment["width"].intOrNull()
                        val height = attachment["height"].intOrNull()
                        if (!id.isNullOrBlank() && mediaType in SUPPORTED_IMAGE_TYPES &&
                            bytes != null && bytes > 0 && width != null && width > 0 && height != null && height > 0
                        ) {
                            output += RemoteImageAttachment(
                                id,
                                mediaType!!,
                                bytes,
                                width,
                                height,
                                attachment["name"].stringOrNull(),
                            )
                        }
                    }
                }
                collect(element["content"])
            }
            else -> Unit
        }
    }
    collect(value)
    return output
}

internal fun imageCount(value: JsonElement?): Int {
    var count = 0
    fun collect(element: JsonElement?) {
        when (element) {
            is JsonArray -> element.forEach(::collect)
            is JsonObject -> {
                if (element["type"].stringOrNull() == "image") count++
                collect(element["content"])
            }
            else -> Unit
        }
    }
    collect(value)
    return count
}
