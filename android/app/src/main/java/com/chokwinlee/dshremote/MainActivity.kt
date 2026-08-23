package com.chokwinlee.dshremote

import android.Manifest
import android.content.ActivityNotFoundException
import android.content.ClipboardManager
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import androidx.activity.ComponentActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.viewModels
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.core.content.ContextCompat
import androidx.core.net.toUri
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import androidx.lifecycle.Lifecycle
import com.chokwinlee.dshremote.app.PairingScannerOverlay
import com.chokwinlee.dshremote.app.RemoteAppViewModel
import com.chokwinlee.dshremote.app.RemoteSystemRequest
import com.chokwinlee.dshremote.platform.scanner.PairingCameraFailure
import com.chokwinlee.dshremote.ui.DSHRemoteApp
import com.chokwinlee.dshremote.ui.theme.DSHRemoteTheme

class MainActivity : ComponentActivity() {
    private val remoteViewModel: RemoteAppViewModel by viewModels()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        remoteViewModel.handleLaunchIntent(intent)
        setContent {
            val uiState by remoteViewModel.uiState.collectAsStateWithLifecycle()
            val scannerRequested by remoteViewModel.scannerRequested.collectAsStateWithLifecycle()
            var cameraPermissionGranted by remember {
                mutableStateOf(
                    ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) ==
                        PackageManager.PERMISSION_GRANTED,
                )
            }
            var scannerRejected by remember { mutableStateOf(false) }
            val imageLauncher = rememberLauncherForActivityResult(
                ActivityResultContracts.PickMultipleVisualMedia(MAX_PICKED_IMAGES),
            ) { uris ->
                remoteViewModel.onImagesSelected(uris)
            }
            val notificationPermissionLauncher = rememberLauncherForActivityResult(
                ActivityResultContracts.RequestPermission(),
            ) { }
            val cameraPermissionLauncher = rememberLauncherForActivityResult(
                ActivityResultContracts.RequestPermission(),
            ) { granted ->
                cameraPermissionGranted = granted
                if (!granted) {
                    if (!shouldShowRequestPermissionRationale(Manifest.permission.CAMERA)) {
                        remoteViewModel.setQrScannerAvailable(false)
                    }
                    remoteViewModel.dismissQrScanner()
                }
            }
            val localNetworkPermissionLauncher = rememberLauncherForActivityResult(
                ActivityResultContracts.RequestPermission(),
                remoteViewModel::onLocalNetworkPermissionResult,
            )

            LaunchedEffect(Unit) {
                remoteViewModel.setQrScannerAvailable(
                    packageManager.hasSystemFeature(PackageManager.FEATURE_CAMERA_ANY),
                )
            }
            LifecycleEventEffect(Lifecycle.Event.ON_RESUME) {
                cameraPermissionGranted =
                    ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) ==
                    PackageManager.PERMISSION_GRANTED
                if (cameraPermissionGranted) {
                    remoteViewModel.setQrScannerAvailable(
                        packageManager.hasSystemFeature(PackageManager.FEATURE_CAMERA_ANY),
                    )
                }
                if (Build.VERSION.SDK_INT < 37 ||
                    ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_LOCAL_NETWORK) ==
                    PackageManager.PERMISSION_GRANTED
                ) {
                    remoteViewModel.onLocalNetworkPermissionResult(true)
                }
            }
            LaunchedEffect(remoteViewModel) {
                remoteViewModel.systemRequests.collect { request ->
                    when (request) {
                        RemoteSystemRequest.ScanPairingCode -> {
                            scannerRejected = false
                            if (!packageManager.hasSystemFeature(PackageManager.FEATURE_CAMERA_ANY)) {
                                remoteViewModel.setQrScannerAvailable(false)
                                remoteViewModel.dismissQrScanner()
                            } else if (!cameraPermissionGranted) {
                                cameraPermissionLauncher.launch(Manifest.permission.CAMERA)
                            } else {
                                // scannerRequested already presents the lifecycle-bound camera.
                            }
                        }
                        RemoteSystemRequest.PickImages -> imageLauncher.launch(
                            PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly),
                        )
                        RemoteSystemRequest.PasteImages -> {
                            val clipboard = getSystemService(ClipboardManager::class.java)
                            val clip = runCatching { clipboard.primaryClip }.getOrNull()
                            val imageUris = buildList {
                                if (clip != null) {
                                    for (index in 0 until clip.itemCount) {
                                        clip.getItemAt(index).uri?.let(::add)
                                    }
                                }
                            }
                            if (imageUris.isEmpty()) remoteViewModel.onClipboardImageUnavailable()
                            else remoteViewModel.onImagesSelected(imageUris)
                        }
                        RemoteSystemRequest.RequestNotificationPermission -> {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                                notificationPermissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
                            }
                        }
                        RemoteSystemRequest.RequestLocalNetworkPermission -> {
                            if (Build.VERSION.SDK_INT >= 37) {
                                localNetworkPermissionLauncher.launch(Manifest.permission.ACCESS_LOCAL_NETWORK)
                            } else {
                                remoteViewModel.onLocalNetworkPermissionResult(true)
                            }
                        }
                        RemoteSystemRequest.OpenAppSettings -> {
                            startActivity(
                                Intent(
                                    Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                                    "package:$packageName".toUri(),
                                ),
                            )
                        }
                        is RemoteSystemRequest.OpenAttachment -> openAttachment(request)
                    }
                }
            }

            DSHRemoteApp(
                uiState = uiState,
                callbacks = remoteViewModel.callbacks,
            )
            if (scannerRequested) {
                DSHRemoteTheme {
                    PairingScannerOverlay(
                        viewModel = remoteViewModel,
                        cameraPermissionGranted = cameraPermissionGranted,
                        rejected = scannerRejected,
                        onRejected = { scannerRejected = true },
                        onFailure = { failure ->
                            when (failure) {
                                PairingCameraFailure.PermissionMissing -> {
                                    cameraPermissionGranted = false
                                    cameraPermissionLauncher.launch(Manifest.permission.CAMERA)
                                }
                                is PairingCameraFailure.CameraUnavailable -> {
                                    remoteViewModel.setQrScannerAvailable(false)
                                    remoteViewModel.dismissQrScanner()
                                }
                                is PairingCameraFailure.AnalysisFailed -> scannerRejected = true
                            }
                        },
                        onDismiss = remoteViewModel::dismissQrScanner,
                    )
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        remoteViewModel.handleLaunchIntent(intent)
    }

    private fun openAttachment(request: RemoteSystemRequest.OpenAttachment) {
        val intent = Intent(Intent.ACTION_VIEW)
            .setDataAndType(request.uri.toUri(), request.mediaType)
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        try {
            startActivity(intent)
        } catch (_: ActivityNotFoundException) {
            // The cached attachment remains available in session state. A future in-app viewer can
            // consume the same content URI without changing the Remote protocol or cache policy.
        }
    }

    private companion object {
        const val MAX_PICKED_IMAGES = 4
    }
}
