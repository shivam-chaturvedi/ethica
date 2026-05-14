//
//  AROverlayView.swift
//  Ethica
//
//  AR camera view with real-time product overlay and detection
//

import SwiftUI
import AVFoundation
import Vision
import AVFAudio

struct AROverlayView: View {
    @StateObject private var cameraManager = ARCameraManager()
    @ObservedObject private var recognitionService = ProductRecognitionService.shared
    @StateObject private var voiceGuidance = VoiceGuidanceService()
    @State private var selectedProduct: DetectedProduct?
    @State private var showingProductDetail = false
    @State private var showingGuide = false
    @State private var voiceEnabled = true
    @State private var lastAnnouncedCount = 0
    @State private var demoMode = false  // OFF by default - use real scanning
    @State private var isScanning = false
    @State private var scanHint = "Tap center to scan product"
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        ZStack {
            // Camera preview
            CameraPreviewView(cameraManager: cameraManager)
                .edgesIgnoringSafeArea(.all)
                .onTapGesture {
                    handleTapToScan(at: .zero)
                }
            
            // Center crosshair for targeting
            if recognitionService.detectedProducts.isEmpty && !isScanning {
                centerCrosshair
            }
            
            // Demo overlay if enabled
            if recognitionService.detectedProducts.isEmpty && demoMode {
                demoProductOverlays
            }
            
            // AR Overlays
            GeometryReader { geometry in
                ForEach(recognitionService.detectedProducts) { product in
                    ProductOverlayBox(
                        product: product,
                        viewSize: geometry.size,
                        isSelected: selectedProduct?.id == product.id
                    )
                    .onTapGesture {
                        withAnimation(.spring(response: 0.3)) {
                            selectedProduct = product
                            showingProductDetail = true
                        }
                        HapticManager.shared.trigger(.impactMedium)
                    }
                }
                
                // Shelf statistics overlay
                if !recognitionService.detectedProducts.isEmpty {
                    ShelfStatisticsOverlay(products: recognitionService.detectedProducts)
                        .frame(maxWidth: .infinity)
                        .position(x: geometry.size.width / 2, y: 80)
                }
            }
            
            // Product detail card (when tapped)
            if showingProductDetail, let product = selectedProduct {
                VStack {
                    Spacer()
                    ProductQuickCard(product: product) {
                        showingProductDetail = false
                        selectedProduct = nil
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.horizontal)
                    .padding(.bottom, 40)
                }
            }
            
            // Top controls
            VStack {
                HStack {
                    // Close button
                    Button(action: {
                        cameraManager.stopSession()
                        dismiss()
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 44, height: 44)
                            .background(Color.black.opacity(0.5))
                            .clipShape(Circle())
                    }
                    
                    Spacer()
                    
                    // Processing indicator
                    if recognitionService.isProcessing {
                        HStack(spacing: 8) {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.8)
                            Text("Scanning...")
                                .font(.caption)
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                    }

                    Spacer()

                    #if DEBUG
                    // Demo mode toggle
                    Button(action: {
                        demoMode.toggle()
                        HapticManager.shared.trigger(.impactLight)
                    }) {
                        Image(systemName: demoMode ? "eye.fill" : "eye.slash.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 44, height: 44)
                            .background(Color.black.opacity(0.5))
                            .clipShape(Circle())
                    }
                    #endif

                    // Voice toggle button
                    Button(action: {
                        voiceEnabled.toggle()
                        HapticManager.shared.trigger(.impactLight)
                    }) {
                        Image(systemName: voiceEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 44, height: 44)
                            .background(Color.black.opacity(0.5))
                            .clipShape(Circle())
                    }
                    
                    // Settings/info button
                    Button(action: {
                        showingGuide = true
                    }) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 44, height: 44)
                            .background(Color.black.opacity(0.5))
                            .clipShape(Circle())
                    }
                }
                .padding(.horizontal)
                .padding(.top, 50)
                
                Spacer()
            }
            
            // Bottom guidance text
            VStack {
                Spacer()
                
                VStack(spacing: 8) {
                    #if DEBUG
                    if demoMode {
                        Text("DEMO MODE ACTIVE")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.yellow)
                    }

                    HStack(spacing: 12) {
                        Text("Detected: \(recognitionService.detectedProducts.count)")
                        Text(recognitionService.isProcessing ? "Processing..." : "Ready")
                            .foregroundColor(recognitionService.isProcessing ? Theme.warning : Theme.success)
                    }
                    .font(.caption)
                    .foregroundColor(.white)
                    #endif

                    if recognitionService.detectedProducts.isEmpty && !demoMode {
                        Text(scanHint)
                            .font(.subheadline)
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                        
                        if !isScanning {
                            Button(action: { scanCenterProduct() }) {
                                HStack(spacing: 8) {
                                    Image(systemName: "viewfinder")
                                    Text("Scan Now")
                                        .fontWeight(.semibold)
                                }
                                .padding(.horizontal, 20)
                                .padding(.vertical, 10)
                                .background(Theme.info)
                                .foregroundColor(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 20))
                            }
                            .padding(.top, 4)
                        } else {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .tint(.white)
                                Text("Scanning...")
                            }
                            .foregroundColor(.white)
                            .padding(.top, 4)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Color.black.opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.bottom, 40)
            }
        }
        .statusBar(hidden: true)
        .sheet(isPresented: $showingGuide) {
            ARGuideView()
                .premiumSheet()
        }
        .onAppear {
            cameraManager.startSession()
            if voiceEnabled {
                voiceGuidance.speak("AR scanner ready. Point camera at products.")
            }
        }
        .onDisappear {
            cameraManager.stopSession()
            voiceGuidance.stopSpeaking()
        }
        .onChange(of: recognitionService.detectedProducts) { _, products in
            handleProductDetectionChange(products)
        }
    }
    
    private func handleTapToScan(at location: CGPoint) {
        guard !isScanning else { return }
        scanCenterProduct()
    }
    
    private func scanCenterProduct() {
        guard !isScanning else { return }
        isScanning = true
        scanHint = "Analyzing product..."
        recognitionService.forceScan()
        
        HapticManager.shared.trigger(.impactMedium)

        // Reset after timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            if recognitionService.detectedProducts.isEmpty {
                isScanning = false
                scanHint = "No product detected. Try again."
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    scanHint = "Tap center to scan product"
                }
            } else {
                isScanning = false
                scanHint = "Tap center to scan product"
            }
        }
    }
    
    private var centerCrosshair: some View {
        VStack(spacing: 0) {
            Spacer()
            HStack(spacing: 0) {
                Spacer()
                ZStack {
                    // Outer circle
                    Circle()
                        .stroke(Color.white.opacity(0.5), lineWidth: 2)
                        .frame(width: 100, height: 100)
                    
                    // Crosshair lines
                    VStack(spacing: 0) {
                        Rectangle()
                            .fill(Color.white.opacity(0.7))
                            .frame(width: 2, height: 30)
                        Spacer()
                            .frame(height: 40)
                        Rectangle()
                            .fill(Color.white.opacity(0.7))
                            .frame(width: 2, height: 30)
                    }
                    .frame(height: 100)
                    
                    HStack(spacing: 0) {
                        Rectangle()
                            .fill(Color.white.opacity(0.7))
                            .frame(width: 30, height: 2)
                        Spacer()
                            .frame(width: 40)
                        Rectangle()
                            .fill(Color.white.opacity(0.7))
                            .frame(width: 30, height: 2)
                    }
                    .frame(width: 100)
                    
                    // Center dot
                    Circle()
                        .fill(Theme.info)
                        .frame(width: 8, height: 8)
                }
                Spacer()
            }
            Spacer()
        }
    }
    
    private func handleProductDetectionChange(_ products: [DetectedProduct]) {
        let safeCount = products.filter { $0.safetyStatus == .safe }.count
        let dangerCount = products.filter { $0.safetyStatus == .danger }.count
        let totalCount = products.count
        
        // Stop scanning animation when product detected
        if totalCount > 0 {
            isScanning = false
        }
        
        // Haptic feedback based on product detection
        if totalCount != lastAnnouncedCount {
            HapticManager.shared.trigger(.impactLight)

            // Voice announcement (throttled)
            if voiceEnabled && totalCount > 0 && abs(totalCount - lastAnnouncedCount) >= 3 {
                if dangerCount > 0 {
                    HapticManager.shared.trigger(.warning)
                    voiceGuidance.speak("\(dangerCount) unsafe product\(dangerCount == 1 ? "" : "s") detected")
                } else if safeCount == totalCount {
                    voiceGuidance.speak("\(safeCount) safe product\(safeCount == 1 ? "" : "s")")
                }
                lastAnnouncedCount = totalCount
            }
        }
    }
}

// MARK: - Product Overlay Box
struct ProductOverlayBox: View {
    let product: DetectedProduct
    let viewSize: CGSize
    let isSelected: Bool
    
    @State private var pulseAnimation = false
    
    var body: some View {
        let frame = convertBoundingBox(product.boundingBox, viewSize: viewSize)
        
        ZStack {
            // Glow effect
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(hex: product.safetyStatus.glowColor).opacity(pulseAnimation ? 0.3 : 0.2))
                .blur(radius: 8)
            
            // Border
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    Color(hex: product.safetyStatus.color),
                    lineWidth: isSelected ? 3 : 2
                )
            
            // Status indicator badge
            VStack {
                HStack {
                    Spacer()
                    statusBadge
                        .padding(4)
                }
                Spacer()
                
                // Show product name for unknown products
                if product.safetyStatus == .unknown {
                    VStack(spacing: 2) {
                        Text(product.name)
                            .font(.caption2)
                            .fontWeight(.bold)
                        if let brand = product.brand {
                            Text(brand)
                                .font(.system(size: 8))
                                .foregroundColor(.white.opacity(0.8))
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.black.opacity(0.7))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .padding(.bottom, 4)
                }
            }
        }
        .frame(width: frame.width, height: frame.height)
        .position(x: frame.midX, y: frame.midY)
        .onAppear {
            withAnimation(Animation.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                pulseAnimation = true
            }
        }
    }
    
    private var statusBadge: some View {
        Group {
            switch product.safetyStatus {
            case .safe:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(Color(hex: "10B981"))
            case .caution:
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(Color(hex: "F59E0B"))
            case .danger:
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(Color(hex: "EF4444"))
            case .unknown:
                Image(systemName: "questionmark.circle.fill")
                    .foregroundColor(Color(hex: "9CA3AF"))
            }
        }
        .font(.system(size: 16))
        .padding(6)
        .background(Theme.surfaceBase)
        .clipShape(Circle())
        .shadow(color: Color.black.opacity(0.2), radius: 4)
    }
    
    private func convertBoundingBox(_ box: CGRect, viewSize: CGSize) -> CGRect {
        // Vision coordinates are normalized and origin is bottom-left
        // UIKit coordinates origin is top-left
        let x = box.minX * viewSize.width
        let y = (1 - box.maxY) * viewSize.height
        let width = box.width * viewSize.width
        let height = box.height * viewSize.height
        
        return CGRect(x: x, y: y, width: width, height: height)
    }
}

// MARK: - Shelf Statistics Overlay
struct ShelfStatisticsOverlay: View {
    let products: [DetectedProduct]
    
    private var safeCount: Int {
        products.filter { $0.safetyStatus == .safe }.count
    }
    
    private var totalCount: Int {
        products.count
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Safe count
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(Color(hex: "10B981"))
                Text("\(safeCount)")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
            }
            
            Text("/")
                .foregroundColor(.white.opacity(0.6))
            
            // Total count
            Text("\(totalCount)")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)
            
            Text("products")
                .font(.caption)
                .foregroundColor(.white.opacity(0.8))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.7))
                .overlay(
                    Capsule()
                        .strokeBorder(Color(hex: "10B981").opacity(0.3), lineWidth: 1)
                )
        )
    }
}

// MARK: - Product Quick Card
struct ProductQuickCard: View {
    let product: DetectedProduct
    let onDismiss: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    if let brand = product.brand {
                        Text(brand)
                            .font(.caption)
                            .foregroundColor(Theme.textTertiary)
                    }
                    Text(product.name)
                        .font(.headline)
                        .foregroundColor(Theme.textPrimary)
                }
                
                Spacer()
                
                // Status icon
                statusIcon
            }
            
            // Quick stats
            if product.safetyStatus != .unknown {
                HStack(spacing: 16) {
                    if let co2 = product.co2 {
                        StatPill(icon: "leaf.fill", value: String(format: "%.2fkg", co2), label: "CO₂")
                    }
                    
                    if let water = product.waterUsage {
                        StatPill(icon: "drop.fill", value: "\(Int(water))L", label: "Water")
                    }
                    
                    if let health = product.healthScore {
                        StatPill(icon: "heart.fill", value: String(format: "%.1f", health), label: "Health")
                    }
                }
            }
            
            // Allergen warnings
            if !product.allergenWarnings.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundColor(Color(hex: "EF4444"))
                        Text("Contains:")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(Color(hex: "EF4444"))
                    }
                    Text(product.allergenWarnings.joined(separator: ", "))
                        .font(.caption)
                        .foregroundColor(Theme.textTertiary)
                }
                .padding(8)
                .background(Theme.error.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            
            // Action button
            Button(action: onDismiss) {
                Text("Dismiss")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(Theme.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Theme.surfaceSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(20)
        .background(Theme.surfaceBase)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: Color.black.opacity(0.15), radius: 20, y: -5)
    }
    
    private var statusIcon: some View {
        Group {
            switch product.safetyStatus {
            case .safe:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 32))
                    .foregroundColor(Color(hex: "10B981"))
            case .caution:
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 32))
                    .foregroundColor(Color(hex: "F59E0B"))
            case .danger:
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 32))
                    .foregroundColor(Color(hex: "EF4444"))
            case .unknown:
                Image(systemName: "questionmark.circle.fill")
                    .font(.system(size: 32))
                    .foregroundColor(Color(hex: "9CA3AF"))
            }
        }
    }
}

struct StatPill: View {
    let icon: String
    let value: String
    let label: String
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .font(.caption.weight(.bold))
                Text(label)
                    .font(.system(size: 9))
                    .foregroundColor(Theme.textTertiary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Theme.surfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Camera Preview
struct CameraPreviewView: UIViewRepresentable {
    let cameraManager: ARCameraManager
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .black
        
        let previewLayer = AVCaptureVideoPreviewLayer(session: cameraManager.captureSession)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = view.bounds
        view.layer.addSublayer(previewLayer)
        
        context.coordinator.previewLayer = previewLayer
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        if let previewLayer = context.coordinator.previewLayer {
            DispatchQueue.main.async {
                previewLayer.frame = uiView.bounds
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator {
        var previewLayer: AVCaptureVideoPreviewLayer?
    }
}

// MARK: - Demo Product Overlays
extension AROverlayView {
    var demoProductOverlays: some View {
        GeometryReader { geometry in
            ZStack {
                // Demo product 1: Safe (green) - Oat Milk
                DemoProductBox(
                    name: "Oatly Oat Milk",
                    status: .safe,
                    position: CGPoint(x: geometry.size.width * 0.25, y: geometry.size.height * 0.3),
                    size: CGSize(width: 120, height: 160)
                )
                
                // Demo product 2: Danger (red) - Dairy
                DemoProductBox(
                    name: "Dairy Milk",
                    status: .danger,
                    position: CGPoint(x: geometry.size.width * 0.5, y: geometry.size.height * 0.35),
                    size: CGSize(width: 100, height: 180)
                )
                
                // Demo product 3: Caution (yellow) - May contain
                DemoProductBox(
                    name: "Mixed Nuts",
                    status: .caution,
                    position: CGPoint(x: geometry.size.width * 0.75, y: geometry.size.height * 0.4),
                    size: CGSize(width: 110, height: 150)
                )
                
                // Demo instruction overlay
                VStack {
                    Spacer()
                    Text("DEMO MODE: Tap eye icon to toggle")
                        .font(.caption)
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.7))
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .padding(.bottom, 120)
                }
            }
        }
    }
}

struct DemoProductBox: View {
    let name: String
    let status: DetectedProduct.SafetyStatus
    let position: CGPoint
    let size: CGSize
    
    @State private var pulseAnimation = false
    
    var body: some View {
        ZStack {
            // Glow effect
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(hex: status.glowColor).opacity(pulseAnimation ? 0.3 : 0.2))
                .blur(radius: 8)
            
            // Border
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color(hex: status.color), lineWidth: 2)
            
            // Label
            VStack {
                HStack {
                    Spacer()
                    statusIcon
                        .padding(4)
                }
                Spacer()
                Text(name)
                    .font(.caption.bold())
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.7))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .padding(.bottom, 4)
            }
        }
        .frame(width: size.width, height: size.height)
        .position(position)
        .onAppear {
            withAnimation(Animation.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                pulseAnimation = true
            }
        }
    }
    
    private var statusIcon: some View {
        Group {
            switch status {
            case .safe:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(Color(hex: "10B981"))
            case .caution:
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(Color(hex: "F59E0B"))
            case .danger:
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(Color(hex: "EF4444"))
            case .unknown:
                Image(systemName: "questionmark.circle.fill")
                    .foregroundColor(Color(hex: "9CA3AF"))
            }
        }
        .font(.system(size: 16))
        .padding(6)
        .background(Theme.surfaceBase)
        .clipShape(Circle())
        .shadow(color: Color.black.opacity(0.2), radius: 4)
    }
}

#Preview {
    AROverlayView()
}
