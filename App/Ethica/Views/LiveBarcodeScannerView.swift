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
    @State private var showNotFound = false
    @State private var notFoundBarcode = ""
    @State private var debounceTimer: Timer?
    @State private var showVisualScanner = false

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
    
    var body: some View {
        ZStack {
            // Camera Preview
            CameraPreview(session: scanner.session)
                .ignoresSafeArea()
            
            // Scanning Overlay
            VStack {
                // Top Bar
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(.white)
                            .shadow(radius: 4)
                    }
                    
                    Spacer()
                    
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
                    } else if showNotFound {
                        // Product not found — show options to scan ingredients or try again
                        VStack(spacing: 16) {
                            Image(systemName: "exclamationmark.magnifyingglass")
                                .font(.system(size: 44))
                                .foregroundColor(Theme.warning)

                            Text("Product Not in Database")
                                .font(.system(size: 17, weight: .bold))
                                .foregroundColor(.white)

                            Text("Scan the ingredient list for a quick safety check")
                                .font(.system(size: 14))
                                .foregroundColor(.white.opacity(0.8))
                                .multilineTextAlignment(.center)

                            // Primary: Scan Ingredients
                            Button {
                                showNotFound = false
                                showIngredientCapture = true
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "camera.fill")
                                    Text("Scan Ingredients")
                                }
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Theme.primary)
                                .cornerRadius(12)
                            }

                            // Secondary: Try Another Barcode
                            Button {
                                showNotFound = false
                                lastScannedBarcode = ""
                                scanCooldown = false
                            } label: {
                                Text("Try Another Barcode")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.white.opacity(0.7))
                            }
                        }
                        .padding(24)
                        .frame(maxWidth: 300)
                        .background(Color.black.opacity(0.85))
                        .cornerRadius(16)
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.8).combined(with: .opacity),
                            removal: .scale(scale: 1.1).combined(with: .opacity)
                        ))
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
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: showNotFound)
                
                Spacer()
                
                // Instruction
                Text(showNotFound ? "Choose an option above" : "Align barcode within frame")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.black.opacity(0.6))
                    .cornerRadius(20)
                    .padding(.bottom, 32)
            }
            
            // Scanning Reticle
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
                        isScanning: scanner.detectedBarcode == nil && !isAnalyzing,
                        isDetected: scanner.detectedBarcode != nil
                    )
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
            }
        }
        .onAppear {
            scanner.startScanning()
        }
        .onDisappear {
            debounceTimer?.invalidate()
            debounceTimer = nil
            scanner.stopScanning()
        }
        .onChange(of: scanner.detectedBarcode) { oldValue, newValue in
            guard let barcode = newValue, !scanCooldown else { return }

            // Cancel previous debounce timer
            debounceTimer?.invalidate()

            // Only scan if barcode is stable for 150ms (reduced from 300ms — preliminary SSE result arrives fast)
            debounceTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: false) { _ in
                // Verify barcode hasn't changed
                guard barcode == scanner.detectedBarcode,
                      barcode != lastScannedBarcode else { return }

                AppLogger.debug("📱 Barcode detected (debounced): \(barcode)")
                // Trigger analysis
                scanBarcode(barcode)
            }
        }
        .fullScreenCover(isPresented: $showResults) {
            if let result = analysisResult {
                ResultsView(result: result, onDismiss: {
                    showResults = false
                    analysisResult = nil
                    lastScannedBarcode = ""

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
        .alert("Camera Access Required", isPresented: $scanner.cameraPermissionDenied) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) { dismiss() }
        } message: {
            Text("Ethica needs camera access to scan product barcodes. Please enable it in Settings.")
        }
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
    
    private func scanBarcode(_ barcode: String) {
        AppLogger.debug("🔍 scanBarcode called with: \(barcode)")
        guard !isAnalyzing else { 
            AppLogger.warning("⚠️ Already analyzing, skipping")
            return 
        }
        
        AppLogger.debug("🚀 Starting analysis for: \(barcode)")
        isAnalyzing = true
        scanCooldown = true
        lastScannedBarcode = barcode
        productPreview = nil
        showNotFound = false
        
        // Start Animation
        isShowingLoadingOverlay = true
        loadingMode = .product // Use .product for Green color
        simulateAnalysisProgress()
        
        // 🔊 Play scan sound + haptic feedback
        AudioServicesPlaySystemSound(1057) // Scanner beep
        HapticManager.shared.trigger(.success)

        Task {
            AppLogger.debug("📡 Starting barcode lookup (SSE streaming)...")

            if let result = await productDatabase.lookupBarcode(barcode, preferences: preferencesManager.preferences) {
                AppLogger.debug("✅ Got result: \(result.productName)")
                // 💾 SAVE TO HISTORY immediately after successful barcode lookup
                let scanHistory = ScanHistory(from: result)
                AppLogger.debug("💾 [LiveBarcodeScanner] Saving barcode scan to history: \(scanHistory.productName)")
                HistoryService.shared.saveScan(scanHistory)
                AppLogger.debug("💾 [LiveBarcodeScanner] Saved barcode scan successfully")
                
                await MainActor.run {
                    AppLogger.debug("🎯 Setting result and showing results screen")
                    isShowingLoadingOverlay = false
                    analysisResult = result
                    isAnalyzing = false
                    productPreview = nil
                    showResults = true
                }
            } else {
                AppLogger.info("📷 Barcode not in database — showing ingredient scan option")
                await MainActor.run {
                    isShowingLoadingOverlay = false
                    isAnalyzing = false
                    productPreview = nil
                    notFoundBarcode = barcode
                    showNotFound = true

                    HapticManager.shared.trigger(.warning)
                }
            }
        }
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

    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "barcode.session.queue")
    private var captureDevice: AVCaptureDevice?

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
    
    private func setupCamera() {
        guard let device = AVCaptureDevice.default(for: .video) else {
            AppLogger.error("❌ No camera available")
            return
        }
        
        captureDevice = device
        
        do {
            let input = try AVCaptureDeviceInput(device: device)
            
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
            
            DispatchQueue.global(qos: .userInitiated).async {
                self.session.startRunning()
            }
            
        } catch {
            AppLogger.error("❌ Camera setup error: \(error)")
        }
    }
}

// MARK: - Metadata Output Delegate
extension BarcodeScannerManager: AVCaptureMetadataOutputObjectsDelegate {
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        
        guard let metadataObject = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let stringValue = metadataObject.stringValue else {
            detectedBarcode = nil
            return
        }
        
        detectedBarcode = stringValue
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
