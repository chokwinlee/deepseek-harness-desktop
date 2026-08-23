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
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowForward
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Cloud
import androidx.compose.material.icons.filled.Computer
import androidx.compose.material.icons.filled.DeleteOutline
import androidx.compose.material.icons.filled.ErrorOutline
import androidx.compose.material.icons.filled.MoreHoriz
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.QrCodeScanner
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Wifi
import androidx.compose.material.icons.outlined.Devices
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
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
import androidx.compose.ui.draw.clip
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.chokwinlee.dshremote.R
import com.chokwinlee.dshremote.ui.components.RemoteActionButton
import com.chokwinlee.dshremote.ui.components.RemoteErrorState
import com.chokwinlee.dshremote.ui.components.RemoteIconButton
import com.chokwinlee.dshremote.ui.components.RemoteLoadingState
import com.chokwinlee.dshremote.ui.components.RemoteSectionHeader
import com.chokwinlee.dshremote.ui.components.RemoteSurface
import com.chokwinlee.dshremote.ui.model.ComputerConnectionState
import com.chokwinlee.dshremote.ui.model.ComputerListUiState
import com.chokwinlee.dshremote.ui.model.ComputerTransport
import com.chokwinlee.dshremote.ui.model.ComputerUiModel
import com.chokwinlee.dshremote.ui.theme.RemoteDimens
import com.chokwinlee.dshremote.ui.theme.RemoteTheme

@Composable
fun ComputerListScreen(
    state: ComputerListUiState,
    onAddComputer: () -> Unit,
    onComputerSelected: (String) -> Unit,
    onRemoveComputer: (String) -> Unit,
    onTryDemo: () -> Unit,
    onRefresh: () -> Unit,
    onOpenAbout: () -> Unit,
) {
    var pendingRemoval by remember { mutableStateOf<ComputerUiModel?>(null) }
    val colors = RemoteTheme.colors

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(colors.canvas),
    ) {
        ComputerHomeHeader(
            hasComputers = state.computers.isNotEmpty(),
            isRefreshing = state.isRefreshing,
            onAddComputer = onAddComputer,
            onRefresh = onRefresh,
            onOpenAbout = onOpenAbout,
        )

        when {
            state.isLoading && state.computers.isEmpty() -> {
                RemoteLoadingState(
                    title = stringResource(R.string.computers_loading_title),
                    message = stringResource(R.string.computers_loading_message),
                    modifier = Modifier.weight(1f),
                )
            }

            state.errorMessage != null && state.computers.isEmpty() -> {
                RemoteErrorState(
                    message = state.errorMessage,
                    onRetry = onRefresh,
                    modifier = Modifier.weight(1f),
                )
            }

            state.computers.isEmpty() -> {
                ComputerOnboarding(
                    onAddComputer = onAddComputer,
                    onTryDemo = onTryDemo,
                    modifier = Modifier.weight(1f),
                )
            }

            else -> {
                SavedComputers(
                    state = state,
                    onComputerSelected = onComputerSelected,
                    onRemoveRequested = { pendingRemoval = it },
                    onRefresh = onRefresh,
                    modifier = Modifier.weight(1f),
                )
            }
        }
    }

    pendingRemoval?.let { computer ->
        AlertDialog(
            onDismissRequest = { pendingRemoval = null },
            icon = { Icon(Icons.Default.DeleteOutline, contentDescription = null) },
            title = { Text(stringResource(R.string.computer_remove_title, computer.name)) },
            text = { Text(stringResource(R.string.computer_remove_message)) },
            confirmButton = {
                TextButton(
                    onClick = {
                        onRemoveComputer(computer.id)
                        pendingRemoval = null
                    },
                ) {
                    Text(
                        text = stringResource(R.string.computer_remove_confirm),
                        color = colors.danger,
                    )
                }
            },
            dismissButton = {
                TextButton(onClick = { pendingRemoval = null }) {
                    Text(stringResource(R.string.action_cancel))
                }
            },
            containerColor = colors.surface,
            tonalElevation = 0.dp,
        )
    }
}

@Composable
private fun ComputerHomeHeader(
    hasComputers: Boolean,
    isRefreshing: Boolean,
    onAddComputer: () -> Unit,
    onRefresh: () -> Unit,
    onOpenAbout: () -> Unit,
) {
    val colors = RemoteTheme.colors
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(colors.canvas)
            .statusBarsPadding()
            .padding(start = 16.dp, top = 14.dp, end = 8.dp, bottom = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Column(
            modifier = Modifier
                .weight(1f)
                .semantics(mergeDescendants = true) { heading() },
            verticalArrangement = Arrangement.spacedBy(2.dp),
        ) {
            Text(
                text = stringResource(R.string.app_name),
                style = MaterialTheme.typography.titleLarge,
            )
            Text(
                text = stringResource(
                    if (hasComputers) R.string.computers_subtitle_saved
                    else R.string.computers_subtitle_onboarding,
                ),
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }

        if (hasComputers) {
            RemoteIconButton(
                imageVector = Icons.Default.Refresh,
                contentDescription = stringResource(R.string.action_refresh),
                onClick = onRefresh,
                enabled = !isRefreshing,
            )
            RemoteIconButton(
                imageVector = Icons.Default.Add,
                contentDescription = stringResource(R.string.computer_add_action),
                onClick = onAddComputer,
                tint = colors.accent,
                emphasized = true,
            )
        }
        RemoteIconButton(
            imageVector = Icons.Outlined.Info,
            contentDescription = stringResource(R.string.about_action),
            onClick = onOpenAbout,
        )
    }
}

@Composable
private fun ComputerOnboarding(
    onAddComputer: () -> Unit,
    onTryDemo: () -> Unit,
    modifier: Modifier = Modifier,
) {
    LazyColumn(
        modifier = modifier
            .fillMaxWidth()
            .navigationBarsPadding(),
        contentPadding = androidx.compose.foundation.layout.PaddingValues(
            start = RemoteDimens.pagePadding,
            top = 18.dp,
            end = RemoteDimens.pagePadding,
            bottom = 24.dp,
        ),
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        item {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Box(
                    modifier = Modifier
                        .size(70.dp)
                        .clip(RoundedCornerShape(20.dp))
                        .background(RemoteTheme.colors.accent.copy(alpha = 0.10f)),
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(
                        imageVector = Icons.Outlined.Devices,
                        contentDescription = null,
                        tint = RemoteTheme.colors.accent,
                        modifier = Modifier.size(34.dp),
                    )
                }
                Text(
                    text = stringResource(R.string.onboarding_title),
                    style = MaterialTheme.typography.headlineSmall,
                )
                Text(
                    text = stringResource(R.string.onboarding_message),
                    style = MaterialTheme.typography.bodyLarge,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }

        item {
            RemoteSurface(modifier = Modifier.fillMaxWidth()) {
                Column(
                    modifier = Modifier.padding(14.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    OnboardingStep(
                        number = "1",
                        title = stringResource(R.string.onboarding_step_desktop_title),
                        message = stringResource(R.string.onboarding_step_desktop_message),
                    )
                    OnboardingStep(
                        number = "2",
                        title = stringResource(R.string.onboarding_step_qr_title),
                        message = stringResource(R.string.onboarding_step_qr_message),
                    )
                }
            }
        }

        item {
            RemoteActionButton(
                text = stringResource(R.string.onboarding_primary_action),
                onClick = onAddComputer,
                icon = Icons.Default.QrCodeScanner,
            )
        }

        item {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .semantics(mergeDescendants = true) {},
                verticalAlignment = Alignment.Top,
                horizontalArrangement = Arrangement.spacedBy(11.dp),
            ) {
                Box(
                    modifier = Modifier
                        .size(38.dp)
                        .clip(RoundedCornerShape(11.dp))
                        .background(RemoteTheme.colors.raisedSurface),
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(
                        imageVector = Icons.Default.Cloud,
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.size(19.dp),
                    )
                }
                Column(
                    modifier = Modifier.weight(1f),
                    verticalArrangement = Arrangement.spacedBy(3.dp),
                ) {
                    Text(
                        text = stringResource(R.string.onboarding_remote_title),
                        style = MaterialTheme.typography.titleMedium,
                    )
                    Text(
                        text = stringResource(R.string.onboarding_remote_message),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }

        item {
            RemoteSurface(modifier = Modifier.fillMaxWidth()) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(RemoteDimens.rowRadius))
                        .clickable(role = Role.Button, onClick = onTryDemo)
                        .padding(13.dp)
                        .semantics(mergeDescendants = true) {},
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    Box(
                        modifier = Modifier
                            .size(38.dp)
                            .clip(RoundedCornerShape(11.dp))
                            .background(RemoteTheme.colors.reasoning.copy(alpha = 0.10f)),
                        contentAlignment = Alignment.Center,
                    ) {
                        Icon(
                            imageVector = Icons.Default.PlayArrow,
                            contentDescription = null,
                            tint = RemoteTheme.colors.reasoning,
                            modifier = Modifier.size(21.dp),
                        )
                    }
                    Column(
                        modifier = Modifier.weight(1f),
                        verticalArrangement = Arrangement.spacedBy(3.dp),
                    ) {
                        Text(
                            text = stringResource(R.string.onboarding_demo_action),
                            style = MaterialTheme.typography.titleMedium,
                        )
                        Text(
                            text = stringResource(R.string.onboarding_demo_message),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            maxLines = 2,
                            overflow = TextOverflow.Ellipsis,
                        )
                    }
                    Icon(
                        imageVector = Icons.AutoMirrored.Filled.ArrowForward,
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.size(18.dp),
                    )
                }
            }
        }
    }
}

@Composable
private fun OnboardingStep(
    number: String,
    title: String,
    message: String,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 6.dp)
            .semantics(mergeDescendants = true) {},
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.Top,
    ) {
        Box(
            modifier = Modifier
                .size(25.dp)
                .clip(CircleShape)
                .background(RemoteTheme.colors.accent.copy(alpha = 0.11f)),
            contentAlignment = Alignment.Center,
        ) {
            Text(
                text = number,
                color = RemoteTheme.colors.accent,
                style = MaterialTheme.typography.labelMedium.copy(fontWeight = FontWeight.SemiBold),
            )
        }
        Column(
            modifier = Modifier.weight(1f),
            verticalArrangement = Arrangement.spacedBy(2.dp),
        ) {
            Text(text = title, style = MaterialTheme.typography.labelLarge)
            Text(
                text = message,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

@Composable
private fun SavedComputers(
    state: ComputerListUiState,
    onComputerSelected: (String) -> Unit,
    onRemoveRequested: (ComputerUiModel) -> Unit,
    onRefresh: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val count = pluralStringResource(
        R.plurals.computer_count,
        state.computers.size,
        state.computers.size,
    )

    LazyColumn(
        modifier = modifier
            .fillMaxWidth()
            .navigationBarsPadding(),
        contentPadding = androidx.compose.foundation.layout.PaddingValues(
            start = RemoteDimens.pagePadding,
            top = 10.dp,
            end = RemoteDimens.pagePadding,
            bottom = 28.dp,
        ),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        if (state.errorMessage != null) {
            item {
                com.chokwinlee.dshremote.ui.components.RemoteInlineNotice(
                    title = stringResource(R.string.state_showing_saved_results),
                    message = state.errorMessage,
                    tone = com.chokwinlee.dshremote.ui.components.RemoteNoticeTone.Warning,
                    actionText = stringResource(R.string.action_retry),
                    onAction = onRefresh,
                )
            }
        }

        item {
            RemoteSectionHeader(
                title = stringResource(R.string.computers_section_title),
                detail = count,
            )
        }

        item {
            RemoteSurface(modifier = Modifier.fillMaxWidth()) {
                Column {
                    state.computers.forEachIndexed { index, computer ->
                        ComputerRow(
                            computer = computer,
                            onClick = { onComputerSelected(computer.id) },
                            onRemove = { onRemoveRequested(computer) },
                        )
                        if (index < state.computers.lastIndex) {
                            Box(
                                Modifier
                                    .fillMaxWidth()
                                    .padding(start = 62.dp)
                                    .height(1.dp)
                                    .background(RemoteTheme.colors.hairline),
                            )
                        }
                    }
                }
            }
        }

        item {
            Text(
                text = stringResource(R.string.computers_remove_hint),
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(horizontal = 2.dp, vertical = 2.dp),
            )
        }
    }
}

@Composable
private fun ComputerRow(
    computer: ComputerUiModel,
    onClick: () -> Unit,
    onRemove: () -> Unit,
) {
    val transportLabel = transportLabel(computer.transport)
    val connectionDescription = connectionStateLabel(computer.connectionState)
    val transportColor = when (computer.transport) {
        ComputerTransport.SameWifi -> RemoteTheme.colors.success
        ComputerTransport.Tailscale -> RemoteTheme.colors.accent
        ComputerTransport.CustomHttps -> RemoteTheme.colors.reasoning
        ComputerTransport.Demo -> MaterialTheme.colorScheme.onSurfaceVariant
    }
    val icon = when (computer.transport) {
        ComputerTransport.SameWifi -> Icons.Default.Wifi
        ComputerTransport.Tailscale, ComputerTransport.CustomHttps -> Icons.Default.Cloud

        ComputerTransport.Demo -> Icons.Default.PlayArrow
    }
    val connectionColor = when (computer.connectionState) {
        ComputerConnectionState.Unknown -> MaterialTheme.colorScheme.onSurfaceVariant
        ComputerConnectionState.Checking -> RemoteTheme.colors.accent
        ComputerConnectionState.Reachable -> RemoteTheme.colors.success
        ComputerConnectionState.Unreachable -> RemoteTheme.colors.danger
    }

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = 68.dp)
            .clickable(role = Role.Button, onClick = onClick)
            .padding(start = 14.dp, top = 9.dp, end = 4.dp, bottom = 9.dp)
            .semantics {
                role = Role.Button
                stateDescription = connectionDescription
            },
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(11.dp),
    ) {
        Icon(
            imageVector = icon,
            contentDescription = null,
            tint = transportColor,
            modifier = Modifier.size(21.dp),
        )
        Column(
            modifier = Modifier.weight(1f),
            verticalArrangement = Arrangement.spacedBy(2.dp),
        ) {
            Text(
                text = computer.name,
                style = MaterialTheme.typography.bodyLarge.copy(fontWeight = FontWeight.SemiBold),
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            Text(
                text = computer.address,
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                Box(
                    Modifier
                        .size(5.dp)
                        .clip(RoundedCornerShape(50))
                        .background(connectionColor),
                )
                Text(
                    text = stringResource(
                        R.string.projects_summary,
                        transportLabel,
                        connectionDescription,
                    ),
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }
        RemoteIconButton(
            imageVector = Icons.Default.MoreHoriz,
            contentDescription = stringResource(R.string.computer_manage, computer.name),
            onClick = onRemove,
        )
    }
}

@Composable
private fun transportLabel(transport: ComputerTransport): String = stringResource(
    when (transport) {
        ComputerTransport.SameWifi -> R.string.transport_same_wifi
        ComputerTransport.Tailscale -> R.string.transport_tailscale
        ComputerTransport.CustomHttps -> R.string.transport_custom_https
        ComputerTransport.Demo -> R.string.transport_demo
    },
)

@Composable
private fun connectionStateLabel(state: ComputerConnectionState): String = stringResource(
    when (state) {
        ComputerConnectionState.Unknown -> R.string.connection_unknown
        ComputerConnectionState.Checking -> R.string.connection_checking
        ComputerConnectionState.Reachable -> R.string.connection_reachable
        ComputerConnectionState.Unreachable -> R.string.connection_unreachable
    },
)
