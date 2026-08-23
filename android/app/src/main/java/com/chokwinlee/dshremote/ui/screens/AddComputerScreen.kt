package com.chokwinlee.dshremote.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Cloud
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.QrCodeScanner
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.chokwinlee.dshremote.R
import com.chokwinlee.dshremote.ui.components.RemoteActionButton
import com.chokwinlee.dshremote.ui.components.RemoteActionKind
import com.chokwinlee.dshremote.ui.components.RemoteCloseButton
import com.chokwinlee.dshremote.ui.components.RemoteInlineNotice
import com.chokwinlee.dshremote.ui.components.RemoteNoticeTone
import com.chokwinlee.dshremote.ui.components.RemotePageHeader
import com.chokwinlee.dshremote.ui.components.RemoteSectionHeader
import com.chokwinlee.dshremote.ui.components.RemoteSurface
import com.chokwinlee.dshremote.ui.components.RemoteTextField
import com.chokwinlee.dshremote.ui.model.AddComputerUiState
import com.chokwinlee.dshremote.ui.theme.RemoteDimens
import com.chokwinlee.dshremote.ui.theme.RemoteTheme

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AddComputerScreen(
    state: AddComputerUiState,
    onBack: () -> Unit,
    onScanQrCode: () -> Unit,
    onVerifyAndSave: (name: String, address: String) -> Unit,
    onOpenSettings: () -> Unit = {},
) {
    var name by rememberSaveable { mutableStateOf(state.initialName) }
    var address by rememberSaveable { mutableStateOf(state.initialAddress) }
    var remoteAccessExpanded by rememberSaveable { mutableStateOf(false) }
    var showScannerPlaceholder by rememberSaveable { mutableStateOf(false) }
    val focusManager = LocalFocusManager.current
    val colors = RemoteTheme.colors
    val remoteAccessSemantics = stringResource(
        if (remoteAccessExpanded) R.string.remote_access_collapse
        else R.string.remote_access_expand,
    )

    LaunchedEffect(state.initialName) {
        if (state.initialName.isNotBlank()) name = state.initialName
    }
    LaunchedEffect(state.initialAddress) {
        if (state.initialAddress.isNotBlank()) {
            address = state.initialAddress
            remoteAccessExpanded = true
        }
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(colors.canvas),
    ) {
        RemotePageHeader(
            title = stringResource(R.string.computer_add_title),
            subtitle = stringResource(R.string.computer_add_subtitle),
            onBack = onBack,
        )

        Column(
            modifier = Modifier
                .weight(1f)
                .verticalScroll(rememberScrollState())
                .padding(horizontal = RemoteDimens.pagePadding, vertical = 16.dp),
            verticalArrangement = Arrangement.spacedBy(RemoteDimens.space20),
        ) {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                RemoteSectionHeader(
                    title = stringResource(R.string.pairing_local_section),
                    detail = stringResource(R.string.label_recommended),
                )

                RemoteSurface(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clickable(
                            enabled = !state.isVerifying && state.qrScannerAvailable,
                            role = Role.Button,
                        ) {
                            focusManager.clearFocus()
                            onScanQrCode()
                            if (state.showQrPlaceholder) showScannerPlaceholder = true
                        },
                    raised = false,
                ) {
                    PairingChoiceRow(
                        icon = Icons.Default.QrCodeScanner,
                        title = stringResource(R.string.pairing_scan_title),
                        message = stringResource(R.string.pairing_scan_message),
                        enabled = state.qrScannerAvailable,
                    )
                }

                if (state.qrScannerAvailable) {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .semantics(mergeDescendants = true) {},
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        Icon(
                            imageVector = Icons.Default.CheckCircle,
                            contentDescription = null,
                            tint = colors.success,
                            modifier = Modifier.size(16.dp),
                        )
                        Text(
                            text = stringResource(R.string.pairing_no_tailscale_needed),
                            style = MaterialTheme.typography.labelSmall,
                            color = colors.success,
                        )
                    }
                } else {
                    RemoteInlineNotice(
                        title = stringResource(R.string.pairing_camera_unavailable_title),
                        message = stringResource(R.string.pairing_camera_unavailable_message),
                        tone = RemoteNoticeTone.Warning,
                        actionText = stringResource(R.string.action_open_settings),
                        onAction = onOpenSettings,
                    )
                }
            }

            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                RemoteSectionHeader(
                    title = stringResource(R.string.remote_access_section),
                    detail = stringResource(R.string.label_optional),
                )
                RemoteSurface(modifier = Modifier.fillMaxWidth()) {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable(role = Role.Button) {
                                focusManager.clearFocus()
                                remoteAccessExpanded = !remoteAccessExpanded
                            }
                            .padding(14.dp)
                            .semantics {
                                role = Role.Button
                                contentDescription = remoteAccessSemantics
                            },
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(10.dp),
                    ) {
                        Icon(
                            imageVector = Icons.Default.Cloud,
                            contentDescription = null,
                            tint = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.size(20.dp),
                        )
                        Column(
                            modifier = Modifier.weight(1f),
                            verticalArrangement = Arrangement.spacedBy(3.dp),
                        ) {
                            Text(
                                text = stringResource(R.string.remote_access_title),
                                style = MaterialTheme.typography.labelLarge,
                            )
                            Text(
                                text = stringResource(R.string.remote_access_message),
                                style = MaterialTheme.typography.bodyMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                        Icon(
                            imageVector = Icons.Default.ExpandMore,
                            contentDescription = null,
                            tint = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.graphicsLayer {
                                rotationZ = if (remoteAccessExpanded) 180f else 0f
                            },
                        )
                    }
                }

                if (remoteAccessExpanded) {
                    RemoteInlineNotice(
                        title = stringResource(R.string.remote_access_notice_title),
                        message = stringResource(R.string.remote_access_notice_message),
                        tone = RemoteNoticeTone.Information,
                    )
                    RemoteTextField(
                        value = name,
                        onValueChange = { name = it },
                        label = stringResource(R.string.computer_name_label),
                        placeholder = stringResource(R.string.computer_name_placeholder),
                        enabled = !state.isVerifying,
                        keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(
                            imeAction = ImeAction.Next,
                        ),
                    )
                    RemoteTextField(
                        value = address,
                        onValueChange = { address = it },
                        label = stringResource(R.string.computer_address_label),
                        placeholder = stringResource(R.string.computer_address_placeholder),
                        supportingText = stringResource(R.string.computer_address_supporting),
                        enabled = !state.isVerifying,
                        keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(
                            keyboardType = KeyboardType.Uri,
                            imeAction = ImeAction.Done,
                        ),
                    )
                }
            }

            if (state.errorMessage != null) {
                RemoteInlineNotice(
                    title = stringResource(R.string.state_connection_failed),
                    message = state.errorMessage,
                    tone = RemoteNoticeTone.Danger,
                    modifier = Modifier.semantics { liveRegion = LiveRegionMode.Assertive },
                    actionText = if (state.needsLocalNetworkPermission) {
                        stringResource(R.string.action_open_settings)
                    } else {
                        null
                    },
                    onAction = if (state.needsLocalNetworkPermission) onOpenSettings else null,
                )
            }

            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .semantics(mergeDescendants = true) {},
                verticalAlignment = Alignment.Top,
                horizontalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                Icon(
                    imageVector = Icons.Default.Lock,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.size(16.dp),
                )
                Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
                    Text(
                        text = stringResource(R.string.security_note_title),
                        style = MaterialTheme.typography.labelLarge,
                    )
                    Text(
                        text = stringResource(R.string.security_note_message),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }

        if (remoteAccessExpanded || address.isNotBlank()) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(colors.surface)
                    .navigationBarsPadding()
                    .imePadding()
                    .padding(horizontal = RemoteDimens.pagePadding, vertical = 10.dp),
            ) {
                RemoteActionButton(
                    text = if (state.isVerifying) {
                        stringResource(R.string.computer_verifying_action)
                    } else {
                        stringResource(R.string.computer_verify_action)
                    },
                    onClick = {
                        focusManager.clearFocus()
                        onVerifyAndSave(name.trim(), address.trim())
                    },
                    enabled = !state.isVerifying &&
                        name.isNotBlank() &&
                        address.trim().startsWith("https://", ignoreCase = true),
                    icon = if (state.isVerifying) null else Icons.Default.Lock,
                )
            }
        }
    }

    if (showScannerPlaceholder) {
        ModalBottomSheet(
            onDismissRequest = { showScannerPlaceholder = false },
            containerColor = colors.canvas,
            dragHandle = null,
        ) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .navigationBarsPadding()
                    .padding(horizontal = RemoteDimens.pagePadding, vertical = 16.dp),
                verticalArrangement = Arrangement.spacedBy(18.dp),
            ) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Column(modifier = Modifier.weight(1f)) {
                        Text(
                            text = stringResource(R.string.scanner_title),
                            style = MaterialTheme.typography.titleLarge,
                        )
                        Text(
                            text = stringResource(R.string.scanner_subtitle),
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                    RemoteCloseButton { showScannerPlaceholder = false }
                }

                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(248.dp)
                        .clip(RoundedCornerShape(RemoteDimens.focusedRadius))
                        .background(colors.codeSurface)
                        .border(
                            1.dp,
                            colors.strongHairline,
                            RoundedCornerShape(RemoteDimens.focusedRadius),
                        ),
                    contentAlignment = Alignment.Center,
                ) {
                    Column(
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(12.dp),
                        modifier = Modifier.padding(24.dp),
                    ) {
                        Icon(
                            imageVector = Icons.Default.QrCodeScanner,
                            contentDescription = null,
                            tint = colors.accent,
                            modifier = Modifier.size(34.dp),
                        )
                        Text(
                            text = stringResource(R.string.scanner_placeholder_message),
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
                RemoteActionButton(
                    text = stringResource(R.string.scanner_manual_action),
                    onClick = {
                        showScannerPlaceholder = false
                        remoteAccessExpanded = true
                    },
                    kind = RemoteActionKind.Secondary,
                )
                Spacer(Modifier.height(4.dp))
            }
        }
    }
}

@Composable
private fun PairingChoiceRow(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    title: String,
    message: String,
    enabled: Boolean,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 14.dp, vertical = 12.dp)
            .semantics(mergeDescendants = true) {},
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Icon(
            imageVector = icon,
            contentDescription = null,
            tint = RemoteTheme.colors.accent.copy(alpha = if (enabled) 1f else 0.42f),
            modifier = Modifier.size(22.dp),
        )
        Column(
            modifier = Modifier.weight(1f),
            verticalArrangement = Arrangement.spacedBy(2.dp),
        ) {
            Text(
                text = title,
                style = MaterialTheme.typography.bodyLarge.copy(fontWeight = FontWeight.SemiBold),
            )
            Text(
                text = message,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        Icon(
            imageVector = Icons.AutoMirrored.Filled.KeyboardArrowRight,
            contentDescription = null,
            tint = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.size(18.dp),
        )
    }
}
