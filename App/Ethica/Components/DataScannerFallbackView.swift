//
//  DataScannerFallbackView.swift
//  Ethica
//
//  VisionKit DataScannerViewController — fallback live scanner when AVFoundation preview fails.

import SwiftUI
import VisionKit
import Vision

enum VisionKitBarcodeScannerSupport {
    static var isAvailable: Bool {
        guard #available(iOS 16.0, *) else { return false }
        return DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }
}

@available(iOS 16.0, *)
struct VisionKitBarcodeScannerSheet: View {
    let onBarcodeDetected: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                DataScannerFallbackRepresentable { barcode in
                    onBarcodeDetected(barcode)
                    dismiss()
                }
                .ignoresSafeArea()
            }
            .navigationTitle("Scan Barcode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

@available(iOS 16.0, *)
private struct DataScannerFallbackRepresentable: UIViewControllerRepresentable {
    let onBarcodeDetected: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onBarcodeDetected: onBarcodeDetected)
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: Self.productBarcodeTypes,
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: true,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        context.coordinator.scanner = scanner
        return scanner
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {
        context.coordinator.startScanningIfNeeded()
    }

    static var productBarcodeTypes: Set<DataScannerViewController.RecognizedDataType> {
        [
            .barcode(symbologies: [
                .ean13,
                .ean8,
                .upce,
                .code128,
                .code39,
                .code93,
                .itf14
            ])
        ]
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        private let onBarcodeDetected: (String) -> Void
        weak var scanner: DataScannerViewController?
        private var didStartScanning = false
        private var didDeliverBarcode = false

        init(onBarcodeDetected: @escaping (String) -> Void) {
            self.onBarcodeDetected = onBarcodeDetected
        }

        func startScanningIfNeeded() {
            guard !didStartScanning, let scanner else { return }
            didStartScanning = true
            do {
                try scanner.startScanning()
            } catch {
                AppLogger.error("❌ VisionKit DataScanner failed to start: \(error.localizedDescription)")
            }
        }

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didAdd addedItems: [RecognizedItem],
            allItems: [RecognizedItem]
        ) {
            deliverBarcodeIfNeeded(from: addedItems)
        }

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didTapOn item: RecognizedItem
        ) {
            deliverBarcodeIfNeeded(from: [item])
        }

        private func deliverBarcodeIfNeeded(from items: [RecognizedItem]) {
            guard !didDeliverBarcode else { return }

            for item in items {
                guard case .barcode(let barcode) = item,
                      let raw = barcode.payloadStringValue else { continue }

                let normalized = BarcodeScanner.normalizeProductBarcode(raw)
                guard BarcodeScanner.isValidProductBarcode(normalized) else { continue }

                didDeliverBarcode = true
                scanner?.stopScanning()
                AppLogger.debug("📷 VisionKit fallback detected barcode: \(normalized)")
                onBarcodeDetected(normalized)
                return
            }
        }
    }
}
