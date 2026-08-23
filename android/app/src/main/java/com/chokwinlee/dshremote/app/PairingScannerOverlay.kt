package com.chokwinlee.dshremote.app

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.chokwinlee.dshremote.R
import com.chokwinlee.dshremote.platform.scanner.CameraPairingScanner
import com.chokwinlee.dshremote.platform.scanner.PairingCameraFailure
import com.chokwinlee.dshremote.remote.RemoteConnectionDescriptor

/** Activity-level camera sheet. It stays independent from navigation and survives recomposition. */
@Composable
fun PairingScannerOverlay(
    viewModel: RemoteAppViewModel,
    cameraPermissionGranted: Boolean,
    rejected: Boolean,
    onRejected: () -> Unit,
    onFailure: (PairingCameraFailure) -> Unit,
    onDismiss: () -> Unit,
) {
    Dialog(
        onDismissRequest = onDismiss,
        properties = DialogProperties(
            dismissOnBackPress = true,
            dismissOnClickOutside = false,
            usePlatformDefaultWidth = false,
            decorFitsSystemWindows = false,
        ),
    ) {
        Surface(modifier = Modifier.fillMaxSize(), color = Color.Black) {
            Box(Modifier.fillMaxSize()) {
                if (cameraPermissionGranted) {
                    CameraPairingScanner(
                        scanController = viewModel.pairingScanController,
                        cameraPermissionGranted = true,
                        onAccepted = viewModel::onPairingConnectionAccepted,
                        onRejected = { reason ->
                            viewModel.onPairingScanRejected(reason)
                            onRejected()
                        },
                        onFailure = onFailure,
                        modifier = Modifier.fillMaxSize(),
                    )
                } else {
                    CircularProgressIndicator(
                        modifier = Modifier.align(Alignment.Center),
                        color = Color.White,
                    )
                }

                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .background(Color.Black.copy(alpha = 0.66f))
                        .statusBarsPadding()
                        .padding(horizontal = 16.dp, vertical = 12.dp),
                    verticalArrangement = Arrangement.spacedBy(4.dp),
                ) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Column(modifier = Modifier.weight(1f)) {
                            Text(
                                text = stringResource(R.string.scanner_title),
                                color = Color.White,
                                style = MaterialTheme.typography.titleMedium,
                            )
                            Text(
                                text = stringResource(R.string.scanner_subtitle),
                                color = Color.White.copy(alpha = 0.78f),
                                style = MaterialTheme.typography.bodyMedium,
                            )
                        }
                        IconButton(onClick = onDismiss) {
                            Icon(
                                imageVector = Icons.Default.Close,
                                contentDescription = stringResource(R.string.action_close),
                                tint = Color.White,
                            )
                        }
                    }
                    if (rejected) {
                        Text(
                            text = stringResource(R.string.state_connection_failed),
                            color = MaterialTheme.colorScheme.error,
                            style = MaterialTheme.typography.labelLarge,
                        )
                    }
                }
            }
        }
    }
}
