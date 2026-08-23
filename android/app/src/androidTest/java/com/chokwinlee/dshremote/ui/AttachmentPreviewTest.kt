package com.chokwinlee.dshremote.ui

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.chokwinlee.dshremote.R
import com.chokwinlee.dshremote.ui.features.conversation.AttachmentList
import com.chokwinlee.dshremote.ui.model.ImageAttachmentUiModel
import com.chokwinlee.dshremote.ui.theme.DSHRemoteTheme
import java.util.concurrent.atomic.AtomicBoolean
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AttachmentPreviewTest {
    @get:Rule
    val compose = createComposeRule()

    private val context get() = ApplicationProvider.getApplicationContext<android.content.Context>()

    @Test
    fun unloadedAttachmentRequestsDataBeforePreviewing() {
        val requested = AtomicBoolean(false)
        compose.setContent {
            DSHRemoteTheme {
                AttachmentList(
                    attachments = listOf(attachment(previewUri = null)),
                    onOpenAttachment = { requested.set(true) },
                )
            }
        }

        compose.onNodeWithText("acceptance.png").performClick()
        compose.runOnIdle { assertTrue(requested.get()) }
    }

    @Test
    fun loadedAttachmentOpensAnInAppPreview() {
        compose.setContent {
            DSHRemoteTheme {
                AttachmentList(
                    attachments = listOf(
                        attachment(previewUri = "android.resource://${context.packageName}/${R.drawable.ic_launcher_foreground}"),
                    ),
                    onOpenAttachment = {},
                )
            }
        }

        compose.onNodeWithText("acceptance.png").performClick()
        compose.onNodeWithText(context.getString(R.string.attachment_preview_close))
            .assertIsDisplayed()
            .performClick()
    }

    private fun attachment(previewUri: String?) = ImageAttachmentUiModel(
        id = "image-1",
        name = "acceptance.png",
        mediaType = "image/png",
        width = 1179,
        height = 2556,
        sizeLabel = "428 KB",
        previewUri = previewUri,
    )
}
