package com.chokwinlee.dshremote.platform.scanner

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import androidx.annotation.OptIn
import androidx.camera.core.CameraSelector
import androidx.camera.core.ExperimentalGetImage
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.chokwinlee.dshremote.remote.RemoteConnectionDescriptor
import com.chokwinlee.dshremote.remote.RemoteEndpointError
import com.google.mlkit.vision.barcode.BarcodeScanner
import com.google.mlkit.vision.barcode.BarcodeScannerOptions
import com.google.mlkit.vision.barcode.BarcodeScanning
import com.google.mlkit.vision.barcode.common.Barcode
import com.google.mlkit.vision.common.InputImage
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/** Failures surfaced by [CameraPairingScanner]. */
sealed interface PairingCameraFailure {
    /** The host must request CAMERA before composing an active scanner. */
    data object PermissionMissing : PairingCameraFailure

    /** CameraX could not acquire or bind a camera. */
    data class CameraUnavailable(val cause: Throwable) : PairingCameraFailure

    /** ML Kit could not analyze a frame. The scanner remains active. */
    data class AnalysisFailed(val cause: Throwable) : PairingCameraFailure
}

/**
 * A lifecycle-bound camera surface for Desktop pairing QR codes.
 *
 * Frames are analyzed in memory with the bundled ML Kit model. They are never
 * recorded, persisted, logged, or uploaded. Only QR codes are decoded. A valid
 * result pauses analysis before [onAccepted] is invoked; rejected pairing codes
 * leave the camera active so the user can point it at another code.
 */
@Composable
fun CameraPairingScanner(
    scanController: PairingScanController,
    cameraPermissionGranted: Boolean,
    onAccepted: (RemoteConnectionDescriptor) -> Unit,
    modifier: Modifier = Modifier,
    onRejected: (RemoteEndpointError) -> Unit = {},
    onFailure: (PairingCameraFailure) -> Unit = {},
    onClosed: () -> Unit = {},
) {
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    val acceptedCallback = rememberUpdatedState(onAccepted)
    val rejectedCallback = rememberUpdatedState(onRejected)
    val failureCallback = rememberUpdatedState(onFailure)
    val closedCallback = rememberUpdatedState(onClosed)
    val previewView = remember(context) {
        PreviewView(context).apply {
            // TextureView composes predictably with scanner sheets and overlays.
            implementationMode = PreviewView.ImplementationMode.COMPATIBLE
            scaleType = PreviewView.ScaleType.FILL_CENTER
        }
    }
    val permissionIsActuallyGranted =
        ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) ==
            PackageManager.PERMISSION_GRANTED
    val canOpenCamera = cameraPermissionGranted && permissionIsActuallyGranted

    AndroidView(
        factory = { previewView },
        modifier = modifier,
        update = { view ->
            view.scaleType = PreviewView.ScaleType.FILL_CENTER
        },
    )

    DisposableEffect(canOpenCamera, context, lifecycleOwner, previewView, scanController) {
        if (!canOpenCamera) {
            scanController.stop()
            failureCallback.value(PairingCameraFailure.PermissionMissing)
            onDispose { }
        } else {
            val camera = CameraXPairingQrCamera(
                context = context,
                lifecycleOwner = lifecycleOwner,
                previewView = previewView,
            )
            val dispatcher = PairingScanResultDispatcher(
                controller = scanController,
                pauseCamera = camera::pause,
                onAccepted = { acceptedCallback.value(it) },
                onRejected = { rejectedCallback.value(it) },
            )

            dispatcher.start()
            camera.startWithFailureDetails(
                onDecoded = { payload -> dispatcher.dispatch(payload) },
                onFailure = { failure -> failureCallback.value(failure) },
            )

            onDispose {
                camera.close()
                dispatcher.stop()
                closedCallback.value()
            }
        }
    }
}

/**
 * Bridges the pure pairing parser to the camera and enforces callback order.
 * Kept Android-free so the one-shot behavior can be covered by local tests.
 */
internal class PairingScanResultDispatcher(
    private val controller: PairingScanController,
    private val pauseCamera: () -> Unit,
    private val onAccepted: (RemoteConnectionDescriptor) -> Unit,
    private val onRejected: (RemoteEndpointError) -> Unit,
) {
    private val delivered = AtomicBoolean(false)

    fun start() {
        delivered.set(false)
        controller.start()
    }

    fun stop() {
        controller.stop()
    }

    fun dispatch(payload: String): PairingScanResult {
        if (delivered.get()) return PairingScanResult.Inactive

        val result = controller.onDecoded(payload)
        when (result) {
            is PairingScanResult.Accepted -> {
                if (delivered.compareAndSet(false, true)) {
                    // Stop delivering frames before navigation or state mutation runs.
                    pauseCamera()
                    onAccepted(result.connection)
                }
            }

            is PairingScanResult.Rejected -> onRejected(result.reason)
            PairingScanResult.Duplicate,
            PairingScanResult.Inactive,
            -> Unit
        }
        return result
    }
}

/** CameraX/ML Kit implementation backing [CameraPairingScanner]. */
@androidx.annotation.OptIn(markerClass = [ExperimentalGetImage::class])
private class CameraXPairingQrCamera(
    private val context: Context,
    private val lifecycleOwner: LifecycleOwner,
    private val previewView: PreviewView,
) : PairingQrCamera {
    private val mainExecutor = ContextCompat.getMainExecutor(context)
    private val analysisExecutor: ExecutorService = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "dsh-pairing-qr").apply { isDaemon = true }
    }
    private val scanner: BarcodeScanner = BarcodeScanning.getClient(
        BarcodeScannerOptions.Builder()
            .setBarcodeFormats(Barcode.FORMAT_QR_CODE)
            .build(),
    )
    private val started = AtomicBoolean(false)
    private val paused = AtomicBoolean(false)
    private val closed = AtomicBoolean(false)
    private val processingFrame = AtomicBoolean(false)
    private val analysisFailureReported = AtomicBoolean(false)

    @Volatile
    private var cameraProvider: ProcessCameraProvider? = null

    @Volatile
    private var preview: Preview? = null

    @Volatile
    private var analysis: ImageAnalysis? = null

    override fun start(
        onDecoded: (String) -> Unit,
        onFailure: (Throwable) -> Unit,
    ) {
        startWithFailureDetails(
            onDecoded = onDecoded,
            onFailure = { failure ->
                onFailure(
                    when (failure) {
                        PairingCameraFailure.PermissionMissing ->
                            SecurityException("Camera permission is missing")

                        is PairingCameraFailure.CameraUnavailable -> failure.cause
                        is PairingCameraFailure.AnalysisFailed -> failure.cause
                    },
                )
            },
        )
    }

    fun startWithFailureDetails(
        onDecoded: (String) -> Unit,
        onFailure: (PairingCameraFailure) -> Unit,
    ) {
        if (closed.get() || !started.compareAndSet(false, true)) return
        paused.set(false)

        val providerFuture = ProcessCameraProvider.getInstance(context)
        providerFuture.addListener(
            {
                if (closed.get()) return@addListener

                try {
                    val provider = providerFuture.get()
                    if (closed.get()) return@addListener

                    val previewUseCase = Preview.Builder().build().also {
                        it.surfaceProvider = previewView.surfaceProvider
                    }
                    val analysisUseCase = ImageAnalysis.Builder()
                        .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                        .build()
                        .also { useCase ->
                            useCase.setAnalyzer(analysisExecutor) { imageProxy ->
                                analyzeFrame(
                                    imageProxy = imageProxy,
                                    onDecoded = onDecoded,
                                    onFailure = onFailure,
                                )
                            }
                        }

                    cameraProvider = provider
                    preview = previewUseCase
                    analysis = analysisUseCase
                    provider.bindToLifecycle(
                        lifecycleOwner,
                        CameraSelector.DEFAULT_BACK_CAMERA,
                        previewUseCase,
                        analysisUseCase,
                    )
                } catch (error: Throwable) {
                    if (!closed.get()) {
                        onFailure(
                            if (error is SecurityException) {
                                PairingCameraFailure.PermissionMissing
                            } else {
                                PairingCameraFailure.CameraUnavailable(error)
                            },
                        )
                    }
                }
            },
            mainExecutor,
        )
    }

    private fun analyzeFrame(
        imageProxy: ImageProxy,
        onDecoded: (String) -> Unit,
        onFailure: (PairingCameraFailure) -> Unit,
    ) {
        if (closed.get() || paused.get() || !processingFrame.compareAndSet(false, true)) {
            imageProxy.close()
            return
        }

        val mediaImage = imageProxy.image
        if (mediaImage == null) {
            processingFrame.set(false)
            imageProxy.close()
            return
        }

        val scanTask = try {
            val inputImage = InputImage.fromMediaImage(
                mediaImage,
                imageProxy.imageInfo.rotationDegrees,
            )
            scanner.process(inputImage)
        } catch (error: Throwable) {
            processingFrame.set(false)
            imageProxy.close()
            reportAnalysisFailure(error, onFailure)
            return
        }

        scanTask
            .addOnSuccessListener { barcodes ->
                if (closed.get() || paused.get()) return@addOnSuccessListener

                val payload = barcodes.firstNotNullOfOrNull { barcode ->
                    barcode.rawValue
                        ?.takeIf { barcode.format == Barcode.FORMAT_QR_CODE && it.isNotBlank() }
                }
                if (payload != null) {
                    // Pairing controller callbacks mutate UI state, so deliver on main.
                    mainExecutor.execute {
                        if (!closed.get() && !paused.get()) onDecoded(payload)
                    }
                }
            }
            .addOnFailureListener { error ->
                reportAnalysisFailure(error, onFailure)
            }
            .addOnCompleteListener {
                processingFrame.set(false)
                imageProxy.close()
            }
    }

    private fun reportAnalysisFailure(
        error: Throwable,
        onFailure: (PairingCameraFailure) -> Unit,
    ) {
        if (!closed.get() && analysisFailureReported.compareAndSet(false, true)) {
            mainExecutor.execute {
                if (!closed.get()) {
                    onFailure(PairingCameraFailure.AnalysisFailed(error))
                }
            }
        }
    }

    /** Keeps the preview visible while preventing any further frame analysis. */
    fun pause() {
        if (!paused.compareAndSet(false, true)) return
        analysis?.clearAnalyzer()
    }

    override fun stop() {
        if (closed.get()) return
        paused.set(true)
        unbindUseCases()
    }

    override fun close() {
        if (!closed.compareAndSet(false, true)) return
        paused.set(true)
        analysis?.clearAnalyzer()
        unbindUseCases()
        scanner.close()
        analysisExecutor.shutdown()
    }

    private fun unbindUseCases() {
        val provider = cameraProvider ?: return
        val boundUseCases = listOfNotNull(preview, analysis).toTypedArray()
        if (boundUseCases.isEmpty()) return

        mainExecutor.execute {
            try {
                provider.unbind(*boundUseCases)
            } catch (_: IllegalStateException) {
                // The lifecycle/provider may already have completed teardown.
            }
        }
    }
}
