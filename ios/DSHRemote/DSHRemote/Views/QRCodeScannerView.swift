import SwiftUI
import VisionKit

struct QRCodeScannerView: UIViewControllerRepresentable {
    let onResult: (String) -> Void
    var onError: ((String) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(onResult: onResult, onError: onError)
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        controller.delegate = context.coordinator
        do {
            try controller.startScanning()
        } catch {
            DispatchQueue.main.async {
                onError?(error.localizedDescription)
            }
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {}

    static func dismantleUIViewController(_ uiViewController: DataScannerViewController, coordinator: Coordinator) {
        uiViewController.stopScanning()
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        private let onResult: (String) -> Void
        private let onError: ((String) -> Void)?
        private var hasDeliveredResult = false

        init(onResult: @escaping (String) -> Void, onError: ((String) -> Void)?) {
            self.onResult = onResult
            self.onError = onError
        }

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didAdd addedItems: [RecognizedItem],
            allItems: [RecognizedItem]
        ) {
            guard !hasDeliveredResult else { return }
            for item in addedItems {
                guard case .barcode(let barcode) = item,
                      let value = barcode.payloadStringValue else {
                    continue
                }
                hasDeliveredResult = true
                onResult(value)
                return
            }
        }

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            becameUnavailableWithError error: DataScannerViewController.ScanningUnavailable
        ) {
            DispatchQueue.main.async { [onError] in
                onError?(error.localizedDescription)
            }
        }
    }
}
