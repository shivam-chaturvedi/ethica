//
//  VisualProductScannerView.swift
//  Ethica
//
//  AI-Powered Visual Product Recognition - Revolutionary scan anything technology

import SwiftUI
import AVFoundation
import Vision
import Combine

struct VisualProductScannerView: View {
    @ObservedObject var preferencesManager: PreferencesManager
    @StateObject private var scanner = VisualScannerManager()
    @ObservedObject private var networkService = NetworkService.shared
    @Environment(\.dismiss) var dismiss
    
    @State private var analysisResult: AnalysisResult?
    @State private var isAnalyzing = false
    @State private var showResults = false
    @State private var detectedText: [String] = []
    @State private var scanProgress: Double = 0
    @State private var scanStatus = "Point camera at product"
    @State private var capturedImage: UIImage?
    
    // Unified loading overlay states
    @State private var isShowingLoadingOverlay = false
    @State private var loadingProgress: CGFloat = 0.0
    @State private var loadingStep = 0
    @State private var loadingMode: ScannerView.LoadingMode = .visual
    @State private var showError = false
    @State private var errorMessage = ""

    var body: some View {
        ZStack {
            // Camera Preview
            CameraPreview(session: scanner.session)
                .ignoresSafeArea()
            
            // Overlay
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
                
                // Status Display
                VStack(spacing: 16) {
                    if !detectedText.isEmpty && !isAnalyzing {
                        // Text Detected State
                        VStack(spacing: 12) {
                            Image(systemName: "doc.text.viewfinder")
                                .font(.system(size: 44))
                                .foregroundColor(Color(hex: "10B981"))
                            
                            Text("Text Detected")
                                .font(.system(size: 17, weight: .bold))
                                .foregroundColor(.white)
                            
                            Text("\(detectedText.count) items found")
                                .font(.system(size: 14))
                                .foregroundColor(.white.opacity(0.8))
                            
                            Button(action: captureAndAnalyze) {
                                HStack(spacing: 8) {
                                    Image(systemName: "sparkles")
                                    Text("Scan This Product")
                                }
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 12)
                                .background(
                                    LinearGradient(
                                        colors: [Color(hex: "10B981"), Color(hex: "059669")],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .cornerRadius(12)
                            }
                        }
                        .padding(24)
                        .background(Color.black.opacity(0.75))
                        .cornerRadius(16)
                    } else {
                        // Idle State
                        VStack(spacing: 12) {
                            Image(systemName: "viewfinder.circle")
                                .font(.system(size: 64))
                                .foregroundColor(.white)
                            
                            Text("Visual Scanner")
                                .font(.system(size: 19, weight: .bold))
                                .foregroundColor(.white)
                            
                            Text("Point at ANY product\nNo barcode or ingredients needed!")
                                .font(.system(size: 15))
                                .foregroundColor(.white.opacity(0.9))
                                .multilineTextAlignment(.center)
                        }
                        .padding(24)
                        .background(Color.black.opacity(0.75))
                        .cornerRadius(16)
                    }
                }
                
                Spacer()
                
                // Manual Capture Button
                if !isAnalyzing {
                    Button(action: captureAndAnalyze) {
                        ZStack {
                            Circle()
                                .fill(Color.white)
                                .frame(width: 70, height: 70)
                            
                            Circle()
                                .stroke(Color.white, lineWidth: 4)
                                .frame(width: 84, height: 84)
                        }
                    }
                    .padding(.bottom, 40)
                }
            }
            
            // Visual Feedback: Detected Text Boxes
            if !isAnalyzing && !detectedText.isEmpty {
                ForEach(scanner.textBoundingBoxes, id: \.self) { box in
                    Rectangle()
                        .stroke(Color(hex: "10B981"), lineWidth: 2)
                        .frame(width: box.width, height: box.height)
                        .position(x: box.midX, y: box.midY)
                }
            }
            
            if isShowingLoadingOverlay {
                AnalysisLoadingOverlay(
                    progress: loadingProgress,
                    step: loadingStep,
                    mode: loadingMode
                )
                .transition(.opacity)
                .zIndex(100)
            }
        }
        .onAppear {
            scanner.startScanning()
        }
        .onDisappear {
            scanner.stopScanning()
        }
        .onChange(of: scanner.detectedText) { _, text in
            detectedText = text
        }
        .fullScreenCover(isPresented: $showResults) {
            if let result = analysisResult {
                ResultsView(result: result, onDismiss: {
                    showResults = false
                    analysisResult = nil
                    capturedImage = nil
                })
            }
        }
        .alert("Scan Failed", isPresented: $showError) {
            Button("Try Again") {
                captureAndAnalyze()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .alert("Camera Access Required", isPresented: $scanner.cameraPermissionDenied) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) { dismiss() }
        } message: {
            Text("Ethica needs camera access to scan products. Please enable it in Settings.")
        }
    }
    
    private func simulateAnalysisProgress() {
        // Reset state
        loadingProgress = 0.0
        loadingStep = 0

        // Step 0: Identifying product from image (0.0 - 0.3) — 3s
        withAnimation(.linear(duration: 3.0)) {
            loadingProgress = 0.3
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            // Step 1: Searching database (0.3 - 0.5) — 2s
            loadingStep = 1
            withAnimation(.linear(duration: 2.0)) {
                loadingProgress = 0.5
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                // Step 2: Checking safety (0.5 - 0.75) — 3s
                loadingStep = 2
                withAnimation(.linear(duration: 3.0)) {
                    loadingProgress = 0.75
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                    // Step 3: Preparing results (0.75 - 0.85) — 2s
                    loadingStep = 3
                    withAnimation(.linear(duration: 2.0)) {
                        loadingProgress = 0.85
                    }
                }
            }
        }
    }
    
    private func captureAndAnalyze() {
        guard !isAnalyzing else { return }
        
        HapticManager.shared.trigger(.impactMedium)
        
        // Capture current frame
        scanner.captureFrame { image in
            guard let image = image else { return }
            
            DispatchQueue.main.async {
                self.capturedImage = image
                self.analyzeProduct(image)
            }
        }
    }
    
    private func analyzeProduct(_ image: UIImage) {
        isAnalyzing = true
        isShowingLoadingOverlay = true
        loadingMode = .visual
        simulateAnalysisProgress()

        // 30-second timeout to prevent infinite loading
        let timeoutTask = DispatchWorkItem {
            if isAnalyzing {
                isShowingLoadingOverlay = false
                isAnalyzing = false
                capturedImage = nil
                errorMessage = "Analysis timed out. Please try again with a clearer photo."
                showError = true
                HapticManager.shared.trigger(.error)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 30, execute: timeoutTask)

        Task {
            do {
                let prefs = preferencesManager.preferences

                // Step 1: Identify product from image (3-5s)
                guard let identification = await networkService.identifyVisualProduct(
                    image,
                    preferences: prefs
                ) else {
                    timeoutTask.cancel()
                    throw NSError(domain: "Visual identification failed", code: 500)
                }

                // Free captured image memory
                await MainActor.run { capturedImage = nil }

                // Step 2: Look up via barcode pipeline (OFF search → quick check → enrichment)
                guard let result = await ProductDatabaseService.shared.lookupVisualProduct(
                    name: identification.productName,
                    estimatedIngredients: identification.estimatedIngredients,
                    preferences: prefs,
                    ingredientConfidence: identification.ingredientConfidence
                ) else {
                    timeoutTask.cancel()
                    throw NSError(domain: "Product analysis failed", code: 500)
                }
                timeoutTask.cancel()

                // Step 3: Save to history
                let scan = ScanHistory(
                    productName: result.productName,
                    barcode: result.sourceBarcode,
                    sourceType: "visual",
                    isSafe: result.isSafe,
                    violationsCount: result.violations.count,
                    violations: result.violations,
                    co2Emissions: result.co2Emissions,
                    waterUsage: result.waterUsage,
                    animalImpact: result.animalImpact,
                    healthScore: result.healthScore,
                    concernsCount: result.healthConcerns.count,
                    purchaseDecision: .scanned,
                    needsReview: true
                )
                HistoryService.shared.saveScan(scan)

                // Complete — jump progress to 100% then show results
                await MainActor.run {
                    networkService.isAnalyzing = false

                    withAnimation(.easeInOut(duration: 0.3)) {
                        loadingProgress = 1.0
                        loadingStep = 4
                    }

                    HapticManager.shared.trigger(.success)

                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        isShowingLoadingOverlay = false
                        analysisResult = result
                        isAnalyzing = false
                        showResults = true
                    }
                }

            } catch {
                timeoutTask.cancel()
                await MainActor.run {
                    capturedImage = nil
                    isShowingLoadingOverlay = false
                    isAnalyzing = false
                    networkService.isAnalyzing = false

                    errorMessage = networkService.errorMessage ?? "Could not identify product. Try a clearer photo with better lighting."
                    showError = true

                    HapticManager.shared.trigger(.error)
                }
            }
        }
    }
}

// MARK: - Visual Scanner Manager
class VisualScannerManager: NSObject, ObservableObject {
    @Published var detectedText: [String] = []
    @Published var textBoundingBoxes: [CGRect] = []
    @Published var torchOn = false
    @Published var torchAvailable = false
    @Published var cameraPermissionDenied = false

    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "visual.session.queue")
    private var captureDevice: AVCaptureDevice?
    private var videoOutput: AVCaptureVideoDataOutput?

    private let textRecognitionQueue = DispatchQueue(label: "text.recognition.queue")
    private var lastRecognitionTime = Date()
    private let recognitionThrottle: TimeInterval = 0.5
    private let ciContext = CIContext() // Reuse — creating per-frame wastes GPU

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
            DispatchQueue.main.async { self.cameraPermissionDenied = true }
            completion(false)
        @unknown default:
            completion(false)
        }
    }
    
    func stopScanning() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            self.captureNextFrame = nil
            self.session.stopRunning()
            // Remove all inputs and outputs to fully release camera
            for input in self.session.inputs {
                self.session.removeInput(input)
            }
            for output in self.session.outputs {
                self.session.removeOutput(output)
            }
            self.videoOutput = nil
        }
    }

    deinit {
        captureNextFrame = nil
        session.stopRunning()
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
    
    func captureFrame(completion: @escaping (UIImage?) -> Void) {
        guard let output = videoOutput else {
            completion(nil)
            return
        }
        
        // Get current frame from video output
        // This is handled by the delegate
        self.captureNextFrame = completion
    }
    
    private var captureNextFrame: ((UIImage?) -> Void)?
    
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
        
        // Configure for high quality
        do {
            try device.lockForConfiguration()
            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }
            device.unlockForConfiguration()
        } catch {
            AppLogger.warning("⚠️ Focus configuration failed: \(error)")
        }
        
        do {
            let input = try AVCaptureDeviceInput(device: device)
            
            if session.canAddInput(input) {
                session.addInput(input)
            }
            
            // Setup video output for text recognition
            let output = AVCaptureVideoDataOutput()
            output.setSampleBufferDelegate(self, queue: textRecognitionQueue)
            
            if session.canAddOutput(output) {
                session.addOutput(output)
                videoOutput = output
            }
            
            // Set high quality preset
            if session.canSetSessionPreset(.high) {
                session.sessionPreset = .high
            }
            
            DispatchQueue.global(qos: .userInitiated).async {
                self.session.startRunning()
            }
            
        } catch {
            AppLogger.error("❌ Camera setup error: \(error)")
        }
    }
    
    private func recognizeText(in image: CVPixelBuffer) {
        let request = VNRecognizeTextRequest { [weak self] request, error in
            guard let observations = request.results as? [VNRecognizedTextObservation] else { return }
            
            var recognizedText: [String] = []
            var boxes: [CGRect] = []
            
            for observation in observations {
                guard let candidate = observation.topCandidates(1).first,
                      candidate.confidence > 0.5 else { continue }
                
                recognizedText.append(candidate.string)
                boxes.append(observation.boundingBox)
            }
            
            DispatchQueue.main.async {
                self?.detectedText = recognizedText
                self?.textBoundingBoxes = boxes
            }
        }
        
        // Configure for accurate text recognition
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        
        let handler = VNImageRequestHandler(cvPixelBuffer: image, options: [:])
        
        do {
            try handler.perform([request])
        } catch {
            AppLogger.error("❌ Text recognition error: \(error)")
        }
    }
}

// MARK: - Video Output Delegate
extension VisualScannerManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        
        // Handle frame capture request
        if let captureHandler = captureNextFrame {
            if let image = imageFromSampleBuffer(sampleBuffer) {
                DispatchQueue.main.async {
                    captureHandler(image)
                }
            }
            captureNextFrame = nil
            return
        }
        
        // Throttle text recognition
        guard Date().timeIntervalSince(lastRecognitionTime) > recognitionThrottle else { return }
        lastRecognitionTime = Date()
        
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        recognizeText(in: pixelBuffer)
    }
    
    private func imageFromSampleBuffer(_ sampleBuffer: CMSampleBuffer) -> UIImage? {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return nil }

        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        
        return UIImage(cgImage: cgImage)
    }
}
