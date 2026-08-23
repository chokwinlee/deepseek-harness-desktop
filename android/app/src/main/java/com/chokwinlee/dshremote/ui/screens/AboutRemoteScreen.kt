package com.chokwinlee.dshremote.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.automirrored.filled.OpenInNew
import androidx.compose.material.icons.filled.DeleteForever
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.annotation.StringRes
import com.chokwinlee.dshremote.BuildConfig
import com.chokwinlee.dshremote.R
import com.chokwinlee.dshremote.ui.components.RemoteActionButton
import com.chokwinlee.dshremote.ui.components.RemoteActionKind
import com.chokwinlee.dshremote.ui.components.RemoteInlineNotice
import com.chokwinlee.dshremote.ui.components.RemoteNoticeTone
import com.chokwinlee.dshremote.ui.components.RemotePageHeader
import com.chokwinlee.dshremote.ui.components.RemoteSectionHeader
import com.chokwinlee.dshremote.ui.components.RemoteSurface
import com.chokwinlee.dshremote.ui.theme.RemoteDimens
import com.chokwinlee.dshremote.ui.theme.RemoteTheme

@Composable
fun AboutRemoteScreen(
    savedComputerCount: Int,
    onBack: () -> Unit,
    onRemoveAllComputers: () -> Unit,
    onOpenSystemSettings: () -> Unit = {},
) {
    var confirmRemoval by remember { mutableStateOf(false) }
    val uriHandler = LocalUriHandler.current

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(RemoteTheme.colors.canvas),
    ) {
        RemotePageHeader(
            title = stringResource(R.string.about_title),
            subtitle = stringResource(R.string.about_subtitle, BuildConfig.VERSION_NAME),
            onBack = onBack,
        )
        Column(
            modifier = Modifier
                .weight(1f)
                .verticalScroll(rememberScrollState())
                .navigationBarsPadding()
                .padding(horizontal = RemoteDimens.pagePadding, vertical = 16.dp),
            verticalArrangement = Arrangement.spacedBy(RemoteDimens.space20),
        ) {
            RemoteInlineNotice(
                title = stringResource(R.string.about_local_first_title),
                message = stringResource(R.string.about_local_first_message),
                tone = RemoteNoticeTone.Information,
            )

            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                RemoteSectionHeader(title = stringResource(R.string.about_tailscale_title))
                RemoteSurface(Modifier.fillMaxWidth()) {
                    Column(
                        modifier = Modifier.padding(vertical = 4.dp),
                    ) {
                        tailscaleGuideSteps.forEachIndexed { index, step ->
                            TailscaleStep(
                                number = index + 1,
                                text = stringResource(step.textRes),
                                links = step.links,
                                onOpenLink = uriHandler::openUri,
                            )
                            if (index < tailscaleGuideSteps.lastIndex) AboutHairline()
                        }
                    }
                }
                RemoteInlineNotice(
                    title = stringResource(R.string.about_tailscale_funnel_title),
                    message = stringResource(R.string.about_tailscale_funnel_message),
                    tone = RemoteNoticeTone.Warning,
                )
            }

            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                RemoteSectionHeader(title = stringResource(R.string.about_privacy_title))
                Text(
                    text = stringResource(R.string.about_privacy_message),
                    style = MaterialTheme.typography.bodyMedium,
                )
                Text(
                    text = stringResource(R.string.about_notification_limit),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                RemoteSurface(Modifier.fillMaxWidth()) {
                    Column {
                        AboutActionRow(
                            text = stringResource(R.string.about_privacy_policy_action),
                            icon = Icons.AutoMirrored.Filled.OpenInNew,
                            onClick = { uriHandler.openUri(PRIVACY_URL) },
                        )
                        AboutHairline(startPadding = 48.dp)
                        AboutActionRow(
                            text = stringResource(R.string.about_support_action),
                            icon = Icons.AutoMirrored.Filled.OpenInNew,
                            onClick = { uriHandler.openUri(SUPPORT_URL) },
                        )
                        AboutHairline(startPadding = 48.dp)
                        AboutActionRow(
                            text = stringResource(R.string.action_open_settings),
                            icon = Icons.Default.Settings,
                            onClick = onOpenSystemSettings,
                        )
                    }
                }
            }

            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                RemoteSectionHeader(
                    title = stringResource(R.string.about_local_data_title),
                    detail = pluralStringResource(
                        R.plurals.about_computer_count,
                        savedComputerCount,
                        savedComputerCount,
                    ),
                )
                Text(
                    text = stringResource(R.string.about_local_data_message),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                RemoteActionButton(
                    text = stringResource(R.string.about_remove_all_action),
                    onClick = { confirmRemoval = true },
                    kind = RemoteActionKind.Destructive,
                    icon = Icons.Default.DeleteForever,
                    enabled = savedComputerCount > 0,
                )
            }

            Text(
                text = stringResource(R.string.about_independent_project),
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }

    if (confirmRemoval) {
        AlertDialog(
            onDismissRequest = { confirmRemoval = false },
            title = { Text(stringResource(R.string.about_remove_all_title)) },
            text = { Text(stringResource(R.string.about_remove_all_message)) },
            confirmButton = {
                TextButton(
                    onClick = {
                        onRemoveAllComputers()
                        confirmRemoval = false
                    },
                ) {
                    Text(
                        text = stringResource(R.string.about_remove_all_confirm),
                        color = RemoteTheme.colors.danger,
                    )
                }
            },
            dismissButton = {
                TextButton(onClick = { confirmRemoval = false }) {
                    Text(stringResource(R.string.action_cancel))
                }
            },
            containerColor = RemoteTheme.colors.surface,
            tonalElevation = 0.dp,
        )
    }
}

@Composable
private fun TailscaleStep(
    number: Int,
    text: String,
    links: List<TailscaleGuideLink>,
    onOpenLink: (String) -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 14.dp, vertical = 10.dp),
        verticalAlignment = Alignment.Top,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Text(
            text = number.toString(),
            style = MaterialTheme.typography.labelMedium,
            color = RemoteTheme.colors.accent,
            modifier = Modifier
                .padding(top = 1.dp)
                .semantics { heading() },
        )
        Column(
            modifier = Modifier.weight(1f),
            verticalArrangement = Arrangement.spacedBy(3.dp),
        ) {
            Text(text = text, style = MaterialTheme.typography.bodyMedium)
            links.forEach { link ->
                TextButton(
                    onClick = { onOpenLink(link.url) },
                    modifier = Modifier.heightIn(min = 44.dp),
                ) {
                    Icon(
                        imageVector = Icons.AutoMirrored.Filled.OpenInNew,
                        contentDescription = null,
                        modifier = Modifier.size(17.dp),
                    )
                    Text(
                        text = stringResource(link.titleRes),
                        modifier = Modifier.padding(start = 7.dp),
                    )
                }
            }
        }
    }
}

@Composable
private fun AboutActionRow(
    text: String,
    icon: ImageVector,
    onClick: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = RemoteDimens.compactRowHeight)
            .clickable(role = Role.Button, onClick = onClick)
            .padding(horizontal = 14.dp, vertical = 8.dp)
            .semantics { role = Role.Button },
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Icon(
            imageVector = icon,
            contentDescription = null,
            tint = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.size(19.dp),
        )
        Text(
            text = text,
            style = MaterialTheme.typography.labelLarge,
            modifier = Modifier.weight(1f),
        )
        Icon(
            imageVector = Icons.AutoMirrored.Filled.KeyboardArrowRight,
            contentDescription = null,
            tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.65f),
            modifier = Modifier.size(18.dp),
        )
    }
}

@Composable
private fun AboutHairline(startPadding: androidx.compose.ui.unit.Dp = 36.dp) {
    Box(
        Modifier
            .fillMaxWidth()
            .padding(start = startPadding)
            .height(1.dp)
            .background(RemoteTheme.colors.hairline),
    )
}

private const val PRIVACY_URL =
    "https://github.com/chokwinlee/deepseek-harness-desktop/blob/main/docs/PRIVACY.md"
private const val SUPPORT_URL = "https://github.com/chokwinlee/deepseek-harness-desktop/issues"

internal data class TailscaleGuideLink(
    @param:StringRes val titleRes: Int,
    val url: String,
)

internal data class TailscaleGuideStep(
    @param:StringRes val textRes: Int,
    val links: List<TailscaleGuideLink> = emptyList(),
)

internal val tailscaleGuideSteps = listOf(
    TailscaleGuideStep(
        textRes = R.string.about_tailscale_step_1,
        links = listOf(
            TailscaleGuideLink(
                R.string.about_tailscale_download_android,
                "https://tailscale.com/docs/install/android",
            ),
            TailscaleGuideLink(
                R.string.about_tailscale_download_computer,
                "https://tailscale.com/download",
            ),
        ),
    ),
    TailscaleGuideStep(
        textRes = R.string.about_tailscale_step_2,
        links = listOf(
            TailscaleGuideLink(
                R.string.about_tailscale_open_admin,
                "https://login.tailscale.com/admin/machines",
            ),
        ),
    ),
    TailscaleGuideStep(
        textRes = R.string.about_tailscale_step_3,
        links = listOf(
            TailscaleGuideLink(
                R.string.about_tailscale_open_dns,
                "https://login.tailscale.com/admin/dns",
            ),
            TailscaleGuideLink(
                R.string.about_tailscale_https_guide,
                "https://tailscale.com/docs/how-to/set-up-https-certificates",
            ),
        ),
    ),
    TailscaleGuideStep(
        textRes = R.string.about_tailscale_step_4,
        links = listOf(
            TailscaleGuideLink(
                R.string.about_tailscale_serve_guide,
                "https://tailscale.com/docs/features/tailscale-serve",
            ),
        ),
    ),
    TailscaleGuideStep(textRes = R.string.about_tailscale_step_5),
)
