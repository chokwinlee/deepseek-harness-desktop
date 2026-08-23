package com.chokwinlee.dshremote.ui

import com.chokwinlee.dshremote.ui.features.composer.DraftReference
import com.chokwinlee.dshremote.ui.features.composer.activeReferenceToken
import com.chokwinlee.dshremote.ui.features.composer.formattedFileMention
import com.chokwinlee.dshremote.ui.features.composer.insertReference
import com.chokwinlee.dshremote.ui.features.composer.submissionText
import com.chokwinlee.dshremote.ui.features.composer.updateDraftReferences
import com.chokwinlee.dshremote.ui.model.ReferenceCandidateKind
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class ReferenceDraftTest {
    @Test
    fun fileMentionsQuoteWhitespaceAndDirectoriesStayOpenForTraversal() {
        assertEquals(
            "@\"docs/My Guide.md\"",
            formattedFileMention("@docs/My Guide.md", ReferenceCandidateKind.File, preserveQuote = false),
        )
        assertEquals(
            "@\"docs/My Folder/",
            formattedFileMention("docs/My Folder", ReferenceCandidateKind.Directory, preserveQuote = false),
        )
        assertEquals(
            "@docs/api/",
            formattedFileMention("docs/api", ReferenceCandidateKind.Directory, preserveQuote = false),
        )
    }

    @Test
    fun unsafeFileMentionsAreRejected() {
        assertNull(formattedFileMention("docs/\"secret\"", ReferenceCandidateKind.File, false))
        assertNull(formattedFileMention("docs/unsafe\u0000name", ReferenceCandidateKind.File, false))
    }

    @Test
    fun quotedReferenceTokenKeepsWhitespaceInQuery() {
        val text = "Check @\"docs/My Guide"
        assertEquals(
            "docs/My Guide",
            activeReferenceToken(text, text.length)?.query,
        )
    }

    @Test
    fun friendlySessionLabelSubmitsOpaqueMention() {
        val source = "Compare @ses"
        val token = requireNotNull(activeReferenceToken(source, source.length))
        val inserted = insertReference(
            oldText = source,
            oldReferences = emptyList(),
            token = token,
            displayText = "@Release review",
            submissionText = "@session:019abc",
            kind = ReferenceCandidateKind.Session,
            appendSpace = true,
        )
        assertEquals("Compare @Release review ", inserted.text)
        assertEquals("Compare @session:019abc ", submissionText(inserted.text, inserted.references))
    }

    @Test
    fun editsBeforeReferenceShiftItAndEditsInsideRemoveIt() {
        val reference = DraftReference(
            start = 6,
            endExclusive = 14,
            displayText = "@Release",
            submissionText = "@session:1",
            kind = ReferenceCandidateKind.Session,
        )
        val shifted = updateDraftReferences("Open: @Release", "Please Open: @Release", listOf(reference))
        assertEquals(13, shifted.single().start)
        assertEquals(
            emptyList<DraftReference>(),
            updateDraftReferences("Open: @Release", "Open: @RelXease", listOf(reference)),
        )
    }
}
