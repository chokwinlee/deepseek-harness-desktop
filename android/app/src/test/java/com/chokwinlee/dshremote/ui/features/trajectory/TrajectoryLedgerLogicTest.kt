package com.chokwinlee.dshremote.ui.features.trajectory

import com.chokwinlee.dshremote.ui.model.DetailSectionKind
import com.chokwinlee.dshremote.ui.model.DetailSectionUiModel
import com.chokwinlee.dshremote.ui.model.ImageAttachmentUiModel
import com.chokwinlee.dshremote.ui.model.TrajectoryKindUi
import com.chokwinlee.dshremote.ui.model.TrajectoryRecordUiModel
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class TrajectoryLedgerLogicTest {
    private val records = listOf(
        record(id = "context", sequence = 1, turn = null, title = "Session context"),
        record(id = "turn-two", sequence = 4, turn = 2, title = "Compile release"),
        record(
            id = "turn-one-tool",
            sequence = 3,
            turn = 1,
            title = "Run tests",
            kind = TrajectoryKindUi.Tool,
            details = listOf(
                DetailSectionUiModel(
                    id = "stderr",
                    title = "Command output",
                    content = "Hidden diagnostic keyword",
                    kind = DetailSectionKind.Code,
                ),
            ),
        ),
        record(id = "turn-one-input", sequence = 2, turn = 1, title = "User request"),
    )

    @Test
    fun searchMatchesFullDetailsCaseInsensitively() {
        assertEquals(
            listOf("turn-one-tool"),
            filterTrajectoryRecords(records, "DIAGNOSTIC").map { it.id },
        )
        assertEquals(records, filterTrajectoryRecords(records, "  "))
    }

    @Test
    fun groupingKeepsContextFirstAndSortsTurnsAndSequence() {
        val groups = groupTrajectoryRecords(records)

        assertEquals(listOf(null, 1, 2), groups.map { it.turn })
        assertEquals(
            listOf("turn-one-input", "turn-one-tool"),
            groups[1].records.map { it.id },
        )
    }

    @Test
    fun overviewCountsVisibleEventsTurnsAndToolCalls() {
        assertEquals(TrajectoryOverview(4, 2, 1), trajectoryOverview(records))
    }

    @Test
    fun combinedCopyIncludesMetadataDetailsAndAttachments() {
        val record = records[2].copy(
            summary = "All checks passed",
            attachments = listOf(
                ImageAttachmentUiModel(
                    id = "image",
                    name = "result.png",
                    mediaType = "image/png",
                    width = 1200,
                    height = 800,
                    sizeLabel = "240 KB",
                ),
            ),
        )
        val text = trajectoryFullContent(
            record = record,
            kindLabel = "Tool",
            metadata = listOf("Turn 1", "Step 2", "420 ms"),
            labels = TrajectoryCopyLabels(
                kind = "Kind",
                sequence = "Sequence",
                summary = "Summary",
                details = "Details",
                attachments = "Attachments",
                defaultAttachment = "Image",
            ),
        )

        assertTrue(text.contains("Kind: Tool"))
        assertTrue(text.contains("Sequence: #3"))
        assertTrue(text.contains("Hidden diagnostic keyword"))
        assertTrue(text.contains("result.png · 1200 × 800 · 240 KB · image/png"))
    }

    private fun record(
        id: String,
        sequence: Int,
        turn: Int?,
        title: String,
        kind: TrajectoryKindUi = TrajectoryKindUi.Input,
        details: List<DetailSectionUiModel> = emptyList(),
    ) = TrajectoryRecordUiModel(
        id = id,
        sequence = sequence,
        turn = turn,
        kind = kind,
        title = title,
        summary = "Summary for $title",
        details = details,
    )
}
