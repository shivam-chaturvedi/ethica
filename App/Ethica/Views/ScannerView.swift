//
//  ScannerView.swift
//  Ethica
//
//  Updated to match web design exactly

import SwiftUI
import PhotosUI

struct ScannerView: View {
    @ObservedObject var preferencesManager: PreferencesManager
    @ObservedObject private var networkService = NetworkService.shared
    @State private var analysisResult: AnalysisResult?
    @State private var selectedImage: UIImage?
    @State private var showImagePicker = false
    @State private var showCamera = false
    @State private var useBarcodeMode = false
    @State private var useRestaurantMode = false
    @State private var usePlateCheckMode = false
    @State private var showSuccessCheckmark = false
    @State private var showLiveScanner = false
    @State private var showVisualScanner = false
    @State private var showPlateCheckSheet = false
    @State private var plateCheckImage: UIImage?
    @State private var preResizedImageData: Data?
    @State private var plateAnalysisResult: [String: Any]?
    @State private var showPlateResults = false
    @State private var showPlateError = false
    @State private var plateErrorMessage = ""
    // Unified loading overlay states
    @State private var isShowingLoadingOverlay = false
    @State private var loadingProgress: CGFloat = 0.0
    @State private var loadingStep = 0
    @State private var loadingMode: LoadingMode = .product
    @State private var appearAnimation = false
    @State private var showAnalysisError = false
    @State private var logoBreathing = false
    var showScanner: Binding<Bool>? = nil // Optional for TabView navigation
    // Haptics via HapticManager.shared
    
    enum LoadingMode {
        case product
        case barcode
        case restaurant
        case plate
        case visual

        var title: String {
            switch self {
            case .product: return "Analyzing Product"
            case .barcode: return "Scanning Barcode"
            case .restaurant: return "Analyzing Menu"
            case .plate: return "Analyzing Your Plate"
            case .visual: return "Identifying Product"
            }
        }

        var iconColor: Color {
            switch self {
            case .product: return Theme.primary
            case .barcode: return Theme.info
            case .restaurant: return Theme.warning
            case .plate: return Theme.accent
            case .visual: return Theme.primary
            }
        }

        var steps: [(icon: String, text: String)] {
            switch self {
            case .product:
                return [
                    ("doc.text.viewfinder", "Processing image..."),
                    ("text.magnifyingglass", "Extracting ingredients..."),
                    ("checkmark.shield", "Checking dietary safety..."),
                    ("leaf.fill", "Calculating impact..."),
                    ("checkmark.circle.fill", "Complete!")
                ]
            case .barcode:
                return [
                    ("barcode.viewfinder", "Scanning barcode..."),
                    ("magnifyingglass", "Searching database..."),
                    ("checkmark.shield", "Checking dietary safety..."),
                    ("leaf.fill", "Calculating impact..."),
                    ("checkmark.circle.fill", "Complete!")
                ]
            case .restaurant:
                return [
                    ("doc.text.viewfinder", "Reading menu..."),
                    ("fork.knife", "Identifying dishes..."),
                    ("checkmark.shield", "Analyzing ingredients..."),
                    ("sparkles", "Generating recommendations..."),
                    ("checkmark.circle.fill", "Complete!")
                ]
            case .plate:
                return [
                    ("photo.fill", "Processing image..."),
                    ("fork.knife", "Identifying ingredients..."),
                    ("checklist", "Checking dietary compliance..."),
                    ("sparkles", "Finalizing analysis..."),
                    ("checkmark.circle.fill", "Complete!")
                ]
            case .visual:
                return [
                    ("viewfinder.circle", "Identifying product..."),
                    ("magnifyingglass", "Searching database..."),
                    ("checkmark.shield", "Checking safety..."),
                    ("sparkles", "Preparing results..."),
                    ("checkmark.circle.fill", "Complete!")
                ]
            }
        }
    }
    
    private func getProgressText() -> String {
        let progress = networkService.analysisProgress
        if useBarcodeMode {
            if progress < 0.2 {
                return "Scanning for barcode..."
            } else if progress < 0.3 {
                return "Checking product database..."
            }
        }
        if useRestaurantMode {
            if progress < 0.4 {
                return "Reading menu with AI..."
            } else if progress < 0.6 {
                return "Identifying dishes..."
            } else if progress < 0.8 {
                return "Analyzing ingredients..."
            } else {
                return "Checking dietary compliance..."
            }
        }
        if progress < 0.5 {
            return "Processing image with OCR..."
        } else if progress < 0.7 {
            return "Extracting ingredients..."
        } else if progress < 0.8 {
            return "Analyzing with AI..."
        } else if progress < 0.95 {
            return "Calculating impact scores..."
        } else {
            return "Finalizing results..."
        }
    }
    
    private var backgroundGradient: some View {
        Theme.backgroundPrimary
            .ignoresSafeArea()
    }
    
    var body: some View {
        ZStack {
            backgroundGradient
            
            ScrollView {
                VStack(spacing: 24) {
                    // Clean Header Section
                    VStack(spacing: 16) {
                        // Simple App Logo
                        ZStack {
                            Circle()
                                .fill(Theme.surfaceBase)
                                .frame(width: 80, height: 80)

                            Circle()
                                .stroke(Theme.surfaceSecondary, lineWidth: 1)
                                .frame(width: 80, height: 80)

                            Text("🌿")
                                .font(.system(size: 40))
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Ethica app logo")
                        
                        VStack(spacing: 6) {
                            Text("Ethica")
                                .font(Typography.h1)
                                .foregroundColor(Theme.textPrimary)

                            Text("Scan · Analyze · Eat Safe")
                                .font(Typography.bodySmall)
                                .foregroundColor(Theme.primary)
                                .tracking(0.5)

                            Text("Check dietary compatibility & environmental impact")
                                .font(Typography.bodySmall)
                                .foregroundColor(Theme.textTertiary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 24)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Ethica. Scan, Analyze, Eat Safe. Check dietary compatibility and environmental impact.")
                    }
                    .padding(.top, 24)
                    .padding(.bottom, 8)
                    
                    // Scan Options Card
                    VStack(spacing: 16) {
                        Text("Scan Options")
                            .font(Typography.bodySmall)
                            .foregroundColor(Theme.textSecondary)
                            .textCase(.uppercase)
                            .tracking(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        VStack(spacing: 12) {
                            // 1. Live Barcode Scanner - fastest option
                            ModernScanButton(
                                icon: "barcode.viewfinder",
                                iconColor: Theme.primary,
                                title: "Live Barcode Scanner",
                                subtitle: "Instant real-time scanning ⚡",
                                gradient: [Theme.primary, Theme.primaryDark],
                                action: {
                                    HapticManager.shared.trigger(.impactMedium)
                                    showLiveScanner = true
                                }
                            )
                            .overlay(ShimmerOverlay())
                            .accessibilityLabel("Live Barcode Scanner")
                            .accessibilityHint("Opens real-time barcode scanner using the camera")
                            .bounceOnAppear(delay: 0.1)
                            
                            // 2. AI Visual Scanner - temporarily hidden
                            // ModernScanButton(
                            //     icon: "sparkles.rectangle.stack",
                            //     iconColor: Theme.accent,
                            //     title: "AI Visual Scanner",
                            //     subtitle: "AI identifies product • No label needed",
                            //     gradient: [Theme.accent, Color(hex: "7C3AED")],
                            //     action: {
                            //         HapticManager.shared.trigger(.impactMedium)
                            //         showVisualScanner = true
                            //     }
                            // )
                            // .accessibilityLabel("AI Visual Scanner")
                            // .accessibilityHint("Point at any product and AI identifies it — no barcode or ingredients label needed")
                            // .bounceOnAppear(delay: 0.2)
                            
                            // 3. Restaurant Menu Scanner - temporarily disabled
                            // ModernScanButton(
                            //     icon: "doc.text.magnifyingglass",
                            //     iconColor: Theme.warning,
                            //     title: "Restaurant Menu Scanner",
                            //     subtitle: "Check which dishes are safe to order",
                            //     gradient: [Theme.warning, Color(hex: "D97706")],
                            //     action: {
                            //         HapticManager.shared.trigger(.impactMedium)
                            //         useBarcodeMode = false
                            //         useRestaurantMode = true
                            //         usePlateCheckMode = false
                            //         #if targetEnvironment(simulator)
                            //         showImagePicker = true
                            //         #else
                            //         showCamera = true
                            //         #endif
                            //     }
                            // )
                            // .accessibilityLabel("Restaurant Menu Scanner")
                            // .accessibilityHint("Takes a photo of a menu to check which dishes are safe to order")
                            // .bounceOnAppear(delay: 0.3)
                            
                            // 4. Plate Check - analyze food on plate
                            ModernScanButton(
                                icon: "fork.knife.circle.fill",
                                iconColor: Theme.accent,
                                title: "Plate Check",
                                subtitle: "Analyze food on your plate",
                                gradient: [Theme.accent, Color(hex: "7C3AED")],
                                action: {
                                    HapticManager.shared.trigger(.impactMedium)
                                    useBarcodeMode = false
                                    useRestaurantMode = false
                                    usePlateCheckMode = true
                                    #if targetEnvironment(simulator)
                                    showImagePicker = true
                                    #else
                                    showCamera = true
                                    #endif
                                }
                            )
                            .accessibilityLabel("Plate Check")
                            .accessibilityHint("Takes a photo to analyze the food on your plate")
                            .bounceOnAppear(delay: 0.4)
                            
                            // 5. Take Photo - manual ingredients label
                            ModernScanButton(
                                icon: "camera.fill",
                                iconColor: Theme.info,
                                title: "Take Photo",
                                subtitle: "Capture ingredients label",
                                gradient: [Theme.info, Color(hex: "2563EB")],
                                action: {
                                    HapticManager.shared.trigger(.impactMedium)
                                    useBarcodeMode = false
                                    useRestaurantMode = false
                                    usePlateCheckMode = false
                                    #if targetEnvironment(simulator)
                                    showImagePicker = true
                                    #else
                                    showCamera = true
                                    #endif
                                }
                            )
                            .accessibilityLabel("Take Photo")
                            .accessibilityHint("Opens camera to capture an ingredients label")
                            .bounceOnAppear(delay: 0.5)
                        }
                    }
                    .padding(20)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Theme.surfaceBase)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Theme.surfaceSecondary, lineWidth: 1)
                    )
                    .padding(.horizontal, 16)
                    
                    // Premium Selected Image Preview Card
                    if let image = selectedImage, !isShowingLoadingOverlay {
                        VStack(spacing: 24) {
                            HStack {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Selected Image")
                                        .font(Typography.h4)
                                        .foregroundColor(Theme.surfaceBase)

                                    Text("Ready to analyze")
                                        .font(Typography.bodySmall)
                                        .foregroundColor(Theme.textTertiary)
                                }

                                Spacer()

                                // Status indicator
                                ZStack {
                                    Circle()
                                        .fill(
                                            LinearGradient(
                                                colors: [
                                                    Theme.primary.opacity(0.2),
                                                    Theme.primaryLight.opacity(0.1)
                                                ],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                        .frame(width: 40, height: 40)

                                    Image(systemName: "checkmark.circle.fill")
                                        .font(Typography.h3)
                                        .foregroundColor(Theme.primary)
                                }
                                .accessibilityHidden(true)
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("Selected image, ready to analyze")
                            
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: 300)
                                .clipShape(RoundedRectangle(cornerRadius: 20))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 20)
                                        .stroke(
                                            LinearGradient(
                                                colors: [
                                                    Theme.primary.opacity(0.3),
                                                    Theme.primaryLight.opacity(0.2)
                                                ],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ),
                                            lineWidth: 2
                                        )
                                )
                                .shadow(color: Color.black.opacity(0.12), radius: 16, y: 6)
                                .shadow(color: Theme.primary.opacity(0.1), radius: 8, y: 3)
                                .accessibilityLabel("Preview of captured product image")
                            
                            // Analyze Button
                            Button(action: {
                                HapticManager.shared.trigger(.impactMedium)
                                analyzeImage()
                            }) {
                                HStack(spacing: 10) {
                                    if showSuccessCheckmark {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(Typography.h3)
                                            .transition(.scale.combined(with: .opacity))
                                    } else {
                                        Image(systemName: "sparkles")
                                            .font(Typography.h4)
                                    }
                                    Text(showSuccessCheckmark ? "Analysis Complete!" : "Analyze Product")
                                        .font(Typography.buttonLarge)
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(
                                    LinearGradient(
                                        colors: showSuccessCheckmark ? [Theme.primary, Theme.primaryDark] : [Theme.primary, Theme.primaryLight],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                                .shadow(color: Theme.primary.opacity(0.4), radius: 12, y: 4)
                                .opacity(networkService.isAnalyzing ? 0.6 : 1.0)
                                .scaleEffect(showSuccessCheckmark ? 1.02 : 1.0)
                                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: showSuccessCheckmark)
                            }
                            .disabled(networkService.isAnalyzing)
                            .accessibilityLabel(showSuccessCheckmark ? "Analysis complete" : "Analyze product")
                            .accessibilityHint(networkService.isAnalyzing ? "Analysis in progress, please wait" : "Starts AI analysis of the selected image")
                            
                            // Progress Indicator
                            if networkService.isAnalyzing {
                                VStack(spacing: 14) {
                                    // Progress Bar
                                    GeometryReader { geometry in
                                        ZStack(alignment: .leading) {
                                            // Background
                                            RoundedRectangle(cornerRadius: 10)
                                                .fill(Theme.textMuted.opacity(0.3))
                                                .frame(height: 8)

                                            // Progress Fill
                                            RoundedRectangle(cornerRadius: 10)
                                                .fill(
                                                    LinearGradient(
                                                        colors: [
                                                            Theme.primary,
                                                            Theme.primaryLight,
                                                            Color(hex: "6EE7B7")
                                                        ],
                                                        startPoint: .leading,
                                                        endPoint: .trailing
                                                    )
                                                )
                                                .frame(width: geometry.size.width * networkService.analysisProgress, height: 8)
                                                .shadow(color: Theme.primary.opacity(0.5), radius: 6, y: 2)
                                                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: networkService.analysisProgress)
                                        }
                                    }
                                    .frame(height: 8)
                                    .accessibilityHidden(true)

                                    // Progress Info
                                    HStack(spacing: 8) {
                                        HStack(spacing: 6) {
                                            ProgressView()
                                                .scaleEffect(0.8)
                                                .tint(Theme.primary)

                                            Text(getProgressText())
                                                .font(Typography.bodySmall)
                                                .foregroundColor(Theme.textMuted)
                                        }

                                        Spacer()

                                        Text("\(Int(networkService.analysisProgress * 100))%")
                                            .font(Typography.bodySmall)
                                            .foregroundColor(Theme.primary)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 4)
                                            .background(Theme.primary.opacity(0.15))
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                    }
                                }
                                .padding(16)
                                .background(Theme.surfaceSecondary)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .accessibilityElement(children: .combine)
                                .accessibilityLabel("Analysis in progress, \(getProgressText()) \(Int(networkService.analysisProgress * 100)) percent complete")
                            }
                        }
                        .padding(24)
                        .background(
                            Theme.surfaceBase
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .shadow(color: Color.black.opacity(0.08), radius: 16, y: 4)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(Theme.surfaceSecondary, lineWidth: 1)
                        )
                        .padding(.horizontal, 20)
                        .transition(.scale.combined(with: .opacity))
                    }
                    
                    // Error Message Card
                    if let error = networkService.errorMessage {
                        HStack(spacing: 14) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(Typography.h2)
                                .foregroundColor(Theme.error)

                            VStack(alignment: .leading, spacing: 6) {
                                Text("Analysis Error")
                                    .font(Typography.body)
                                    .foregroundColor(Theme.error)
                                Text(error)
                                    .font(Typography.bodySmall)
                                    .foregroundColor(Theme.error.opacity(0.8))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(18)
                        .background(
                            LinearGradient(
                                colors: [Theme.error.opacity(0.15), Theme.error.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Theme.error.opacity(0.3), lineWidth: 1.5)
                        )
                        .shadow(color: Theme.error.opacity(0.2), radius: 12, y: 4)
                        .padding(.horizontal, 20)
                        .transition(.scale.combined(with: .opacity))
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Analysis error. \(error)")
                    }
                    
                    // Footer
                    VStack(spacing: 8) {
                        HStack(spacing: 6) {
                            Text("🌱")
                                .font(Typography.buttonLarge)
                            Text("Guided by Ahimsa")
                                .font(Typography.bodySmall)
                                .foregroundColor(Theme.primary)
                        }
                        Text("Make mindful choices for yourself and the planet")
                            .font(Typography.caption)
                            .foregroundColor(Theme.textTertiary)
                            .multilineTextAlignment(.center)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Guided by Ahimsa. Make mindful choices for yourself and the planet.")
                    .padding(.top, 8)
                    .padding(.bottom, 32)
                }
                .padding(.top, 20)
            }
            
            // Unified Analysis Loading Overlay
            if isShowingLoadingOverlay {
                AnalysisLoadingOverlay(
                    progress: loadingProgress,
                    step: loadingStep,
                    mode: loadingMode
                )
                .transition(.opacity)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(loadingMode.title), \(loadingStep < loadingMode.steps.count ? loadingMode.steps[loadingStep].text : "Processing"), \(Int(loadingProgress * 100)) percent complete")
                .accessibilityAddTraits(.updatesFrequently)
            }
        }
        .sheet(isPresented: $showImagePicker) {
            ImagePicker(image: $selectedImage)
                .premiumSheet()
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker(image: $selectedImage)
        }
        .fullScreenCover(isPresented: $showLiveScanner) {
            LiveBarcodeScannerView(preferencesManager: preferencesManager)
        }
        .fullScreenCover(isPresented: $showVisualScanner) {
            VisualProductScannerView(preferencesManager: preferencesManager)
        }
        .onChange(of: selectedImage) { _, newImage in
            if let image = newImage {
                if usePlateCheckMode {
                    // Store image and show plate check context sheet
                    plateCheckImage = image
                    showPlateCheckSheet = true
                    // Pre-resize in background while user fills context fields
                    preResizedImageData = nil
                    Task.detached(priority: .userInitiated) {
                        let resized = NetworkService.shared.resizeImagePublic(image, maxSize: 800)
                        let data = resized.jpegData(compressionQuality: 0.8)
                        await MainActor.run { preResizedImageData = data }
                    }
                } else {
                    // Regular analysis
                    analyzeImage()
                }
            }
        }
        .sheet(isPresented: $showPlateCheckSheet) {
            PlateCheckContextSheet(
                image: plateCheckImage,
                onAnalyze: { restaurantName, dishName, cuisineType in
                    analyzePlate(restaurantName: restaurantName, dishName: dishName, cuisineType: cuisineType)
                },
                onCancel: {
                    selectedImage = nil
                    plateCheckImage = nil
                    usePlateCheckMode = false
                }
            )
            .premiumSheet()
        }
        .fullScreenCover(isPresented: $showPlateResults) {
            if let result = plateAnalysisResult {
                PlateAnalysisResultView(analysis: result, onDismiss: {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        plateAnalysisResult = nil
                        showPlateResults = false
                        selectedImage = nil
                        plateCheckImage = nil
                    }
                })
                .transition(.asymmetric(
                    insertion: .move(edge: .bottom).combined(with: .opacity),
                    removal: .move(edge: .bottom).combined(with: .opacity)
                ))
            }
        }
        .fullScreenCover(item: $analysisResult) { result in
            Group {
                if result.isRestaurantMenu == true {
                    // Show menu analysis view
                    MenuAnalysisView(result: result)
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .trailing).combined(with: .opacity)
                        ))
                        .onDisappear {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                analysisResult = nil
                                selectedImage = nil
                            }
                        }
                } else {
                    // Show regular results view
                    ResultsView(result: result, onDismiss: {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            analysisResult = nil
                            selectedImage = nil
                        }
                    })
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.95)),
                        removal: .move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.95))
                    ))
                    .onAppear {
                        AppLogger.debug("📣 Presenting ResultsView with productName=\(result.productName), overallScore=\(result.overallScore)")
                    }
                }
            }
        }
        .onAppear {
            withAnimation(.easeIn(duration: 0.6)) {
                appearAnimation = true
            }
        }
        .alert("Plate Analysis Failed", isPresented: $showPlateError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(plateErrorMessage)
        }
        .alert("Analysis Failed", isPresented: $showAnalysisError) {
            Button("Try Again") { selectedImage = nil }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Could not analyze this product. Please try again with a clearer image.")
        }
    }
    
    private func analyzeImage() {
        guard let image = selectedImage else { return }
        
        // Determine loading mode based on scan type
        if useBarcodeMode {
            loadingMode = .barcode
        } else if useRestaurantMode {
            loadingMode = .restaurant
        } else {
            loadingMode = .product
        }
        
        // Show loading overlay
        withAnimation(.easeInOut(duration: 0.3)) {
            isShowingLoadingOverlay = true
            loadingProgress = 0.0
            loadingStep = 0
        }
        
        // Simulate progress steps
        simulateAnalysisProgress()
        
        Task {
            let result = await networkService.analyzeImage(
                image, 
                preferences: preferencesManager.preferences, 
                useBarcodeScanning: useBarcodeMode,
                useRestaurantMode: useRestaurantMode
            )
            await MainActor.run {
                // Complete the progress
                withAnimation(.easeInOut(duration: 0.2)) {
                    loadingProgress = 1.0
                    loadingStep = 4
                }
                
                // Small delay to show completion
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isShowingLoadingOverlay = false
                    }
                    
                    if let result = result {
                        AppLogger.debug("✅ Got result, showing results view")
                        AppLogger.debug("✅ Result data: productName=\\(result.productName), score=\\(result.overallScore)")
                        
                        HapticManager.shared.trigger(.success)

                        // Record taste data for learning
                        Task {
                            await TasteProfileService.shared.recordTasteData(from: result)
                        }

                        // Display result (taste ranking will be applied separately if needed)
                        self.analysisResult = result
                    } else {
                        AppLogger.error("❌ Result was nil - check error message")
                        HapticManager.shared.trigger(.error)
                        showAnalysisError = true
                    }
                }
            }
        }
    }
    
    private func simulateAnalysisProgress() {
        // Step 1: Processing (0-25%)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.easeInOut(duration: 0.5)) {
                loadingProgress = 0.25
                loadingStep = 1
            }
        }
        
        // Step 2: Extracting/Searching (25-50%)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation(.easeInOut(duration: 0.5)) {
                loadingProgress = 0.50
                loadingStep = 2
            }
        }
        
        // Step 3: Checking safety (50-75%)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation(.easeInOut(duration: 0.5)) {
                loadingProgress = 0.75
                loadingStep = 3
            }
        }
        
        // Step 4: Almost done (75-90%)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation(.easeInOut(duration: 0.5)) {
                loadingProgress = 0.90
            }
        }
    }
    
    private func analyzePlate(restaurantName: String, dishName: String, cuisineType: String) {
        guard let image = plateCheckImage else { return }

        // Set loading mode
        loadingMode = .plate

        // Show loading overlay
        withAnimation(.easeInOut(duration: 0.3)) {
            isShowingLoadingOverlay = true
            loadingProgress = 0.0
            loadingStep = 0
        }

        // Simulate progress steps
        simulateAnalysisProgress()

        Task {
            // Use pre-resized data if available (resized during context sheet), otherwise fall back to UIImage
            let result: [String: Any]?
            if let preData = preResizedImageData {
                result = await networkService.analyzePlateStreaming(
                    imageData: preData,
                    preferences: preferencesManager.preferences,
                    restaurantName: restaurantName,
                    dishName: dishName,
                    cuisineType: cuisineType
                )
            } else {
                result = await networkService.analyzePlateStreaming(
                    image: image,
                    preferences: preferencesManager.preferences,
                    restaurantName: restaurantName,
                    dishName: dishName,
                    cuisineType: cuisineType
                )
            }
            await MainActor.run {
                // Complete the progress
                withAnimation(.easeInOut(duration: 0.2)) {
                    loadingProgress = 1.0
                    loadingStep = 4
                }

                // Small delay to show completion
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isShowingLoadingOverlay = false
                    }

                    showPlateCheckSheet = false
                    if let result = result {
                        AppLogger.debug("✅ Plate analysis Phase 1 ready")
                        plateAnalysisResult = result
                        showPlateResults = true

                        HapticManager.shared.trigger(.success)
                    } else {
                        AppLogger.error("❌ Plate analysis failed")
                        plateErrorMessage = networkService.errorMessage ?? "Could not analyze plate. Try a clearer photo with better lighting."
                        showPlateError = true
                        HapticManager.shared.trigger(.error)
                    }
                    // Reset state
                    selectedImage = nil
                    plateCheckImage = nil
                    preResizedImageData = nil
                    usePlateCheckMode = false
                }
            }
        }
    }
}

// Clean Modern Scan Button Component with Loading State
// Fix for ModernScanButton - replace lines 770-850
struct ModernScanButton: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    let gradient: [Color]
    let action: () -> Void
    @State private var isPressed = false
    @State private var isLoading = false
    @State private var pulseScale: CGFloat = 1.0
    
    var body: some View {
        Button(action: {
            // Only trigger action on genuine tap, not scroll
        }) {
            HStack(spacing: 14) {
                // Icon Circle with loading animation
                ZStack {
                    // Background pulse when loading
                    if isLoading {
                        Circle()
                            .fill(iconColor.opacity(0.3))
                            .frame(width: 52, height: 52)
                            .scaleEffect(pulseScale)
                            .opacity(2 - pulseScale)
                            .animation(
                                .easeInOut(duration: 0.8).repeatForever(autoreverses: false),
                                value: pulseScale
                            )
                    }
                    
                    Circle()
                        .fill(iconColor.opacity(0.15))
                        .frame(width: 44, height: 44)
                    
                    if isLoading {
                        Circle()
                            .trim(from: 0, to: 0.7)
                            .stroke(iconColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                            .frame(width: 36, height: 36)
                            .rotationEffect(.degrees(pulseScale * 360))
                            .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: pulseScale)
                    } else {
                        Image(systemName: icon)
                            .font(Typography.h3)
                            .foregroundColor(iconColor)
                    }
                }

                // Text
                VStack(alignment: .leading, spacing: 3) {
                    Text(isLoading ? "Opening..." : title)
                        .font(Typography.body)
                        .foregroundColor(Theme.textPrimary)
                        .lineLimit(1)

                    Text(isLoading ? "Please wait" : subtitle)
                        .font(Typography.caption)
                        .foregroundColor(Theme.textTertiary)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(Typography.bodySmall)
                    .foregroundColor(Theme.textSecondary.opacity(0.6))
                    .accessibilityHidden(true)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Theme.surfaceSecondary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(
                        LinearGradient(
                            colors: gradient.map { $0.opacity(0.3) },
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .scaleEffect(isPressed ? 0.98 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isPressed)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(isLoading ? "Opening \(title)" : "\(title), \(subtitle)")
        .buttonStyle(PlainButtonStyle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    // Only press if minimal movement (genuine tap)
                    if abs(value.translation.height) < 5 && abs(value.translation.width) < 5 {
                        if !isPressed {
                            withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
                                isPressed = true
                            }
                        }
                    } else {
                        // User is scrolling, release press
                        if isPressed {
                            withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
                                isPressed = false
                            }
                        }
                    }
                }
                .onEnded { value in
                    // Only trigger action if it was a genuine tap (minimal movement)
                    if abs(value.translation.height) < 10 && abs(value.translation.width) < 10 {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                            isLoading = true
                            pulseScale = 1.5
                        }
                        
                        HapticManager.shared.trigger(.impactMedium)
                        
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            action()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                withAnimation { 
                                    isLoading = false 
                                    pulseScale = 1.0
                                }
                            }
                        }
                    }
                    
                    // Always release press state
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        isPressed = false
                    }
                }
        )
        .onAppear {
            pulseScale = 1.0
        }
    }
}

// MARK: - Button Style
private struct ScannerButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MARK: - Unified Analysis Loading Overlay
struct AnalysisLoadingOverlay: View {
    let progress: CGFloat
    let step: Int
    let mode: ScannerView.LoadingMode
    var productName: String? = nil
    var productBrand: String? = nil
    
    @State private var pulseAnimation = false
    @State private var rotationAngle: Double = 0
    @State private var shimmerOffset: CGFloat = -200
    
    private var steps: [(icon: String, text: String)] {
        mode.steps
    }
    
    private var primaryColor: Color {
        mode.iconColor
    }
    
    private var gradientColors: [Color] {
        switch mode {
        case .product, .visual:
            return [Theme.primary, Theme.primaryDark]
        case .barcode:
            return [Theme.info, Color(hex: "2563EB")]
        case .restaurant:
            return [Theme.warning, Color(hex: "D97706")]
        case .plate:
            return [Theme.accent, Color(hex: "7C3AED")]
        }
    }

    private var lightGradientColors: [Color] {
        switch mode {
        case .product, .visual:
            return [Theme.primary, Theme.primaryLight, Color(hex: "6EE7B7")]
        case .barcode:
            return [Theme.info, Color(hex: "60A5FA"), Color(hex: "93C5FD")]
        case .restaurant:
            return [Theme.warning, Color(hex: "FBBF24"), Color(hex: "FCD34D")]
        case .plate:
            return [Theme.accent, Color(hex: "A78BFA"), Color(hex: "C4B5FD")]
        }
    }
    
    var body: some View {
        ZStack {
            // Blurred background
            Color.black.opacity(0.95)
                .ignoresSafeArea()
            
            VStack(spacing: 32) {
                // Animated icon
                ZStack {
                    // Outer glow rings
                    ForEach(0..<3) { i in
                        Circle()
                            .stroke(
                                primaryColor.opacity(0.3 - Double(i) * 0.1),
                                lineWidth: 2
                            )
                            .frame(width: 120 + CGFloat(i * 20), height: 120 + CGFloat(i * 20))
                            .scaleEffect(pulseAnimation ? 1.1 : 1.0)
                            .animation(
                                .easeInOut(duration: 1.5)
                                .repeatForever(autoreverses: true)
                                .delay(Double(i) * 0.2),
                                value: pulseAnimation
                            )
                    }
                    
                    // Main circle with gradient
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: gradientColors,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 100, height: 100)
                        .shadow(color: primaryColor.opacity(0.5), radius: 20, y: 5)
                    
                    // Rotating ring
                    Circle()
                        .trim(from: 0, to: 0.3)
                        .stroke(
                            LinearGradient(
                                colors: [Color.white.opacity(0.8), Color.white.opacity(0.2)],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            style: StrokeStyle(lineWidth: 3, lineCap: .round)
                        )
                        .frame(width: 110, height: 110)
                        .rotationEffect(.degrees(rotationAngle))
                    
                    // Center icon with iOS 17 symbol transition
                    Image(systemName: step < steps.count ? steps[step].icon : "sparkles")
                        .contentTransition(.symbolEffect(.replace))
                        .font(.system(size: 40, weight: .medium))
                        .foregroundColor(Theme.textPrimary)
                        .scaleEffect(pulseAnimation ? 1.1 : 1.0)
                        .animation(
                            .easeInOut(duration: 0.8)
                            .repeatForever(autoreverses: true),
                            value: pulseAnimation
                        )
                }
                
                // Status text with optional product info
                VStack(spacing: 16) {
                    // Product info (if available)
                    if let name = productName {
                        VStack(spacing: 6) {
                            Text(name)
                                .font(Typography.h4)
                                .foregroundColor(Theme.textPrimary)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)

                            if let brand = productBrand, !brand.isEmpty {
                                Text(brand)
                                    .font(Typography.bodySmall)
                                    .foregroundColor(Theme.textMuted)
                            }
                        }
                        .padding(.horizontal, 40)
                        .padding(.bottom, 8)
                    }
                    
                    // Analysis step text
                    Text(step < steps.count ? steps[step].text : "Processing...")
                        .font(Typography.body)
                        .foregroundColor(primaryColor)
                        .animation(.easeInOut(duration: 0.3), value: step)
                }
                
                // Progress bar
                VStack(spacing: 12) {
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            // Background track
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Theme.surfaceSecondary)
                                .frame(height: 10)
                            
                            // Progress fill with gradient
                            RoundedRectangle(cornerRadius: 6)
                                .fill(
                                    LinearGradient(
                                        colors: lightGradientColors,
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: geometry.size.width * progress, height: 10)
                                .shadow(color: primaryColor.opacity(0.6), radius: 8, y: 2)
                            
                            // Shimmer effect
                            RoundedRectangle(cornerRadius: 6)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(0),
                                            Color.white.opacity(0.3),
                                            Color.white.opacity(0)
                                        ],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: 60, height: 10)
                                .offset(x: shimmerOffset)
                                .mask(
                                    RoundedRectangle(cornerRadius: 6)
                                        .frame(width: geometry.size.width * progress, height: 10)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                )
                        }
                    }
                    .frame(height: 10)
                    .padding(.horizontal, 40)
                    
                    // Percentage
                    Text("\(Int(progress * 100))%")
                        .font(Typography.bodySmall)
                        .foregroundColor(primaryColor)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(primaryColor.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .accessibilityLabel("\(Int(progress * 100)) percent")
                }
                
                // Step indicators
                HStack(spacing: 8) {
                    ForEach(0..<4) { i in
                        Circle()
                            .fill(i <= step ? primaryColor : Theme.surfaceSecondary)
                            .frame(width: 8, height: 8)
                            .scaleEffect(i == step ? 1.3 : 1.0)
                            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: step)
                    }
                }
                .padding(.top, 8)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Step \(step + 1) of 4")
            }
        }
        .onAppear {
            pulseAnimation = true
            
            // Start rotation animation
            withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
                rotationAngle = 360
            }
            
            // Shimmer animation
            withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                shimmerOffset = 300
            }
        }
    }
}

// MARK: - Shimmer Overlay for idle scan button

private struct ShimmerOverlay: View {
    @State private var shimmerX: CGFloat = -200

    var body: some View {
        GeometryReader { geo in
            LinearGradient(
                colors: [
                    Color.white.opacity(0),
                    Color.white.opacity(0.08),
                    Color.white.opacity(0)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: 80)
            .offset(x: shimmerX)
            .onAppear {
                guard geo.size.width > 0 else { return }
                shimmerX = -80
                withAnimation(.linear(duration: 2.5).repeatForever(autoreverses: false)) {
                    shimmerX = geo.size.width + 80
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .allowsHitTesting(false)
    }
}
