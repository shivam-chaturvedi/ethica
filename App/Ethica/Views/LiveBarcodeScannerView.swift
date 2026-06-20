//
//  LiveBarcodeScannerView.swift
//  Ethica
//
//  Real-time barcode scanner with INSTANT results - Yuka-style experience

import SwiftUI
import AVFoundation
import Vision
import Combine
import AudioToolbox
import PhotosUI

struct LiveBarcodeScannerView: View {
    @ObservedObject var preferencesManager: PreferencesManager
    @StateObject private var scanner = BarcodeScannerManager()
    @ObservedObject private var productDatabase = ProductDatabaseService.shared
    @Environment(\.dismiss) var dismiss
    
    @State private var analysisResult: AnalysisResult?
    @State private var isAnalyzing = false
    @State private var showResults = false
    @State private var lastScannedBarcode = ""
    @State private var scanCooldown = false
    @State private var notFoundBarcode = ""
    @State private var notFoundPreviewImage: UIImage?
    @State private var scanPreviewImage: UIImage?
    @State private var debounceTask: Task<Void, Never>?
    @State private var showVisualScanner = false
    @State private var showProductNotFoundFlow = false

    // Barcode-from-image states
    @State private var showBarcodeImagePicker = false
    @State private var pickedBarcodeItem: PhotosPickerItem?
    @State private var isDecodingPickedImage = false
    @State private var isProcessingPickedPhoto = false
    @State private var pickedPhotoFailed = false
    @State private var activeAlert: ScannerAlert?
    @State private var activeBarcodeLookupTask: Task<Void, Never>?
    @State private var activeBarcodeDecodeTask: Task<Void, Never>?
    @State private var lookupDeadlineTask: Task<Void, Never>?

    // VisionKit DataScanner fallback (live camera only — does not replace AVFoundation scanner)
    @State private var showVisionKitScannerFallback = false

    // Manual barcode entry
    @State private var manualBarcodeText = ""
    @FocusState private var isManualBarcodeFocused: Bool

    // Ingredient photo capture states
    @State private var showIngredientCapture = false
    @State private var quickSafetyResult: QuickSafetyResult?
    @State private var showQuickResults = false
    @State private var isCheckingSafety = false

    // Unified loading overlay states
    @State private var isShowingLoadingOverlay = false
    @State private var loadingProgress: CGFloat = 0.0
    @State private var loadingStep = 0
    @State private var loadingMode: ScannerView.LoadingMode = .product // Use .product for Green color
    
    // 🚀 NEW: Instant preview state
    @State private var productPreview: ProductPreview?
    @State private var showPreviewCard = false
    
    struct ProductPreview {
        let barcode: String
        let name: String
        let brand: String?
        let imageUrl: String?
        let nutriscoreGrade: String?
    }

    enum ScannerAlert: Identifiable {
        case cameraAccess
        case pickedImageError(String)
        case lookupTimeout

        var id: String {
            switch self {
            case .cameraAccess:
                return "cameraAccess"
            case .pickedImageError:
                return "pickedImageError"
            case .lookupTimeout:
                return "lookupTimeout"
            }
        }
    }
    
    private var isUsingPickedPhoto: Bool {
        isProcessingPickedPhoto || isDecodingPickedImage || scanPreviewImage != nil
    }

    private var isInPhotoReviewMode: Bool {
        scanPreviewImage != nil && !isDecodingPickedImage && !isProcessingPickedPhoto
    }

    private var isVisionKitScannerAvailable: Bool {
        VisionKitBarcodeScannerSupport.isAvailable
    }

    private var shouldOfferVisionKitFallback: Bool {
        isVisionKitScannerAvailable
            && scanPreviewImage == nil
            && !isAnalyzing
            && !isDecodingPickedImage
            && (scanner.cameraUnavailable || scanner.cameraPermissionDenied)
    }

    var body: some View {
        ZStack {
            // Camera preview, or the photo the user picked from the library
            Group {
                if let preview = scanPreviewImage {
                    Color.black
                    GeometryReader { geo in
                        Image(uiImage: preview)
                            .resizable()
                            .scaledToFit()
                            .frame(width: geo.size.width, height: geo.size.height)
                            .position(x: geo.size.width / 2, y: geo.size.height / 2)
                    }
                } else {
                    CameraPreview(session: scanner.session)
                }
            }
            .ignoresSafeArea()
            
            // Scanning Overlay
            VStack {
                // Top Bar
                HStack {
                    if isInPhotoReviewMode || pickedPhotoFailed {
                        Button(action: resetToLiveCamera) {
                            HStack(spacing: 6) {
                                Image(systemName: "chevron.left")
                                Text("Back")
                            }
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .shadow(radius: 4)
                        }
                    } else {
                        Button(action: { dismiss() }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 32))
                                .foregroundColor(.white)
                                .shadow(radius: 4)
                        }
                    }
                    
                    Spacer()

                    Button(action: openBarcodePhotoPicker) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 26))
                            .foregroundColor(.white)
                            .shadow(radius: 4)
                    }
                    .accessibilityLabel("Pick barcode image")
                    
                    if scanner.torchAvailable {
                        Button(action: { scanner.toggleTorch() }) {
                            Image(systemName: scanner.torchOn ? "flashlight.on.fill" : "flashlight.off.fill")
                                .font(.system(size: 28))
                                .foregroundColor(.white)
                                .shadow(radius: 4)
                        }
                    }
                }
                .padding()
                
                Spacer()
                
                // Scanning Frame
                VStack {
                    if isAnalyzing && !isShowingLoadingOverlay {
                        VStack(spacing: 16) {
                            ProgressView()
                                .scaleEffect(1.5)
                                .tint(.white)
                            
                            Text("Looking up product...")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(.white)
                        }
                        .padding(24)
                        .background(Color.black.opacity(0.7))
                        .cornerRadius(16)
                    } else if isDecodingPickedImage || isProcessingPickedPhoto {
                        VStack(spacing: 12) {
                            ProgressView()
                                .scaleEffect(1.4)
                                .tint(.white)

                            Text(isProcessingPickedPhoto && !isDecodingPickedImage
                                 ? "Loading selected photo…"
                                 : "Reading barcode from photo…")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(.white)
                        }
                        .padding(24)
                        .background(Color.black.opacity(0.7))
                        .cornerRadius(16)
                    } else if let barcode = scanner.detectedBarcode {
                        VStack(spacing: 12) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 44))
                                .foregroundColor(Theme.primary)
                            
                            Text("Barcode Detected")
                                .font(.system(size: 17, weight: .bold))
                                .foregroundColor(.white)
                            
                            Text(barcode)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(.white.opacity(0.9))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Color.white.opacity(0.2))
                                .cornerRadius(8)
                        }
                        .padding(24)
                        .background(Color.black.opacity(0.7))
                        .cornerRadius(16)
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.9).combined(with: .opacity),
                            removal: .scale(scale: 1.05).combined(with: .opacity)
                        ))
                    } else if pickedPhotoFailed {
                        VStack(spacing: 16) {
                            Image(systemName: "barcode.viewfinder")
                                .font(.system(size: 48))
                                .foregroundColor(.white)

                            Text("No barcode found in photo")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(.white)

                            Text("Try another photo or enter the number below")
                                .font(.system(size: 14))
                                .foregroundColor(.white.opacity(0.8))

                            HStack(spacing: 12) {
                                Button(action: resetToLiveCamera) {
                                    Text("Use Camera")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 10)
                                        .background(Color.white.opacity(0.2))
                                        .cornerRadius(10)
                                }

                                Button(action: retryBarcodeDecodeFromPreview) {
                                    Text("Retry Scan")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 10)
                                        .background(Color.white.opacity(0.2))
                                        .cornerRadius(10)
                                }

                                Button(action: openBarcodePhotoPicker) {
                                    Text("Try Another Photo")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 10)
                                        .background(Theme.primary)
                                        .cornerRadius(10)
                                }
                            }
                        }
                        .padding(24)
                        .background(Color.black.opacity(0.7))
                        .cornerRadius(16)
                    } else {
                        VStack(spacing: 12) {
                            Image(systemName: "barcode.viewfinder")
                                .font(.system(size: 64))
                                .foregroundColor(.white)
                            
                            Text("Point camera at barcode")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(.white)
                            
                            Text("Product will be scanned automatically")
                                .font(.system(size: 14))
                                .foregroundColor(.white.opacity(0.8))
                        }
                        .padding(24)
                        .background(Color.black.opacity(0.7))
                        .cornerRadius(16)
                    }
                }
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: productPreview != nil)
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isAnalyzing)
                Spacer()
                
                VStack(spacing: 12) {
                    if shouldOfferVisionKitFallback {
                        visionKitFallbackPrompt
                    }

                    if !isManualBarcodeFocused && !pickedPhotoFailed {
                        Text(isUsingPickedPhoto ? "Scanning barcode in photo" : "Align barcode within frame")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(Color.black.opacity(0.6))
                            .cornerRadius(20)
                    }

                    if !isAnalyzing && !isShowingLoadingOverlay && !isDecodingPickedImage {
                        manualBarcodeEntrySection
                    }
                }
                .padding(.bottom, 16)
            }
            
            // Scanning Reticle — hide when reviewing a picked photo
            if scanPreviewImage == nil {
            Rectangle()
                .stroke(scanner.detectedBarcode != nil ? Theme.primary : Color.white, lineWidth: 3)
                .frame(width: 280, height: 160)
                .overlay(
                    // Corner indicators
                    GeometryReader { geo in
                        ForEach(0..<4) { index in
                            Path { path in
                                let cornerLength: CGFloat = 20
                                let x: CGFloat = index % 2 == 0 ? 0 : geo.size.width
                                let y: CGFloat = index < 2 ? 0 : geo.size.height
                                
                                if index % 2 == 0 {
                                    path.move(to: CGPoint(x: x, y: y))
                                    path.addLine(to: CGPoint(x: x + cornerLength, y: y))
                                    path.move(to: CGPoint(x: x, y: y))
                                    path.addLine(to: CGPoint(x: x, y: y + (index < 2 ? cornerLength : -cornerLength)))
                                } else {
                                    path.move(to: CGPoint(x: x, y: y))
                                    path.addLine(to: CGPoint(x: x - cornerLength, y: y))
                                    path.move(to: CGPoint(x: x, y: y))
                                    path.addLine(to: CGPoint(x: x, y: y + (index < 2 ? cornerLength : -cornerLength)))
                                }
                            }
                            .stroke(scanner.detectedBarcode != nil ? Theme.primary : Color.white, lineWidth: 4)
                        }
                    }
                )
                .animation(.easeInOut(duration: 0.3), value: scanner.detectedBarcode)
                .overlay {
                    // Animated scan line
                    ScanLineAnimation(
                        isScanning: scanner.detectedBarcode == nil && !isAnalyzing && !isUsingPickedPhoto,
                        isDetected: scanner.detectedBarcode != nil
                    )
                }
            }

            if isShowingLoadingOverlay {
                AnalysisLoadingOverlay(
                    progress: loadingProgress,
                    step: loadingStep,
                    mode: loadingMode,
                    productName: productPreview?.name,
                    productBrand: productPreview?.brand
                )
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.95).combined(with: .opacity),
                    removal: .scale(scale: 1.05).combined(with: .opacity)
                ))
                .zIndex(100)
                .overlay(alignment: .bottom) {
                    Button {
                        cancelCurrentOperation()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "stop.circle.fill")
                            Text("Stop")
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.black.opacity(0.35))
                        .cornerRadius(12)
                    }
                    .padding(.bottom, 40)
                }
            }

            if isUsingPickedPhoto && (isDecodingPickedImage || isProcessingPickedPhoto) {
                ZStack {
                    Color.black.opacity(0.45)
                        .ignoresSafeArea()

                    VStack(spacing: 16) {
                        Button {
                            cancelCurrentOperation()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "stop.circle.fill")
                                Text("Stop")
                            }
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(Color.white.opacity(0.18))
                            .cornerRadius(12)
                        }
                    }
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 120)
                }
                .zIndex(200)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    isManualBarcodeFocused = false
                }
            }
        }
        .onAppear {
            scanner.startScanning()
        }
        .onDisappear {
            debounceTask?.cancel()
            debounceTask = nil
            lookupDeadlineTask?.cancel()
            lookupDeadlineTask = nil
            activeBarcodeLookupTask?.cancel()
            activeBarcodeLookupTask = nil
            activeBarcodeDecodeTask?.cancel()
            activeBarcodeDecodeTask = nil
            scanner.stopScanning()
        }
        .onChange(of: scanner.detectedBarcode) { _, newValue in
            guard let barcode = newValue,
                  !scanCooldown,
                  !isAnalyzing,
                  !isUsingPickedPhoto else { return }

            debounceTask?.cancel()
            debounceTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 200_000_000)
                guard !Task.isCancelled else { return }
                guard let current = scanner.detectedBarcode,
                      current == barcode,
                      current != lastScannedBarcode,
                      !scanCooldown,
                      !isAnalyzing else { return }

                let normalized = BarcodeScanner.normalizeProductBarcode(current)
                AppLogger.debug("📱 Barcode detected (debounced): \(normalized)")
                scanBarcode(normalized)
            }
        }
        .onChange(of: pickedBarcodeItem) { _, newItem in
            guard let newItem else { return }
            processPickedBarcodePhoto(from: newItem)
        }
        .fullScreenCover(isPresented: $showResults) {
            if let result = analysisResult {
                ResultsView(result: result, onDismiss: {
                    showResults = false
                    analysisResult = nil
                    lastScannedBarcode = ""
                    manualBarcodeText = ""
                    scanner.detectedBarcode = nil
                    scanPreviewImage = nil
                    isProcessingPickedPhoto = false
                    pickedPhotoFailed = false

                    // Resume scanning after short delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        scanCooldown = false
                    }
                })
            }
        }
        .fullScreenCover(isPresented: $showVisualScanner, onDismiss: {
            // Reset cooldown so barcode scanning resumes after returning from visual scanner
            scanCooldown = false
            lastScannedBarcode = ""
        }) {
            VisualProductScannerView(preferencesManager: PreferencesManager.shared)
        }
        .sheet(isPresented: $showIngredientCapture) {
            IngredientPhotoCaptureView(
                isCheckingSafety: $isCheckingSafety,
                onImageCaptured: { image in
                    showIngredientCapture = false
                    isCheckingSafety = true
                    Task {
                        let result = await NetworkService.shared.quickSafetyCheckFromPhoto(
                            image: image,
                            preferences: preferencesManager.preferences
                        )
                        await MainActor.run {
                            isCheckingSafety = false
                            if let result = result {
                                quickSafetyResult = result
                                showQuickResults = true
                            }
                        }
                    }
                }
            )
        }
        .sheet(isPresented: $showProductNotFoundFlow, onDismiss: {
            notFoundPreviewImage = nil
            scanPreviewImage = nil
            scanCooldown = false
            scanner.detectedBarcode = nil
        }) {
            MissingProductSubmissionView(
                barcode: notFoundBarcode.isEmpty ? lastScannedBarcode : notFoundBarcode,
                previewImage: notFoundPreviewImage,
                onSkip: {
                    showProductNotFoundFlow = false
                    notFoundPreviewImage = nil
                    scanPreviewImage = nil
                    scanCooldown = false
                },
                onScanIngredients: {
                    showProductNotFoundFlow = false
                    showIngredientCapture = true
                }
            )
        }
        .photosPicker(isPresented: $showBarcodeImagePicker, selection: $pickedBarcodeItem, matching: .images)
        .fullScreenCover(isPresented: $showVisionKitScannerFallback) {
            if #available(iOS 16.0, *) {
                VisionKitBarcodeScannerSheet { barcode in
                    handleVisionKitBarcodeDetected(barcode)
                }
            }
        }
        .fullScreenCover(isPresented: $showQuickResults) {
            if let safetyResult = quickSafetyResult {
                QuickSafetyResultView(
                    result: safetyResult,
                    onDismiss: {
                        showQuickResults = false
                        quickSafetyResult = nil
                        lastScannedBarcode = ""
                        scanCooldown = false
                    },
                    onRunFullAnalysis: { ingredients, productName in
                        showQuickResults = false
                        quickSafetyResult = nil
                        // Run full analysis with extracted ingredients
                        runFullAnalysisFromIngredients(ingredients, productName: productName)
                    }
                )
            }
        }
        .overlay {
            if isCheckingSafety {
                ZStack {
                    Color.black.opacity(0.7)
                        .ignoresSafeArea()
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                            .tint(Theme.primary)
                        Text("Checking ingredients...")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.white)
                    }
                    .padding(32)
                    .background(Color.black.opacity(0.8))
                    .cornerRadius(16)
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: isCheckingSafety)
        .onChange(of: scanner.cameraPermissionDenied) { _, denied in
            if denied {
                activeAlert = .cameraAccess
            }
        }
        .alert(item: $activeAlert) { alert in
            switch alert {
            case .cameraAccess:
                return Alert(
                    title: Text("Camera Access Required"),
                    message: Text("Ethica needs camera access to scan product barcodes. Please enable it in Settings."),
                    primaryButton: .default(Text("Open Settings"), action: {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }),
                    secondaryButton: .cancel(Text("Cancel"), action: {
                        dismiss()
                    })
                )
            case .pickedImageError(let message):
                return Alert(
                    title: Text("Couldn’t Read Barcode"),
                    message: Text(message),
                    dismissButton: .default(Text("OK"))
                )
            case .lookupTimeout:
                return Alert(
                    title: Text("Taking Too Long"),
                    message: Text("The product lookup is taking longer than expected. Please check your connection and try again."),
                    dismissButton: .default(Text("OK"), action: {
                        isShowingLoadingOverlay = false
                        isAnalyzing = false
                        scanCooldown = false
                        lastScannedBarcode = ""
                    })
                )
            }
        }
    }
    
    // MARK: - Manual Barcode Entry

    private var visionKitFallbackPrompt: some View {
        VStack(spacing: 10) {
            Text("Camera preview unavailable")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)

            Text("Try Apple’s built-in scanner as a fallback.")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.8))
                .multilineTextAlignment(.center)

            Button(action: openVisionKitScannerFallback) {
                Text("Open Apple Scanner")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Theme.primary)
                    .cornerRadius(10)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(Color.black.opacity(0.72))
        .cornerRadius(14)
        .padding(.horizontal, 16)
    }

    private var manualBarcodeEntrySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Or enter barcode manually")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.85))

            HStack(spacing: 10) {
                TextField("EAN / UPC (8–14 digits)", text: $manualBarcodeText)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .focused($isManualBarcodeFocused)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Color.white.opacity(0.15))
                    .cornerRadius(12)
                    .foregroundColor(.white)
                    .tint(Theme.primary)
                    .submitLabel(.search)
                    .onSubmit(submitManualBarcode)
                    .onChange(of: manualBarcodeText) { _, newValue in
                        let digitsOnly = newValue.filter(\.isNumber)
                        if digitsOnly != newValue {
                            manualBarcodeText = digitsOnly
                        }
                    }

                Button(action: submitManualBarcode) {
                    Text("Look up")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(canSubmitManualBarcode ? Theme.primary : Color.white.opacity(0.25))
                        .cornerRadius(12)
                }
                .disabled(!canSubmitManualBarcode)
            }

            if isVisionKitScannerAvailable && scanPreviewImage == nil {
                Button(action: openVisionKitScannerFallback) {
                    HStack(spacing: 6) {
                        Image(systemName: "barcode.viewfinder")
                        Text("Alternate scanner (Apple VisionKit)")
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Theme.primary)
                }
                .padding(.top, 4)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background(Color.black.opacity(0.7))
        .cornerRadius(16)
        .padding(.horizontal, 16)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Manual barcode entry")
    }

    private var canSubmitManualBarcode: Bool {
        let digits = manualBarcodeText.trimmingCharacters(in: .whitespacesAndNewlines)
        return digits.count >= 8 && !isAnalyzing && !isDecodingPickedImage
    }

    @MainActor
    private func openVisionKitScannerFallback() {
        guard isVisionKitScannerAvailable else { return }
        isManualBarcodeFocused = false
        showVisionKitScannerFallback = true
    }

    @MainActor
    private func handleVisionKitBarcodeDetected(_ barcode: String) {
        let normalized = BarcodeScanner.normalizeProductBarcode(barcode)
        guard BarcodeScanner.isValidProductBarcode(normalized) else {
            ToastManager.shared.warning("Looks like a barcode isn’t there (or it’s unsupported). Try an EAN/UPC barcode.")
            return
        }

        scanner.detectedBarcode = normalized
        scanCooldown = false
        lastScannedBarcode = ""
        scanBarcode(normalized)
    }

    @MainActor
    private func openBarcodePhotoPicker() {
        cancelInFlightScan(showToast: false)
        pickedPhotoFailed = false
        scanPreviewImage = nil
        isProcessingPickedPhoto = false
        pickedBarcodeItem = nil
        showBarcodeImagePicker = true
    }

    @MainActor
    private func resetToLiveCamera() {
        cancelInFlightScan(showToast: false)
        pickedPhotoFailed = false
        scanPreviewImage = nil
        isProcessingPickedPhoto = false
        pickedBarcodeItem = nil
        scanner.detectedBarcode = nil
        lastScannedBarcode = ""
        scanCooldown = false
        scanner.startScanning()
    }

    private func submitManualBarcode() {
        let barcode = manualBarcodeText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSubmitManualBarcode else { return }

        isManualBarcodeFocused = false
        scanCooldown = false
        lastScannedBarcode = ""
        scanBarcode(barcode)
    }

    // MARK: - Nutriscore Color Helper
    private func nutriscoreColor(_ grade: String) -> Color {
        switch grade.uppercased() {
        case "A": return Color(hex: "038141")
        case "B": return Color(hex: "85BB2F")
        case "C": return Color(hex: "FECB02")
        case "D": return Color(hex: "EE8100")
        case "E": return Color(hex: "E63E11")
        default: return .white
        }
    }
    
    private func simulateAnalysisProgress() {
        // Reset state
        loadingProgress = 0.0
        loadingStep = 0
        
        // Step 1: Scanning (0.0 - 0.3)
        withAnimation(.linear(duration: 0.5)) {
            loadingProgress = 0.3
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            // Step 2: Searching (0.3 - 0.6)
            loadingStep = 1
            withAnimation(.linear(duration: 0.8)) {
                loadingProgress = 0.6
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                // Step 3: Checking Safety (0.6 - 0.85)
                loadingStep = 2
                withAnimation(.linear(duration: 0.8)) {
                    loadingProgress = 0.85
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    // Step 4: Calculating Impact (0.85 - 1.0)
                    loadingStep = 3
                    withAnimation(.linear(duration: 0.4)) {
                        loadingProgress = 1.0
                    }
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        loadingStep = 4
                    }
                }
            }
        }
    }
    
    private func processPickedBarcodePhoto(from item: PhotosPickerItem) {
        cancelInFlightScan(showToast: false)

        activeBarcodeDecodeTask?.cancel()
        activeBarcodeDecodeTask = Task {
            await MainActor.run {
                isProcessingPickedPhoto = true
                isDecodingPickedImage = true
                pickedPhotoFailed = false
                scanPreviewImage = nil
                scanner.detectedBarcode = nil
                lastScannedBarcode = ""
                scanCooldown = true
                showProductNotFoundFlow = false
            }

            let image = await loadPickedBarcodeImage(from: item)
            if Task.isCancelled { return }

            guard let image else {
                await MainActor.run {
                    finishPickedPhotoProcessing()
                    pickedBarcodeItem = nil
                }
                return
            }

            await MainActor.run {
                scanPreviewImage = image
                isProcessingPickedPhoto = false
                pickedBarcodeItem = nil
            }

            let decodedBarcode = await decodeBarcodeFromPhoto(image)

            await MainActor.run { isDecodingPickedImage = false }

            if let decoded = decodedBarcode {
                await MainActor.run {
                    pickedPhotoFailed = false
                    isProcessingPickedPhoto = false
                    scanner.detectedBarcode = decoded
                    scanCooldown = false
                    scanBarcode(decoded)
                }
            } else {
                await MainActor.run {
                    finishPickedPhotoProcessing(keepPreview: true, failed: true)
                    ToastManager.shared.warning("Looks like a barcode isn’t there. Try a clearer photo with the barcode fully visible.")
                }
            }
        }
    }

    private func decodeBarcodeFromPhoto(_ image: UIImage) async -> String? {
        if Task.isCancelled { return nil }
        return await BarcodeScanner().detectBestProductBarcode(in: image)
    }

    @MainActor
    private func retryBarcodeDecodeFromPreview() {
        guard let image = scanPreviewImage else {
            openBarcodePhotoPicker()
            return
        }

        pickedPhotoFailed = false
        isDecodingPickedImage = true
        scanner.detectedBarcode = nil

        activeBarcodeDecodeTask?.cancel()
        activeBarcodeDecodeTask = Task {
            let decoded = await decodeBarcodeFromPhoto(image)
            if Task.isCancelled { return }

            await MainActor.run { isDecodingPickedImage = false }

            if let decoded {
                pickedPhotoFailed = false
                scanner.detectedBarcode = decoded
                scanCooldown = false
                scanBarcode(decoded)
            } else {
                finishPickedPhotoProcessing(keepPreview: true, failed: true)
            }
        }
    }

    private func loadPickedBarcodeImage(from item: PhotosPickerItem) async -> UIImage? {
        guard let data = try? await item.loadTransferable(type: Data.self) else {
            return nil
        }
        return BarcodeScanner.imageForBarcodeScan(from: data)
    }

    @MainActor
    private func finishPickedPhotoProcessing(keepPreview: Bool = false, failed: Bool = false) {
        isDecodingPickedImage = false
        isProcessingPickedPhoto = false
        scanCooldown = false
        pickedPhotoFailed = failed && keepPreview
        if !keepPreview {
            scanPreviewImage = nil
        }
    }

    private func scanBarcode(_ barcode: String) {
        AppLogger.debug("🔍 scanBarcode called with: \(barcode)")
        guard !isAnalyzing else { 
            AppLogger.warning("⚠️ Already analyzing, skipping")
            return 
        }

        let normalizedBarcode = BarcodeScanner.normalizeProductBarcode(barcode)
        guard BarcodeScanner.isValidProductBarcode(normalizedBarcode) else {
            ToastManager.shared.warning("Looks like a barcode isn’t there (or it’s unsupported). Try an EAN/UPC barcode.")
            scanCooldown = false
            lastScannedBarcode = ""
            return
        }
        
        AppLogger.debug("🚀 Starting analysis for: \(normalizedBarcode)")
        isAnalyzing = true
        scanCooldown = true
        lastScannedBarcode = normalizedBarcode
        productPreview = nil
        showProductNotFoundFlow = false
        
        isShowingLoadingOverlay = true
        loadingMode = .barcode
        loadingProgress = 0.2
        loadingStep = 1
        
        //  Play scan sound + haptic feedback
        AudioServicesPlaySystemSound(1057) // Scanner beep
        HapticManager.shared.trigger(.success)

        lookupDeadlineTask?.cancel()
        lookupDeadlineTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled else { return }
            guard isAnalyzing || isShowingLoadingOverlay else { return }
            AppLogger.info(" Barcode lookup deadline — showing not-found flow")
            activeBarcodeLookupTask?.cancel()
            presentProductNotFound(barcode: normalizedBarcode)
        }

        activeBarcodeLookupTask?.cancel()
        activeBarcodeLookupTask = Task { @MainActor in
            AppLogger.debug(" Starting fast barcode lookup...")

            if Task.isCancelled { return }

            let resolvedResult = await productDatabase.lookupBarcodeForScan(
                normalizedBarcode,
                preferences: preferencesManager.preferences
            )

            lookupDeadlineTask?.cancel()
            lookupDeadlineTask = nil

            if Task.isCancelled { return }

            if let result = resolvedResult {
                AppLogger.debug("✅ Got result: \(result.productName)")
                let scanHistory = ScanHistory(from: result)
                HistoryService.shared.saveScan(scanHistory)
                
                isShowingLoadingOverlay = false
                analysisResult = result
                isAnalyzing = false
                productPreview = nil
                showResults = true
            } else {
                AppLogger.info("📷 Barcode not in database — showing contribution flow")
                presentProductNotFound(barcode: normalizedBarcode)
            }
        }
    }

    @MainActor
    private func presentProductNotFound(barcode: String) {
        lookupDeadlineTask?.cancel()
        lookupDeadlineTask = nil
        isShowingLoadingOverlay = false
        isAnalyzing = false
        scanCooldown = false
        productPreview = nil
        notFoundBarcode = barcode
        notFoundPreviewImage = scanPreviewImage
        showProductNotFoundFlow = true
        HapticManager.shared.trigger(.warning)
    }

    private func cancelInFlightScan(showToast: Bool = true) {
        debounceTask?.cancel()
        debounceTask = nil
        activeBarcodeDecodeTask?.cancel()
        activeBarcodeDecodeTask = nil
        lookupDeadlineTask?.cancel()
        lookupDeadlineTask = nil
        activeBarcodeLookupTask?.cancel()
        activeBarcodeLookupTask = nil

        isDecodingPickedImage = false
        isProcessingPickedPhoto = false
        pickedPhotoFailed = false
        isShowingLoadingOverlay = false
        isAnalyzing = false
        scanCooldown = false
        showProductNotFoundFlow = false
        lastScannedBarcode = ""
        notFoundPreviewImage = nil
        scanPreviewImage = nil
        pickedBarcodeItem = nil
        isManualBarcodeFocused = false
        scanner.detectedBarcode = nil

        if showToast {
            ToastManager.shared.info("Stopped. You can try again.")
        }
    }

    private func cancelCurrentOperation(showToast: Bool = true) {
        cancelInFlightScan(showToast: showToast)
    }

    private func isLikelyProductBarcode(_ barcode: String) -> Bool {
        BarcodeScanner.isValidProductBarcode(BarcodeScanner.normalizeProductBarcode(barcode))
    }

    private func runFullAnalysisFromIngredients(_ ingredients: [String], productName: String?) {
        isAnalyzing = true
        scanCooldown = true
        isShowingLoadingOverlay = true
        loadingMode = .product
        simulateAnalysisProgress()

        Task {
            let result = await NetworkService.shared.analyzeIngredientsDirectly(
                ingredients: ingredients,
                productName: productName ?? "Unknown Product",
                preferences: preferencesManager.preferences
            )
            await MainActor.run {
                isShowingLoadingOverlay = false
                isAnalyzing = false
                if let result = result {
                    analysisResult = result
                    showResults = true
                }
            }
        }
    }

    private func withTimeout<T>(
        seconds: Double,
        showsTimeoutAlert: Bool = true,
        operation: @escaping () async -> T
    ) async -> (value: T?, timedOut: Bool) {
        await withTaskGroup(of: (T?, Bool).self) { group in
            group.addTask {
                let value = await operation()
                return (value, false)
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                return (nil, true)
            }

            let first = await group.next() ?? (nil, true)
            group.cancelAll()

            if first.1, showsTimeoutAlert {
                await MainActor.run {
                    activeAlert = .lookupTimeout
                }
            }

            return first
        }
    }
}

// MARK: - Ingredient Photo Capture View
struct IngredientPhotoCaptureView: View {
    @Binding var isCheckingSafety: Bool
    let onImageCaptured: (UIImage) -> Void
    @Environment(\.dismiss) var dismiss
    @State private var showCamera = false
    @State private var showPhotoLibrary = false
    @State private var capturedImage: UIImage?

    var body: some View {
        NavigationView {
            ZStack {
                Theme.backgroundPrimary
                    .ignoresSafeArea()

                VStack(spacing: Spacing.lg) {
                    Spacer()

                    Image(systemName: "doc.text.viewfinder")
                        .font(.system(size: 64))
                        .foregroundColor(Theme.primary)

                    Text("Scan Ingredient List")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(Theme.textPrimary)

                    Text("Take a photo of the ingredient list on the product packaging")
                        .font(.system(size: 15))
                        .foregroundColor(Theme.textTertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Spacing.xl)

                    Spacer()

                    VStack(spacing: Spacing.sm) {
                        Button {
                            showCamera = true
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "camera.fill")
                                Text("Take Photo")
                            }
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Theme.primary)
                            .cornerRadius(Spacing.radiusMD)
                        }

                        Button {
                            showPhotoLibrary = true
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "photo.on.rectangle")
                                Text("Choose from Library")
                            }
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(Theme.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.white.opacity(0.08))
                            .cornerRadius(Spacing.radiusMD)
                        }
                    }
                    .padding(.horizontal, Spacing.screenHorizontal)
                    .padding(.bottom, Spacing.xl)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(Theme.primary)
                }
            }
            .sheet(isPresented: $showCamera) {
                CameraPicker(image: $capturedImage)
            }
            .sheet(isPresented: $showPhotoLibrary) {
                ImagePicker(image: $capturedImage)
            }
            .onChange(of: capturedImage) { _, newImage in
                if let image = newImage {
                    onImageCaptured(image)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Camera Preview
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .black
        
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)
        
        context.coordinator.previewLayer = previewLayer
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async {
            context.coordinator.previewLayer?.frame = uiView.bounds
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator {
        var previewLayer: AVCaptureVideoPreviewLayer?
    }
}

// MARK: - Barcode Scanner Manager
class BarcodeScannerManager: NSObject, ObservableObject {
    @Published var detectedBarcode: String?
    @Published var torchOn = false
    @Published var torchAvailable = false
    @Published var cameraPermissionDenied = false
    @Published var cameraUnavailable = false

    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "barcode.session.queue")
    private var captureDevice: AVCaptureDevice?
    private var isSessionConfigured = false

    override init() {
        super.init()
        checkTorchAvailability()
    }

    func startScanning() {
        checkCameraPermission { [weak self] granted in
            guard granted else { return }
            self?.sessionQueue.async {
                self?.setupCamera()
            }
        }
    }

    /// Simulator-only: retry after serve-sim injects a Mac webcam feed.
    func retryCameraIfNeeded() {
        #if targetEnvironment(simulator)
        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard self.cameraUnavailable || !self.session.isRunning else { return }
            guard AVCaptureDevice.default(for: .video) != nil else { return }
            AppLogger.info("📷 Simulator camera feed detected — restarting capture session")
            self.setupCamera(forceReconfigure: self.isSessionConfigured)
        }
        #endif
    }

    private func checkCameraPermission(completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if !granted {
                    DispatchQueue.main.async { self?.cameraPermissionDenied = true }
                }
                completion(granted)
            }
        case .denied, .restricted:
            DispatchQueue.main.async { [weak self] in self?.cameraPermissionDenied = true }
            completion(false)
        @unknown default:
            completion(false)
        }
    }
    
    func stopScanning() {
        sessionQueue.async { [weak self] in
            self?.session.stopRunning()
        }
    }
    
    func toggleTorch() {
        guard let device = captureDevice, device.hasTorch else { return }
        
        do {
            try device.lockForConfiguration()
            device.torchMode = torchOn ? .off : .on
            device.unlockForConfiguration()
            
            DispatchQueue.main.async {
                self.torchOn.toggle()
            }
        } catch {
            AppLogger.error("❌ Torch error: \(error)")
        }
    }
    
    private func checkTorchAvailability() {
        if let device = AVCaptureDevice.default(for: .video) {
            torchAvailable = device.hasTorch
        }
    }
    
    private func setupCamera(forceReconfigure: Bool = false) {
        if forceReconfigure {
            session.beginConfiguration()
            session.inputs.forEach { session.removeInput($0) }
            session.outputs.forEach { session.removeOutput($0) }
            session.commitConfiguration()
            isSessionConfigured = false
        }

        if isSessionConfigured {
            if !session.isRunning {
                session.startRunning()
            }
            DispatchQueue.main.async { [weak self] in
                self?.cameraUnavailable = false
            }
            return
        }

        guard let device = AVCaptureDevice.default(for: .video) else {
            AppLogger.warning("❌ No camera available (Simulator has no camera unless Mac webcam is injected)")
            DispatchQueue.main.async { [weak self] in
                self?.cameraUnavailable = true
            }
            return
        }
        
        captureDevice = device
        DispatchQueue.main.async { [weak self] in
            self?.cameraUnavailable = false
        }
        
        do {
            let input = try AVCaptureDeviceInput(device: device)
            
            session.beginConfiguration()
            if session.canAddInput(input) {
                session.addInput(input)
            }
            
            let output = AVCaptureMetadataOutput()
            
            if session.canAddOutput(output) {
                session.addOutput(output)
                
                output.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
                output.metadataObjectTypes = [
                    .ean13, .ean8, .upce, .code128, .code39, .code93,
                    .qr, .pdf417, .aztec, .dataMatrix
                ]
            }
            session.commitConfiguration()
            isSessionConfigured = true
            
            if !session.isRunning {
                session.startRunning()
            }
            
        } catch {
            AppLogger.error("❌ Camera setup error: \(error)")
            DispatchQueue.main.async { [weak self] in
                self?.cameraUnavailable = true
            }
        }
    }
}

// MARK: - Metadata Output Delegate
extension BarcodeScannerManager: AVCaptureMetadataOutputObjectsDelegate {
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard let metadataObject = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let stringValue = metadataObject.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !stringValue.isEmpty else {
            // Keep last detection visible — clearing causes flicker and breaks debounce.
            return
        }

        let normalized = BarcodeScanner.normalizeProductBarcode(stringValue)
        if detectedBarcode != normalized {
            detectedBarcode = normalized
        }
    }
}

// MARK: - Scan Line Animation

struct ScanLineAnimation: View {
    let isScanning: Bool
    let isDetected: Bool

    @State private var lineOffset: CGFloat = -1

    var body: some View {
        GeometryReader { geo in
            if isScanning {
                // Green laser line
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.clear,
                                Theme.primary.opacity(0.6),
                                Theme.primary,
                                Theme.primary.opacity(0.6),
                                Color.clear
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 3)
                    .shadow(color: Theme.primary.opacity(0.8), radius: 8, y: 0)
                    .offset(y: lineOffset * geo.size.height / 2)
                    .onAppear {
                        withAnimation(
                            .linear(duration: 2.0)
                            .repeatForever(autoreverses: true)
                        ) {
                            lineOffset = 1
                        }
                    }
            }

            if isDetected {
                // Flash green on detection
                RoundedRectangle(cornerRadius: 4)
                    .fill(Theme.primary.opacity(0.15))
                    .transition(.opacity)
            }
        }
        .allowsHitTesting(false)
    }
}
