package com.chokwinlee.dshremote.ui.features.composer

import com.chokwinlee.dshremote.ui.model.ReferenceCandidateKind

internal data class ActiveReferenceToken(
    val start: Int,
    val endExclusive: Int,
    val query: String,
    val quoted: Boolean,
)

internal data class DraftReference(
    val start: Int,
    val endExclusive: Int,
    val displayText: String,
    val submissionText: String,
    val kind: ReferenceCandidateKind,
)

internal data class ReferenceInsertion(
    val text: String,
    val cursor: Int,
    val references: List<DraftReference>,
)

internal fun activeReferenceToken(text: String, cursor: Int): ActiveReferenceToken? {
    if (cursor !in 0..text.length) return null
    val beforeCursor = text.substring(0, cursor)
    val lineStart = beforeCursor.lastIndexOf('\n').let { if (it < 0) 0 else it + 1 }
    val line = beforeCursor.substring(lineStart)
    val match = REFERENCE_TOKEN.find(line) ?: return null
    val token = match.groups[1] ?: return null
    val quoted = match.groups[2]
    val plain = match.groups[3]
    val query = (quoted ?: plain)?.value ?: return null
    return ActiveReferenceToken(
        start = lineStart + token.range.first,
        endExclusive = lineStart + token.range.last + 1,
        query = query,
        quoted = quoted != null,
    )
}

internal fun formattedFileMention(
    pathValue: String,
    kind: ReferenceCandidateKind,
    preserveQuote: Boolean,
    keepDirectoryOpen: Boolean = true,
): String? {
    if (kind != ReferenceCandidateKind.File && kind != ReferenceCandidateKind.Directory) return null
    var path = pathValue.removePrefix("@")
    if (kind == ReferenceCandidateKind.Directory && !path.endsWith('/') && !path.endsWith('\\')) {
        path += "/"
    }
    if (path.isEmpty() || path.any(Char::isISOControl) || '"' in path) return null
    val quoted = preserveQuote || path.any(Char::isWhitespace)
    if (!quoted) return "@$path"
    return if (kind == ReferenceCandidateKind.Directory && keepDirectoryOpen) "@\"$path" else "@\"$path\""
}

internal fun insertReference(
    oldText: String,
    oldReferences: List<DraftReference>,
    token: ActiveReferenceToken,
    displayText: String,
    submissionText: String?,
    kind: ReferenceCandidateKind,
    appendSpace: Boolean,
): ReferenceInsertion {
    val suffix = if (appendSpace) " " else ""
    val replacement = displayText + suffix
    val newText = oldText.replaceRange(token.start, token.endExclusive, replacement)
    val shifted = updateDraftReferences(oldText, newText, oldReferences)
    val added = submissionText?.let {
        DraftReference(
            start = token.start,
            endExclusive = token.start + displayText.length,
            displayText = displayText,
            submissionText = it,
            kind = kind,
        )
    }
    return ReferenceInsertion(
        text = newText,
        cursor = token.start + replacement.length,
        references = if (added == null) shifted else shifted + added,
    )
}

internal fun updateDraftReferences(
    oldText: String,
    newText: String,
    references: List<DraftReference>,
): List<DraftReference> {
    if (oldText == newText || references.isEmpty()) return references
    val prefix = commonPrefixLength(oldText, newText)
    val suffix = commonSuffixLength(oldText, newText, prefix)
    val oldEnd = oldText.length - suffix
    val newEnd = newText.length - suffix
    val delta = (newEnd - prefix) - (oldEnd - prefix)
    return references.mapNotNull { reference ->
        when {
            reference.endExclusive <= prefix -> reference
            reference.start >= oldEnd -> reference.copy(
                start = reference.start + delta,
                endExclusive = reference.endExclusive + delta,
            )
            else -> null
        }
    }.filter { reference ->
        reference.start >= 0 &&
            reference.endExclusive <= newText.length &&
            newText.substring(reference.start, reference.endExclusive) == reference.displayText
    }
}

internal fun submissionText(text: String, references: List<DraftReference>): String {
    var result = text
    references.sortedByDescending(DraftReference::start).forEach { reference ->
        if (reference.start >= 0 &&
            reference.endExclusive <= result.length &&
            result.substring(reference.start, reference.endExclusive) == reference.displayText
        ) {
            result = result.replaceRange(reference.start, reference.endExclusive, reference.submissionText)
        }
    }
    return result
}

private fun commonPrefixLength(left: String, right: String): Int {
    val limit = minOf(left.length, right.length)
    var index = 0
    while (index < limit && left[index] == right[index]) index += 1
    return index
}

private fun commonSuffixLength(left: String, right: String, prefix: Int): Int {
    val limit = minOf(left.length - prefix, right.length - prefix)
    var count = 0
    while (count < limit && left[left.lastIndex - count] == right[right.lastIndex - count]) count += 1
    return count
}

private val REFERENCE_TOKEN = Regex("(?:^|\\s)(@\"([^\"]*)|@([^\\s@]*))$")
