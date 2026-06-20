//
//  ResultsView-Redesigned.swift
//  Ethica
//
//  Clean, visual redesign with swipeable alternatives
//

import SwiftUI
import Combine

struct ResultsView: View {
    let result: AnalysisResult
    let onDismiss: () -> Void

    @State private var currentResult: AnalysisResult
    @State private var isEnhancingWithAI = false
    @State private var selectedAlternativeIndex: Int = 0
    @State private var showPurchaseDecisionModal = false
    @State private var expandedSections: Set<String> = []
    @State private var showFullDetailsSheet = false
    @State private var showComparisonView = false
    @State private var showAlternatives = false  // Collapsible alternatives section
    @State private var alternatives: [AnalysisResult.Alternative] = []
    @State private var isLoadingAlternatives = false
    @State private var showCelebration = false
    @State private var triggerUnsafeShake = false
    @State private var showRedFlash = false

    /// Stable history record ID — doesn't change when enhanced result replaces preliminary.
    @State private var originalHistoryId: UUID

    init(result: AnalysisResult, onDismiss: @escaping () -> Void) {
        self.result = result
        self.onDismiss = onDismiss
        self._currentResult = State(initialValue: result)
        self._isEnhancingWithAI = State(initialValue: result.sourceType == "preliminary")
        self._originalHistoryId = State(initialValue: result.id)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.backgroundPrimary
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: Spacing.lg) {
                        // Compact header with product name
                        headerSection

                        // AI enhancement indicator
                        if isEnhancingWithAI {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .tint(.white.opacity(0.7))
                                    .scaleEffect(0.8)
                                Text("Enhancing with AI...")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.white.opacity(0.7))
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Color.white.opacity(0.08))
                            .cornerRadius(20)
                            .transition(.opacity.combined(with: .scale(scale: 0.95)))
                        }

                        // Visual hero verdict card
                        ZStack {
                            heroVerdictCard
                                .shakeEffect(trigger: triggerUnsafeShake)
                                .overlay {
                                    if showRedFlash {
                                        RoundedRectangle(cornerRadius: Spacing.radiusMD)
                                            .fill(Theme.error.opacity(0.15))
                                            .allowsHitTesting(false)
                                            .transition(.opacity)
                                    }
                                }

                            // Celebration confetti overlay
                            if showCelebration {
                                ConfettiEffect(isActive: showCelebration, style: .celebration)
                                    .frame(height: 300)
                                    .allowsHitTesting(false)
                            }
                        }
                        .scaleIn(delay: 0.1)
                        .onAppear {
                            let state = safetyState
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                                if state == .safe && currentResult.healthScore >= 90 {
                                    showCelebration = true
                                    HapticManager.shared.sequence(.celebration)
                                } else if state == .avoid {
                                    triggerUnsafeShake = true
                                    withAnimation(.easeInOut(duration: 0.3)) { showRedFlash = true }
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                        withAnimation(.easeOut(duration: 0.4)) { showRedFlash = false }
                                    }
                                    HapticManager.shared.sequence(.warningPulse)
                                }
                            }
                        }

                        // Quick stats row
                        quickStatsRow

                        // Compact violations/warnings pills
                        if hasIssues {
                            issuesPillsSection
                        }

                        // Detected allergens
                        if !currentResult.detectedAllergens.isEmpty {
                            detectedAllergensSection
                        }

                        // Cross-contamination risks (shared equipment warnings)
                        if let risks = currentResult.crossContaminationRisks, !risks.isEmpty {
                            crossContaminationSection(risks: risks)
                        }

                        // Environmental impact visual
                        if currentResult.co2Emissions > 0 || currentResult.waterUsage > 0 {
                            environmentalImpactCard
                        }

                        // Additives section (if any detected)
                        if !currentResult.additives.isEmpty {
                            additivesQuickSection
                        }

                        // Collapsible alternatives section (if available or loading) - MOVED AFTER ADDITIVES
                        if !filteredAlternatives.isEmpty || isLoadingAlternatives {
                            alternativesSection
                                .padding(.top, Spacing.md)
                        }

                        // Action buttons
                        actionButtons
                    }
                    .padding(.horizontal, Spacing.screenHorizontal)
                    .padding(.vertical, Spacing.screenVertical)
                }
            }
            .navigationBarHidden(true)
            .overlay {
                if showPurchaseDecisionModal {
                    purchaseDecisionModal
                }
            }
        }
        .onAppear {
            alternatives = currentResult.alternatives
            if !currentResult.violations.isEmpty {
                HapticManager.shared.trigger(.warning)
            }
        }
        .task(id: alternativesSignature) {
            await enrichAlternativesIfNeeded()
        }
        .task {
            // Lazy-load alternatives if they weren't included in the initial response
            if alternatives.isEmpty, let metadata = currentResult.alternativesMetadata {
                isLoadingAlternatives = true
                let fetched = await NetworkService.shared.fetchAlternatives(
                    metadata: metadata,
                    preferences: PreferencesManager.shared.preferences
                )
                await MainActor.run {
                    if !fetched.isEmpty {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            alternatives = fetched
                        }
                        // Update AI cache so re-scans include alternatives
                        if let barcode = currentResult.sourceBarcode {
                            let updated = currentResult.withAlternatives(fetched)
                            Task {
                                await AIResultsCacheService.shared.save(
                                    barcode: barcode,
                                    preferences: PreferencesManager.shared.preferences,
                                    result: updated
                                )
                            }
                        }
                    }
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isLoadingAlternatives = false
                    }
                }
            }
        }
        .task {
            // Progressive update: observe enhanced AI result from streaming/background enrichment
            guard isEnhancingWithAI else { return }
            let expectedBarcode = currentResult.sourceBarcode

            // Check if an enhanced result is already available (CurrentValueSubject replays last value)
            if let existing = ProductDatabaseService.enhancedResultSubject.value,
               expectedBarcode == nil || existing.sourceBarcode == expectedBarcode {
                withAnimation(.easeInOut(duration: 0.4)) {
                    currentResult = currentResult.mergingEnrichment(from: existing)
                    if !existing.alternatives.isEmpty {
                        alternatives = existing.alternatives
                    }
                    isEnhancingWithAI = false
                }
                // Trigger alternatives fetch if still empty
                if alternatives.isEmpty, !isLoadingAlternatives, let metadata = existing.alternativesMetadata {
                    isLoadingAlternatives = true
                    let fetched = await NetworkService.shared.fetchAlternatives(
                        metadata: metadata,
                        preferences: PreferencesManager.shared.preferences
                    )
                    if !fetched.isEmpty {
                        withAnimation(.easeInOut(duration: 0.3)) { alternatives = fetched }
                        if let barcode = existing.sourceBarcode {
                            let updated = existing.withAlternatives(fetched)
                            await AIResultsCacheService.shared.save(
                                barcode: barcode,
                                preferences: PreferencesManager.shared.preferences,
                                result: updated
                            )
                        }
                    }
                    withAnimation(.easeInOut(duration: 0.3)) { isLoadingAlternatives = false }
                }
                // Clear so next scan doesn't pick up stale value
                ProductDatabaseService.enhancedResultSubject.send(nil)
                return
            }

            for await enhanced in ProductDatabaseService.enhancedResultSubject.values {
                guard let enhanced = enhanced else { continue } // Skip nil values
                // Guard: only accept enrichment for the same barcode we're displaying
                if let expected = expectedBarcode, let incoming = enhanced.sourceBarcode, expected != incoming {
                    continue  // Skip enrichment for a different product
                }
                withAnimation(.easeInOut(duration: 0.4)) {
                    currentResult = currentResult.mergingEnrichment(from: enhanced)
                    if !enhanced.alternatives.isEmpty {
                        alternatives = enhanced.alternatives
                    }
                    isEnhancingWithAI = false
                }
                // Trigger alternatives fetch if still empty
                if alternatives.isEmpty, !isLoadingAlternatives, let metadata = enhanced.alternativesMetadata {
                    isLoadingAlternatives = true
                    let fetched = await NetworkService.shared.fetchAlternatives(
                        metadata: metadata,
                        preferences: PreferencesManager.shared.preferences
                    )
                    if !fetched.isEmpty {
                        withAnimation(.easeInOut(duration: 0.3)) { alternatives = fetched }
                        if let barcode = enhanced.sourceBarcode {
                            let updated = enhanced.withAlternatives(fetched)
                            await AIResultsCacheService.shared.save(
                                barcode: barcode,
                                preferences: PreferencesManager.shared.preferences,
                                result: updated
                            )
                        }
                    }
                    withAnimation(.easeInOut(duration: 0.3)) { isLoadingAlternatives = false }
                }
                // Cache the enhanced result
                if let barcode = enhanced.sourceBarcode {
                    await AIResultsCacheService.shared.save(
                        barcode: barcode,
                        preferences: PreferencesManager.shared.preferences,
                        result: enhanced
                    )
                }
                // Clear so next scan doesn't pick up stale value
                ProductDatabaseService.enhancedResultSubject.send(nil)
                break // Only need the first value
            }
        }
        .task {
            // Timeout: dismiss "Enhancing with AI" spinner after 15s to prevent perpetual spinner
            guard isEnhancingWithAI else { return }
            try? await Task.sleep(nanoseconds: 15_000_000_000)
            if isEnhancingWithAI {
                withAnimation { isEnhancingWithAI = false }
            }
        }
        .sheet(isPresented: $showComparisonView) {
            ProductComparisonView(
                currentProduct: currentResult,
                alternatives: alternatives
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .premiumSheet()
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(currentResult.productName)
                    .textStyleH1()
                    .lineLimit(2)

                if let brand = currentResult.brand, !brand.isEmpty {
                    Text(brand)
                        .textStyleBodySmall()
                }
            }

            Spacer()

            ShareLink(item: shareSummary) {
                Image(systemName: "square.and.arrow.up.circle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(Theme.textMuted)
            }
            .accessibilityLabel("Share results")

            Button(action: { onDismiss() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(Theme.textMuted)
            }
            .accessibilityLabel("Close results")
        }
        .padding(.top, 8)
    }

    // MARK: - Share Summary

    private var shareSummary: String {
        var lines = ["\(currentResult.productName) — Ethica Scan"]
        if !currentResult.violations.isEmpty {
            lines.append("⚠️ \(currentResult.violations.count) violation(s): \(currentResult.violations.joined(separator: ", "))")
        } else {
            lines.append("✅ Safe for you")
        }
        if currentResult.healthScore > 0 {
            lines.append("Health: \(Int(currentResult.healthScore))/100")
        }
        if currentResult.co2Emissions > 0 {
            lines.append("CO₂: \(String(format: "%.1f", currentResult.co2Emissions))kg")
        }
        lines.append("Scanned with Ethica")
        return lines.joined(separator: "\n")
    }

    // MARK: - Hero Verdict Card

    private var safetyState: SafetyState {
        if !currentResult.violations.isEmpty {
            return .avoid  // Real dietary violations → red
        } else if !currentResult.warnings.isEmpty || !currentResult.cautionWarnings.isEmpty {
            return .caution  // Cautions/warnings but no hard violations → yellow
        } else if !currentResult.isSafe {
            return .caution  // Backend says not safe but no specific violations → yellow
        } else {
            return .safe  // All clear → green
        }
    }

    private var ambientVerdict: AmbientGradient.AmbientVerdict {
        switch safetyState {
        case .safe: return .safe
        case .caution: return .caution
        case .avoid: return .unsafe
        }
    }

    @ViewBuilder
    private var heroVerdictCard: some View {
        let state = safetyState
        GlassCard(variant: state.variant) {
            VStack(spacing: Spacing.md) {
                // Colored accent capsule at top
                Capsule()
                    .fill(state.color)
                    .frame(width: 60, height: 3)

                // Icon with glowing backdrop
                ZStack {
                    Circle()
                        .fill(state.color.opacity(0.3))
                        .blur(radius: 20)
                        .frame(width: 72, height: 72)

                    Image(systemName: state.icon)
                        .font(.system(size: 48))
                        .foregroundColor(state.color)
                        .symbolEffect(.bounce, value: true)
                }
                .glowPulse(color: state.color, intensity: 0.5, speed: 2.0)

                Text(state.title)
                    .textStyleH2()
                    .multilineTextAlignment(.center)

                Text(safetySubtitle)
                    .textStyleBody()
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
            }
            .frame(maxWidth: .infinity)
        }
        .ambientVerdict(ambientVerdict)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Product safety: \(state.title). \(safetySubtitle)")
    }

    private var safetySubtitle: String {
        if !currentResult.violations.isEmpty {
            // Show the first violation reason directly
            let first = cleanIssueText(currentResult.violations.first ?? "")
            if currentResult.violations.count == 1 {
                return first
            } else {
                return "\(first) (+\(currentResult.violations.count - 1) more)"
            }
        } else if !currentResult.warnings.isEmpty {
            let first = cleanIssueText(currentResult.warnings.first ?? "")
            if currentResult.warnings.count == 1 {
                return first
            } else {
                return "\(first) (+\(currentResult.warnings.count - 1) more)"
            }
        } else if !currentResult.cautionWarnings.isEmpty {
            let first = cleanIssueText(currentResult.cautionWarnings.first ?? "")
            if currentResult.cautionWarnings.count == 1 {
                return first
            } else {
                return "\(first) (+\(currentResult.cautionWarnings.count - 1) more)"
            }
        } else if !currentResult.isSafe {
            return "Some ingredients need review"
        } else {
            return "No conflicts with your preferences"
        }
    }

    // MARK: - Quick Stats Row

    private var quickStatsRow: some View {
        HStack(spacing: Spacing.md) {
            // Health score
            if currentResult.healthScore > 0 {
                ScoreCircle(
                    score: currentResult.healthScore,
                    size: .medium,
                    showLabel: true,
                    label: "Health",
                    showGlow: true,
                    revealMode: true
                )
                .scaleIn(delay: 0.2)
            }

            // Environmental score
            if currentResult.environmentalScore > 0 {
                ScoreCircle(
                    score: currentResult.environmentalScore,
                    size: .medium,
                    showLabel: true,
                    label: "Eco"
                )
                .scaleIn(delay: 0.3)
            }

            // Animal impact badge
            if !currentResult.animalImpact.isEmpty {
                animalImpactBadge
            }
        }
    }

    private var animalImpactBadge: some View {
        let color = impactColor(currentResult.animalImpact)
        return VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: impactIcon(currentResult.animalImpact))
                    .font(.system(size: 20))
                    .foregroundColor(color)
            }
            Text(currentResult.animalImpact)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Theme.textSecondary)
            Text("Animal")
                .font(.system(size: 10))
                .foregroundColor(Theme.textMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(color.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(color.opacity(0.15), lineWidth: 1)
                )
        )
        .scaleIn(delay: 0.35)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Animal impact: \(currentResult.animalImpact)")
    }

    private func impactIcon(_ impact: String) -> String {
        let lower = impact.lowercased()
        if lower.contains("high") { return "flame.fill" }
        if lower.contains("medium") || lower.contains("moderate") { return "pawprint.fill" }
        if lower.contains("low") || lower.contains("plant") { return "leaf.fill" }
        switch impact.uppercased() {
        case "A", "B": return "leaf.fill"
        case "C": return "pawprint.fill"
        case "D", "E": return "flame.fill"
        default: return "leaf.fill"
        }
    }

    private func impactColor(_ impact: String) -> Color {
        let lower = impact.lowercased()
        if lower.contains("high") { return Theme.error }
        if lower.contains("medium") || lower.contains("moderate") { return Theme.warning }
        if lower.contains("low") || lower.contains("plant") { return Theme.success }
        switch impact.uppercased() {
        case "A", "B": return Theme.success
        case "C": return Theme.warning
        case "D", "E": return Theme.error
        default: return Theme.textSecondary
        }
    }

    // MARK: - Issues Pills Section

    private var hasIssues: Bool {
        !currentResult.violations.isEmpty || !currentResult.warnings.isEmpty || !currentResult.cautionWarnings.isEmpty
    }

    private var issuesPillsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            // Violations
            if !currentResult.violations.isEmpty {
                issueCategory(
                    title: "Dietary Violations",
                    items: currentResult.violations,
                    icon: "xmark.circle.fill",
                    color: Theme.error,
                    variant: .error,
                    sectionKey: "violations"
                )
            }

            // Warnings (GMO, etc)
            if !currentResult.warnings.isEmpty {
                issueCategory(
                    title: "Product Warnings",
                    items: currentResult.warnings,
                    icon: "exclamationmark.triangle.fill",
                    color: Theme.warning,
                    variant: .warning,
                    sectionKey: "warnings"
                )
            }

            // Cautions
            if !currentResult.cautionWarnings.isEmpty {
                issueCategory(
                    title: "Caution Items",
                    items: currentResult.cautionWarnings,
                    icon: "info.circle.fill",
                    color: Theme.info,
                    variant: .primary,
                    sectionKey: "cautions"
                )
            }
        }
    }

    private func issueCategory(title: String, items: [String], icon: String, color: Color, variant: GlassCardVariant, sectionKey: String) -> some View {
        let isExpanded = expandedSections.contains(sectionKey)
        let previewItems = isExpanded ? items : Array(items.prefix(2))

        return GlassCard(variant: variant) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                // Header with count badge
                HStack {
                    Label(title, systemImage: icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(color)

                    Spacer()

                    StatusBadge("\(items.count)", variant: variant == .error ? .error : .warning, size: .small)
                }

                // Items with SF Symbol icons instead of dots
                VStack(spacing: 8) {
                    ForEach(Array(previewItems.enumerated()), id: \.element) { index, item in
                        HStack(spacing: 8) {
                            Image(systemName: icon)
                                .font(.system(size: 10))
                                .foregroundColor(color)

                            Text(cleanIssueText(item))
                                .font(.system(size: 13))
                                .foregroundColor(Theme.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)

                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(color.opacity(0.08))
                        .cornerRadius(8)
                    }
                }

                // Show more/less button
                if items.count > 2 {
                    Button(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            if isExpanded {
                                expandedSections.remove(sectionKey)
                            } else {
                                expandedSections.insert(sectionKey)
                            }
                        }
                        HapticManager.shared.trigger(.impactLight)
                    }) {
                        HStack {
                            Text(isExpanded ? "Show less" : "Show \(items.count - 2) more")
                                .font(.system(size: 13, weight: .medium))
                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                .font(.system(size: 11))
                        }
                        .foregroundColor(color)
                        .padding(.top, 4)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(title): \(items.count) item\(items.count == 1 ? "" : "s")")
    }

    private func cleanIssueText(_ text: String) -> String {
        // Remove emoji prefixes like ⛔, ⚠️, 🧬, ℹ️, ❌, ✓, etc
        var cleaned = text
        while let first = cleaned.unicodeScalars.first,
              !first.properties.isAlphabetic && !first.properties.isASCIIHexDigit && first != "(" {
            cleaned = String(cleaned.unicodeScalars.dropFirst())
        }
        return cleaned.trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Detected Allergens Section

    private var userAllergens: Set<String> {
        PreferencesManager.shared.preferences.selectedAllergens
    }

    private func allergenMatchesUserPrefs(_ allergen: String) -> Bool {
        return userAllergens.contains(where: { ProductDatabaseService.allergensMatch(allergen, $0) })
    }

    private var detectedAllergensSection: some View {
        let hasUserMatch = currentResult.detectedAllergens.contains(where: { allergenMatchesUserPrefs($0) })
        let isExpanded = expandedSections.contains("detectedAllergens")
        let evidenceItems = currentResult.detectionEvidence
        let previewEvidence = isExpanded ? evidenceItems : Array(evidenceItems.prefix(2))

        return GlassCard(variant: hasUserMatch ? .error : .warning) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                // Header
                HStack {
                    Label("Detected Allergens", systemImage: "allergens")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(hasUserMatch ? Theme.error : Theme.warning)

                    Spacer()

                    StatusBadge("\(currentResult.detectedAllergens.count)", variant: hasUserMatch ? .error : .warning, size: .small)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Detected allergens: \(currentResult.detectedAllergens.count)")

                // Allergen pills
                FlowLayout(spacing: Spacing.xs) {
                    ForEach(currentResult.detectedAllergens, id: \.self) { allergen in
                        StatusBadge(
                            allergen,
                            icon: allergenMatchesUserPrefs(allergen) ? "exclamationmark.triangle.fill" : nil,
                            variant: allergenMatchesUserPrefs(allergen) ? .error : .warning,
                            size: .small
                        )
                    }
                }

                // Detection evidence (collapsible)
                if !evidenceItems.isEmpty {
                    VStack(spacing: 6) {
                        ForEach(Array(previewEvidence.enumerated()), id: \.offset) { _, evidence in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "arrow.right.circle.fill")
                                    .font(.system(size: 10))
                                    .foregroundColor(hasUserMatch ? Theme.error : Theme.warning)
                                    .padding(.top, 3)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(evidence.ingredient) → \(evidence.matchedPreference)")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(Theme.textPrimary)
                                    Text(evidence.reason)
                                        .font(.system(size: 11))
                                        .foregroundColor(Theme.textSecondary)
                                        .lineLimit(2)
                                    if evidence.confidence > 0 {
                                        Text("\(Int(evidence.confidence))% confidence")
                                            .font(.system(size: 10, weight: .medium))
                                            .foregroundColor(Theme.textMuted)
                                    }
                                }

                                Spacer()
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background((hasUserMatch ? Theme.error : Theme.warning).opacity(0.06))
                            .cornerRadius(8)
                        }
                    }

                    // Show more/less
                    if evidenceItems.count > 2 {
                        Button(action: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                if isExpanded {
                                    expandedSections.remove("detectedAllergens")
                                } else {
                                    expandedSections.insert("detectedAllergens")
                                }
                            }
                            HapticManager.shared.trigger(.impactLight)
                        }) {
                            HStack {
                                Text(isExpanded ? "Show less" : "Show \(evidenceItems.count - 2) more")
                                    .font(.system(size: 13, weight: .medium))
                                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 11))
                            }
                            .foregroundColor(hasUserMatch ? Theme.error : Theme.warning)
                            .padding(.top, 4)
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Detected allergens: \(currentResult.detectedAllergens.joined(separator: ", "))")
    }

    // MARK: - Cross-Contamination Risks Section

    private func crossContaminationSection(risks: [AnalysisResult.CrossContaminationRisk]) -> some View {
        let isExpanded = expandedSections.contains("crossContamination")
        let previewRisks = isExpanded ? risks : Array(risks.prefix(2))

        return GlassCard(variant: .warning) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                // Header
                HStack {
                    Label("Cross-Contamination Risks", systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Theme.warning)

                    Spacer()

                    StatusBadge("\(risks.count)", variant: .warning, size: .small)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Cross-contamination risks: \(risks.count) identified")

                // Risk items
                VStack(spacing: 8) {
                    ForEach(previewRisks) { risk in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 10))
                                    .foregroundColor(riskColor(for: risk.riskLevel))

                                Text(risk.allergen)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(Theme.textPrimary)

                                StatusBadge(risk.riskLevel, variant: risk.riskLevel.lowercased().contains("high") ? .error : .warning, size: .small)

                                Spacer()
                            }

                            Text(risk.riskExplanation)
                                .font(.system(size: 12))
                                .foregroundColor(Theme.textSecondary)

                            if !risk.guidance.isEmpty {
                                Text(risk.guidance)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(Theme.warning)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Theme.warning.opacity(0.06))
                        .cornerRadius(8)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(risk.allergen), risk level \(risk.riskLevel). \(risk.riskExplanation)\(risk.guidance.isEmpty ? "" : ". \(risk.guidance)")")
                    }
                }

                // Show more/less
                if risks.count > 2 {
                    Button(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            if isExpanded {
                                expandedSections.remove("crossContamination")
                            } else {
                                expandedSections.insert("crossContamination")
                            }
                        }
                        HapticManager.shared.trigger(.impactLight)
                    }) {
                        HStack {
                            Text(isExpanded ? "Show less" : "Show \(risks.count - 2) more")
                                .font(.system(size: 13, weight: .medium))
                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                .font(.system(size: 11))
                        }
                        .foregroundColor(Theme.warning)
                        .padding(.top, 4)
                    }
                    .accessibilityLabel(isExpanded ? "Show fewer cross-contamination risks" : "Show \(risks.count - 2) more cross-contamination risks")
                }
            }
        }
    }

    private func riskColor(for level: String) -> Color {
        switch level.lowercased() {
        case "high", "very high": return Theme.error
        case "medium": return Theme.warning
        case "low": return Theme.info
        default: return Theme.warning
        }
    }

    // MARK: - Alternatives Section (Collapsible)

    private var alternativesSection: some View {
        VStack(spacing: 0) {
            if isLoadingAlternatives && alternatives.isEmpty {
                // Loading state
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Theme.primary.opacity(0.2))
                            .frame(width: 40, height: 40)

                        ProgressView()
                            .tint(Theme.primary)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Finding Alternatives...")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(Theme.textPrimary)
                            .lineLimit(1)

                        Text("Searching for better options")
                            .font(.system(size: 12))
                            .foregroundColor(Theme.textSecondary)
                            .lineLimit(1)
                    }

                    Spacer()
                }
                .padding(14)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Theme.surfaceBase)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Theme.primary.opacity(0.2), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 2)
            } else {
                // Compact toggle button
                Button(action: {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                    showAlternatives.toggle()
                }
                HapticManager.shared.trigger(.impactMedium)
            }) {
                HStack(spacing: 12) {
                    // Icon
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Theme.primary.opacity(0.2))
                            .frame(width: 40, height: 40)

                        Image(systemName: showAlternatives ? "chevron.up" : "sparkles")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(Theme.primary)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Better Alternatives")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(Theme.textPrimary)
                            .lineLimit(1)

                        Text("\(alternatives.count) option\(alternatives.count == 1 ? "" : "s") available")
                            .font(.system(size: 12))
                            .foregroundColor(Theme.textSecondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Image(systemName: showAlternatives ? "chevron.up" : "chevron.down")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Theme.textSecondary)
                }
                .padding(14)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Theme.surfaceBase)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Theme.primary.opacity(0.2), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 2)
            }
            .buttonStyle(.plain)

            // Expanded content
            if showAlternatives {
                alternativesCarousel
                    .padding(.top, 16)
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .move(edge: .top).combined(with: .opacity)
                    ))
            }
            } // end else (non-loading state)
        }
    }

    // MARK: - Alternatives Intro Header

    private var alternativesIntroHeader: some View {
        HStack(spacing: Spacing.md) {
            // Icon with gradient background
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        LinearGradient(
                            colors: [Theme.primary, Theme.primary.opacity(0.6)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 48, height: 48)

                Image(systemName: "sparkles")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Better Choices Available")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(Theme.textPrimary)

                Text(alternativesHeaderText)
                    .font(.system(size: 13))
                    .foregroundColor(Theme.textSecondary)
                    .lineLimit(2)
            }

            Spacer()
        }
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Theme.surfaceBase)
                .shadow(color: Theme.primary.opacity(0.1), radius: 12, x: 0, y: 4)
        )
    }

    /// When product is completely safe, only show alternatives that are actually better on at least one dimension.
    private var filteredAlternatives: [AnalysisResult.Alternative] {
        let withoutSelf = alternatives.filter { alt in
            // Exclude the scanned product itself from alternatives
            let nameMatch = alt.name.localizedCaseInsensitiveCompare(currentResult.productName) == .orderedSame
            let brandMatch: Bool = {
                guard let altBrand = alt.brand, let resultBrand = currentResult.brand else { return false }
                return altBrand.localizedCaseInsensitiveCompare(resultBrand) == .orderedSame
            }()
            return !(nameMatch || (brandMatch && alt.name.lowercased().contains(currentResult.productName.lowercased())))
        }
        // Only score-filter when product has no issues — and only compare
        // dimensions the alternative actually has (nil = unknown, not "zero")
        guard !hasIssues else { return withoutSelf }
        return withoutSelf.filter { alt in
            let healthBetter = alt.displayHealthScore > currentResult.healthScore
            let envBetter = alt.displayEnvironmentalScore > currentResult.environmentalScore
            let ethicsBetter = alt.displayEthicsScore > currentResult.animalWelfareScore
            return healthBetter || envBetter || ethicsBetter
        }
    }

    private var alternativesHeaderText: String {
        if !currentResult.violations.isEmpty {
            return "\(filteredAlternatives.count) product\(filteredAlternatives.count == 1 ? "" : "s") match your preferences"
        } else if currentResult.healthScore < 60 {
            return "\(filteredAlternatives.count) healthier option\(filteredAlternatives.count == 1 ? "" : "s")"
        } else {
            return "\(filteredAlternatives.count) recommended alternative\(filteredAlternatives.count == 1 ? "" : "s")"
        }
    }

    // MARK: - Alternatives Carousel

    private var alternativesCarousel: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Horizontal scroll with snapping
            if #available(iOS 17.0, *) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(Array(filteredAlternatives.enumerated()), id: \.offset) { index, alternative in
                            premiumAlternativeCard(alternative, index: index)
                                .containerRelativeFrame(.horizontal, count: 1, spacing: 16)
                                .scrollTransition { content, phase in
                                    content
                                        .opacity(phase.isIdentity ? 1.0 : 0.7)
                                        .scaleEffect(phase.isIdentity ? 1.0 : 0.95)
                                }
                        }
                    }
                    .scrollTargetLayout()
                    .padding(.bottom, 8)
                }
                .scrollTargetBehavior(.viewAligned)
            } else {
                // Fallback for iOS 16
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(Array(filteredAlternatives.enumerated()), id: \.offset) { index, alternative in
                            premiumAlternativeCard(alternative, index: index)
                                .frame(width: UIScreen.main.bounds.width - 48)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                }
            }

            // Compare All button - completely separate from scroll
            compareAllButton
        }
    }
    
    private var compareAllButton: some View {
        Button(action: {
            showComparisonView = true
            HapticManager.shared.trigger(.impactMedium)
        }) {
            HStack(spacing: 12) {
                Image(systemName: "chart.bar.doc.horizontal")
                    .font(.system(size: 18, weight: .semibold))

                Text("Compare All Products")
                    .font(.system(size: 16, weight: .bold))

                Spacer()

                Image(systemName: "chevron.right.circle.fill")
                    .font(.system(size: 20))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Theme.primary)
            )
        }
        .buttonStyle(.plain)
    }

    private var alternativesSignature: String {
        alternatives.map { "\($0.name)|\($0.barcode ?? "")|\($0.isEnriched)" }.joined(separator: ";")
    }

    private func enrichAlternativesIfNeeded() async {
        guard !alternatives.isEmpty else { return }
        let needsEnrichment = alternatives.contains { $0.healthScore == nil && $0.barcode == nil }
        guard needsEnrichment else { return }

        let enriched = await NetworkService.shared.enrichAlternatives(alternatives)
        await MainActor.run {
            guard !enriched.isEmpty else { return }
            withAnimation(.easeInOut(duration: 0.3)) {
                alternatives = enriched
            }
        }
    }

    private func openAlternativeInBrowser(_ alternative: AnalysisResult.Alternative) {
        HistoryService.shared.logAlternativeInteraction(
            alternativeName: alternative.name,
            alternativeBrand: alternative.brand,
            originalProduct: currentResult.productName,
            action: "viewed"
        )

        guard let url = alternative.productURL else {
            AppLogger.warning("⚠️ No URL for alternative: \(alternative.name)")
            return
        }

        UIApplication.shared.open(url, options: [:]) { opened in
            if !opened {
                AppLogger.error("❌ Failed to open alternative URL: \(url.absoluteString)")
            }
        }
        HapticManager.shared.trigger(.impactMedium)
    }

    // Premium alternative card design
    @ViewBuilder
    private func premiumAlternativeCard(_ alternative: AnalysisResult.Alternative, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
                // Rank badge inline
                rankBadge(for: index)

                // Product name & brand
                VStack(alignment: .leading, spacing: 4) {
                    Text(alternative.name)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(Theme.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    if let brand = alternative.brand, !brand.isEmpty {
                        Text(brand)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Theme.textSecondary)
                    }
                }

                // Why it's better (compact)
                if let reason = alternative.reason, !reason.isEmpty {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 12))
                            .foregroundColor(Theme.primary)
                            .padding(.top, 2)

                        Text(condensedReason(reason))
                            .font(.system(size: 12))
                            .foregroundColor(Theme.textPrimary)
                            .lineLimit(2)
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Theme.primary.opacity(0.08))
                    )
                }

                // Health, Environmental, Ethics Scores
                scoresRow(for: alternative)

            // View product CTA — dedicated button (not whole-card) so taps work inside horizontal scroll
            Button(action: {
                openAlternativeInBrowser(alternative)
            }) {
                HStack {
                    Text("View Details")
                        .font(.system(size: 14, weight: .semibold))
                    Spacer()
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.system(size: 16))
                }
                .foregroundColor(.white)
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Theme.primary)
                )
            }
            .buttonStyle(.plain)
            .buttonPressAnimation()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Theme.surfaceSecondary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(
                    LinearGradient(
                        colors: gradientForRank(index),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ).opacity(0.4),
                    lineWidth: 1.5
                )
        )
        // Top accent capsule
        .overlay(alignment: .top) {
            Capsule()
                .fill(rankInfo(for: index).2)
                .frame(width: 80, height: 3)
                .offset(y: -1.5)
        }
    }

    private func rankBadge(for index: Int) -> some View {
        let (label, icon, color) = rankInfo(for: index)

        return HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
            Text(label)
                .font(.system(size: 12, weight: .bold))
                .textCase(.uppercase)
        }
        .foregroundColor(color)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(.white.opacity(0.95))
                .shadow(color: color.opacity(0.3), radius: 8, x: 0, y: 4)
        )
    }

    private func rankInfo(for index: Int) -> (String, String, Color) {
        switch index {
        case 0: return ("Top Pick", "star.fill", Theme.warning)
        case 1: return ("Runner-Up", "medal.fill", Theme.warning)
        case 2: return ("Good Choice", "checkmark.circle.fill", Theme.success)
        default: return ("Option \(index + 1)", "circle.fill", Theme.textMuted)
        }
    }

    private func gradientForRank(_ index: Int) -> [Color] {
        switch index {
        case 0: return [Theme.warning.opacity(0.3), Theme.warning.opacity(0.2)]
        case 1: return [Theme.warning.opacity(0.3), Theme.error.opacity(0.2)]
        case 2: return [Theme.success.opacity(0.3), Theme.primary.opacity(0.2)]
        default: return [Theme.primary.opacity(0.3), Theme.primary.opacity(0.1)]
        }
    }

    private func impactStatsRow(for alternative: AnalysisResult.Alternative) -> some View {
        HStack(spacing: 12) {
            if let co2 = alternative.estimatedCO2, co2 > 0 {
                impactStatPill(
                    icon: "leaf.fill",
                    value: "\(String(format: "%.1f", co2))kg CO₂",
                    improvement: co2Improvement(alternative),
                    color: Theme.success
                )
            }

            if let water = alternative.estimatedWater, water > 0 {
                impactStatPill(
                    icon: "drop.fill",
                    value: "\(Int(water))L",
                    improvement: waterImprovement(alternative),
                    color: Theme.info
                )
            }
        }
    }

    // Health, Environmental, and Ethics scores row WITH DELTAS
    private func scoresRow(for alternative: AnalysisResult.Alternative) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                scoreCardWithDelta(
                    title: "Health",
                    score: alternative.displayHealthScore,
                    currentScore: currentResult.healthScore,
                    icon: "heart.fill",
                    color: scoreColor(alternative.displayHealthScore)
                )

                scoreCardWithDelta(
                    title: "Environment",
                    score: alternative.displayEnvironmentalScore,
                    currentScore: currentResult.environmentalScore,
                    icon: "leaf.fill",
                    color: scoreColor(alternative.displayEnvironmentalScore)
                )

                scoreCardWithDelta(
                    title: "Ethics",
                    score: alternative.displayEthicsScore,
                    currentScore: nil,
                    icon: "star.fill",
                    color: scoreColor(alternative.displayEthicsScore)
                )
            }

            HStack(spacing: 4) {
                Image(systemName: alternative.isEnriched ? "checkmark.circle.fill" : "sparkles")
                    .font(.system(size: 9))
                Text(alternative.isEnriched ? "Verified Data" : "AI Estimate")
                    .font(.system(size: 9, weight: .medium))
            }
            .foregroundColor(alternative.isEnriched ? Theme.success : Theme.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill((alternative.isEnriched ? Theme.success : Theme.textSecondary).opacity(0.1))
            )
        }
    }

    private func scoreCard(title: String, score: Double, icon: String, color: Color) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                    .foregroundColor(color)
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Theme.textSecondary)
            }

            Text("\(Int(score))")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(Theme.textPrimary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(color.opacity(0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(color.opacity(0.3), lineWidth: 1)
                )
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) score: \(Int(score)) out of 100")
    }

    // Score card WITH delta comparison
    private func scoreCardWithDelta(title: String, score: Double, currentScore: Double?, icon: String, color: Color) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                    .foregroundColor(color)
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Theme.textSecondary)
            }

            Text("\(Int(score))")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(Theme.textPrimary)

            // Show delta if we have current score
            if let current = currentScore {
                let delta = score - current
                if abs(delta) > 1 { // Only show if meaningful difference
                    Text("\(delta > 0 ? "+" : "")\(Int(delta))")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(delta > 0 ? Theme.success : Theme.error)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(color.opacity(0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(color.opacity(0.3), lineWidth: 1)
                )
        )
    }

    private func scorePlaceholder(title: String, icon: String) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                    .foregroundColor(Theme.textMuted)
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Theme.textSecondary)
            }

            Text("—")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(Theme.textMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Theme.textMuted.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Theme.textMuted.opacity(0.1), lineWidth: 1)
                )
        )
    }

    private func scoreColor(_ score: Double) -> Color {
        if score >= 75 {
            return Theme.success
        } else if score >= 50 {
            return Theme.warning
        } else {
            return Theme.error
        }
    }

    private func impactStatPill(icon: String, value: String, improvement: String?, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundColor(color)
                Text(value)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Theme.textPrimary)
            }

            if let improvement = improvement {
                Text(improvement)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(color)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(color.opacity(0.12))
        )
    }

    // Keep original alternativeCard for backwards compatibility
    private func alternativeCard(_ alternative: AnalysisResult.Alternative, index: Int) -> some View {
        premiumAlternativeCard(alternative, index: index)
    }

    // Scale button style for smooth interactions
    struct ScaleButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
                .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
        }
    }

    @ViewBuilder
    private func determineBadge(for alternative: AnalysisResult.Alternative) -> some View {
        // Determine if this is the best choice
        let isBestHealth = (alternative.estimatedCO2 ?? Double.infinity) < currentResult.co2Emissions * 0.7
        let isBestEco = (alternative.estimatedWater ?? Double.infinity) < currentResult.waterUsage * 0.7

        if isBestHealth && isBestEco {
            badgePill(text: "Best Choice", icon: "star.fill", color: Theme.success)
        } else if isBestHealth {
            badgePill(text: "Eco Winner", icon: "leaf.fill", color: Theme.success)
        } else {
            EmptyView()
        }
    }

    private func badgePill(text: String, icon: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10))
            Text(text)
                .font(.system(size: 11, weight: .bold))
        }
        .foregroundColor(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.15))
        .cornerRadius(8)
    }

    private func comparisonStat(icon: String, value: String, improvement: String?, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(color)
                Text(value)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Theme.textPrimary)
            }

            if let improvement = improvement {
                Text(improvement)
                    .font(.system(size: 10))
                    .foregroundColor(Theme.success)
            }
        }
    }

    private func condensedReason(_ reason: String) -> String {
        // Take first sentence or first 100 characters
        let sentences = reason.components(separatedBy: ". ")
        if let first = sentences.first, first.count < 120 {
            return first + "."
        }
        return String(reason.prefix(100)) + "..."
    }

    private func co2Improvement(_ alternative: AnalysisResult.Alternative) -> String? {
        guard let altCO2 = alternative.estimatedCO2, currentResult.co2Emissions > 0 else { return nil }
        let improvement = ((currentResult.co2Emissions - altCO2) / currentResult.co2Emissions) * 100
        if improvement > 5 {
            return "-\(Int(improvement))% CO₂"
        }
        return nil
    }

    private func waterImprovement(_ alternative: AnalysisResult.Alternative) -> String? {
        guard let altWater = alternative.estimatedWater, currentResult.waterUsage > 0 else { return nil }
        let improvement = ((currentResult.waterUsage - altWater) / currentResult.waterUsage) * 100
        if improvement > 5 {
            return "-\(Int(improvement))% H₂O"
        }
        return nil
    }

    // MARK: - Additives Quick Section
    
    private var additivesQuickSection: some View {
        GlassCard(variant: .warning) {
            VStack(alignment: .leading, spacing: Spacing.md) {
                // Header
                HStack {
                    ZStack {
                        Circle()
                            .fill(Theme.warning.opacity(0.15))
                            .frame(width: 36, height: 36)
                        Image(systemName: "flask.fill")
                            .font(.system(size: 16))
                            .foregroundColor(Theme.warning)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Additives Detected")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(Theme.textPrimary)
                        Text("\(currentResult.additives.count) additive\(currentResult.additives.count == 1 ? "" : "s") found")
                            .font(.system(size: 12))
                            .foregroundColor(Theme.textSecondary)
                    }

                    Spacer()

                    StatusBadge("\(currentResult.additives.count)", variant: .warning, size: .small)
                }

                // Show first 3 additives
                VStack(spacing: 8) {
                    ForEach(currentResult.additives.prefix(3)) { additive in
                        HStack(spacing: 12) {
                            // Risk indicator icon
                            Image(systemName: "flask.fill")
                                .font(.system(size: 10))
                                .foregroundColor(additiveRiskColor(additive.riskLevel))

                            VStack(alignment: .leading, spacing: 2) {
                                Text(additive.code)
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(Theme.textPrimary)
                                Text(additive.name)
                                    .font(.system(size: 12))
                                    .foregroundColor(Theme.textSecondary)
                                    .lineLimit(1)
                            }

                            Spacer()

                            // Risk badge using StatusBadge
                            StatusBadge(
                                additive.riskLevel.capitalized,
                                variant: additive.riskLevel.lowercased() == "high" ? .error : (additive.riskLevel.lowercased() == "moderate" ? .warning : .success),
                                size: .small
                            )
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Theme.surfaceSecondary)
                        .cornerRadius(10)
                    }

                    // "View All" if more than 3
                    if currentResult.additives.count > 3 {
                        Button(action: {
                            showFullDetailsSheet = true
                        }) {
                            HStack {
                                Text("View all \(currentResult.additives.count) additives")
                                    .font(.system(size: 13, weight: .medium))
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11))
                            }
                            .foregroundColor(Theme.primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Theme.surfaceSecondary)
                            .cornerRadius(10)
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Additives detected: \(currentResult.additives.count) additive\(currentResult.additives.count == 1 ? "" : "s") found")
    }

    private func additiveRiskColor(_ riskLevel: String) -> Color {
        switch riskLevel.lowercased() {
        case "high": return Theme.error
        case "moderate": return Theme.warning
        case "low": return Theme.success
        default: return Theme.textMuted
        }
    }

    // MARK: - Environmental Impact Card

    private var environmentalImpactCard: some View {
        GlassCard.primary {
            ZStack {
                // Subtle leaf particles in the background
                LeafParticleEffect(count: 4)
                    .frame(height: 150)
                    .opacity(0.5)

            VStack(alignment: .leading, spacing: Spacing.md) {
                Label("Environmental Impact", systemImage: "leaf.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(Theme.textPrimary)

                HStack(spacing: Spacing.md) {
                    // CO2 with tree icons
                    if currentResult.co2Emissions > 0 {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 4) {
                                // Tree bracket icons: <1kg = 3 green, 1-3kg = 2 green + 1 gray, >3kg = 1 green + 2 gray
                                let greenCount = currentResult.co2Emissions < 1.0 ? 3 : (currentResult.co2Emissions < 3.0 ? 2 : 1)
                                ForEach(0..<3, id: \.self) { i in
                                    Image(systemName: "leaf.fill")
                                        .font(.system(size: 14))
                                        .foregroundColor(i < greenCount ? Theme.success : Theme.textMuted.opacity(0.3))
                                }
                            }
                            HStack(alignment: .firstTextBaseline, spacing: 3) {
                                AnimatedNumber(value: currentResult.co2Emissions, formatter: {
                                    let f = NumberFormatter()
                                    f.numberStyle = .decimal
                                    f.maximumFractionDigits = 1
                                    return f
                                }())
                                    .font(.system(size: 22, weight: .bold))
                                    .foregroundColor(Theme.textPrimary)
                                Text("kg CO₂")
                                    .font(.system(size: 11))
                                    .foregroundColor(Theme.textSecondary)
                            }
                            Text("per package")
                                .font(.system(size: 10))
                                .foregroundColor(Theme.textMuted)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Theme.surfaceSecondary)
                        .cornerRadius(10)
                    }

                    // Water with drop icons
                    if currentResult.waterUsage > 0 {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 4) {
                                // Drop bracket icons: <100L = 3 blue, 100-300L = 2 blue + 1 gray, >300L = 1 blue + 2 gray
                                let blueCount = currentResult.waterUsage < 100 ? 3 : (currentResult.waterUsage < 300 ? 2 : 1)
                                ForEach(0..<3, id: \.self) { i in
                                    Image(systemName: "drop.fill")
                                        .font(.system(size: 14))
                                        .foregroundColor(i < blueCount ? Theme.info : Theme.textMuted.opacity(0.3))
                                }
                            }
                            HStack(alignment: .firstTextBaseline, spacing: 3) {
                                AnimatedNumber(value: currentResult.waterUsage)
                                    .font(.system(size: 22, weight: .bold))
                                    .foregroundColor(Theme.textPrimary)
                                Text("L H₂O")
                                    .font(.system(size: 11))
                                    .foregroundColor(Theme.textSecondary)
                            }
                            Text("per package")
                                .font(.system(size: 10))
                                .foregroundColor(Theme.textMuted)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Theme.surfaceSecondary)
                        .cornerRadius(10)
                    }
                }
            }
            } // Close ZStack
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Environmental impact: \(currentResult.co2Emissions > 0 ? String(format: "%.1f kilograms CO2", currentResult.co2Emissions) : "") \(currentResult.waterUsage > 0 ? String(format: "%.0f liters water", currentResult.waterUsage) : "") per package")
    }

    private func co2Color(_ value: Double) -> Color {
        if value < 1.0 { return Theme.success }
        if value < 3.0 { return Theme.warning }
        return Theme.error
    }

    private func waterColor(_ value: Double) -> Color {
        if value < 100 { return Theme.success }
        if value < 300 { return Theme.warning }
        return Theme.error
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        VStack(spacing: Spacing.sm) {
            Button(action: {
                showPurchaseDecisionModal = true
                HapticManager.shared.trigger(.impactMedium)
            }) {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18))
                    Text("Save Purchase Decision")
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    LinearGradient(
                        gradient: Gradient(colors: [Theme.primary, Theme.primary.opacity(0.8)]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(12)
            }
            .buttonPressAnimation()
            .accessibilityLabel("Save purchase decision")
            .accessibilityHint("Record whether you purchased, avoided, or are considering this product")

            // View all details link
            Button(action: {
                HapticManager.shared.trigger(.impactLight)
                showFullDetailsSheet = true
            }) {
                HStack(spacing: 6) {
                    Text("View All Details")
                        .font(.system(size: 14, weight: .medium))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12))
                }
                .foregroundColor(Theme.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .sheet(isPresented: $showFullDetailsSheet) {
                FullDetailsSheet(result: currentResult)
                    .premiumSheet()
            }
        }
    }

    // MARK: - Purchase Decision Modal

    private var purchaseDecisionModal: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation {
                        showPurchaseDecisionModal = false
                    }
                }

            GlassCard.primary {
                VStack(spacing: Spacing.lg) {
                    Text("Purchase Decision")
                        .textStyleH2()

                    Text("Did you purchase this product?")
                        .textStyleBody()

                    VStack(spacing: Spacing.sm) {
                        decisionButton(title: "Yes, Purchased", icon: "checkmark.circle.fill", color: Theme.success, decision: PurchaseDecision.purchased)
                        decisionButton(title: "No, Avoided", icon: "xmark.circle.fill", color: Theme.error, decision: PurchaseDecision.avoided)
                        decisionButton(title: "Maybe Later", icon: "clock.fill", color: Theme.warning, decision: PurchaseDecision.scanned)
                    }
                }
            }
            .padding(.horizontal, Spacing.xl)
            .scaleIn()
        }
        .transition(.scale.combined(with: .opacity))
    }

    private func decisionButton(title: String, icon: String, color: Color, decision: PurchaseDecision) -> some View {
        Button(action: {
            savePurchaseDecision(decision)
            withAnimation {
                showPurchaseDecisionModal = false
            }
            HapticManager.shared.trigger(.success)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                onDismiss()
            }
        }) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 18))
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
            }
            .foregroundColor(Theme.textPrimary)
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .background(color.opacity(0.2))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(color, lineWidth: 2)
            )
            .cornerRadius(10)
        }
    }

    private func savePurchaseDecision(_ decision: PurchaseDecision) {
        Task {
            await HistoryService.shared.updatePurchaseDecision(
                for: originalHistoryId,
                decision: decision
            )

            let userKept = (decision == .purchased)
            await TasteProfileService.shared.recordTasteData(from: currentResult, userKept: userKept)
        }
    }
}

// MARK: - Safety State
/// Determines the safety state: .safe (green), .caution (yellow), .avoid (red)
enum SafetyState {
    case safe, caution, avoid

    var icon: String {
        switch self {
        case .safe: return "checkmark.shield.fill"
        case .caution: return "exclamationmark.triangle.fill"
        case .avoid: return "exclamationmark.shield.fill"
        }
    }

    var title: String {
        switch self {
        case .safe: return "Safe for You"
        case .caution: return "Use Caution"
        case .avoid: return "Not Recommended"
        }
    }

    var color: Color {
        switch self {
        case .safe: return Theme.success
        case .caution: return Theme.warning
        case .avoid: return Theme.error
        }
    }

    var variant: GlassCardVariant {
        switch self {
        case .safe: return .success
        case .caution: return .warning
        case .avoid: return .error
        }
    }
}

// MARK: - Full Details Sheet
struct FullDetailsSheet: View {
    let result: AnalysisResult
    @Environment(\.dismiss) var dismiss
    @State private var expandedSections: Set<String> = ["scores", "environmental"] // Default open sections
    @State private var expandedEducationItems: Set<String> = []

    private var safetyState: SafetyState {
        if !result.violations.isEmpty {
            return .avoid
        } else if !result.warnings.isEmpty || !result.cautionWarnings.isEmpty {
            return .caution
        } else if !result.isSafe {
            return .caution
        } else {
            return .safe
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    // Hero Product Card
                    heroProductCard
                        .scaleIn(delay: 0.05)

                    // Scores Section (Visual Cards)
                    scoresSection

                    // Safety Issues (if any)
                    if !result.violations.isEmpty || !result.warnings.isEmpty || !result.cautionWarnings.isEmpty {
                        safetyIssuesSection
                    }

                    // Analysis Confidence
                    if result.confidence > 0 || result.safetyConfidenceExplanation != nil {
                        analysisConfidenceSection
                    }

                    // Environmental Impact (Visual)
                    environmentalSection

                    // Health Details
                    if !result.healthConcerns.isEmpty || !result.healthBenefits.isEmpty || !result.additives.isEmpty {
                        healthDetailsSection
                    }

                    // Ingredients (Collapsible)
                    if !result.ingredients.isEmpty {
                        ingredientsSection
                    }

                    // Ingredient Education (Collapsible)
                    if let education = result.ingredientEducation, !education.isEmpty {
                        ingredientEducationSection(education: education)
                    }

                    // Recommendations (Collapsible)
                    if !result.recommendations.isEmpty {
                        recommendationsSection
                    }
                }
                .padding(.horizontal, Spacing.screenHorizontal)
                .padding(.vertical, Spacing.lg)
            }
            .background(Theme.backgroundPrimary)
            .navigationTitle("Product Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(Theme.primary)
                }
            }
        }
    }

    // MARK: - Hero Product Card
    private var heroProductCard: some View {
        GlassCard(variant: safetyState.variant) {
            VStack(spacing: Spacing.md) {
                HStack {
                    Image(systemName: safetyState.icon)
                        .font(.system(size: 40))
                        .foregroundColor(safetyState.color)
                        .glowPulse(color: safetyState.color, intensity: 0.5, speed: 2.0)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(result.productName)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(Theme.textPrimary)
                            .lineLimit(2)

                        if let brand = result.brand, !brand.isEmpty {
                            Text(brand)
                                .font(.system(size: 14))
                                .foregroundColor(Theme.textSecondary)
                        }

                        // Processing level badge
                        if let processingLevel = result.processingLevel, !processingLevel.isEmpty {
                            StatusBadge(
                                processingLevel,
                                icon: "gearshape.2.fill",
                                variant: .custom(
                                    backgroundColor: processingLevelColor(processingLevel).opacity(0.2),
                                    foregroundColor: processingLevelColor(processingLevel),
                                    borderColor: processingLevelColor(processingLevel).opacity(0.4)
                                ),
                                size: .small
                            )
                        }
                    }

                    Spacer()
                }

                // Certifications badges
                if let certifications = result.certifications, !certifications.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Spacing.xs) {
                            ForEach(certifications, id: \.self) { certification in
                                certificationBadge(certification)
                            }
                        }
                    }
                }

                // Food grading badges
                if result.nutriscoreGrade != nil || result.ecoscoreGrade != nil || result.novaGroup != nil {
                    foodGradingBadgesRow
                }

                // GMO status badge
                if let gmo = result.gmoStatus, !gmo.isEmpty {
                    gmoStatusBadge(gmo)
                }

                // Overall verdict badge
                HStack {
                    Spacer()
                    StatusBadge(
                        safetyState.title,
                        icon: safetyState.icon,
                        variant: .custom(
                            backgroundColor: safetyState.color.opacity(0.2),
                            foregroundColor: safetyState.color,
                            borderColor: safetyState.color.opacity(0.4)
                        ),
                        size: .large
                    )
                    Spacer()
                }
            }
        }
    }

    private func certificationBadge(_ certification: String) -> some View {
        StatusBadge(
            certification,
            icon: certificationIcon(certification),
            variant: .success,
            size: .small
        )
    }

    private func certificationIcon(_ certification: String) -> String {
        let lower = certification.lowercased()
        if lower.contains("organic") { return "leaf.fill" }
        if lower.contains("fair trade") { return "heart.fill" }
        if lower.contains("vegan") { return "checkmark.seal.fill" }
        if lower.contains("gluten") { return "cross.circle.fill" }
        if lower.contains("kosher") || lower.contains("halal") { return "checkmark.circle.fill" }
        return "rosette"
    }

    private func processingLevelColor(_ level: String) -> Color {
        let lower = level.lowercased()
        if lower.contains("minimal") || lower.contains("raw") || lower.contains("unprocessed") {
            return Theme.success
        }
        if lower.contains("moderate") {
            return Theme.warning
        }
        return Theme.error // Highly processed
    }

    // MARK: - Food Grading Badges
    private var foodGradingBadgesRow: some View {
        HStack(spacing: Spacing.sm) {
            if let nutri = result.nutriscoreGrade {
                foodGradeBadge(grade: nutri.uppercased(), label: "Nutri-Score", color: gradeColor(nutri))
            }
            if let eco = result.ecoscoreGrade {
                foodGradeBadge(grade: eco.uppercased(), label: "Eco-Score", color: gradeColor(eco))
            }
            if let nova = result.novaGroup {
                foodGradeBadge(grade: "\(nova)", label: "NOVA", color: novaColor(nova))
            }
        }
    }

    private func foodGradeBadge(grade: String, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(grade)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 40, height: 40)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(color)
                )
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(Theme.textSecondary)
        }
    }

    private func gradeColor(_ grade: String) -> Color {
        switch grade.lowercased() {
        case "a": return Theme.success
        case "b": return Color(hex: "84CC16")
        case "c": return Theme.warning
        case "d": return Color(hex: "F97316")
        case "e": return Theme.error
        default: return Theme.textMuted
        }
    }

    private func novaColor(_ group: Int) -> Color {
        switch group {
        case 1: return Theme.success
        case 2: return Color(hex: "84CC16")
        case 3: return Theme.warning
        case 4: return Theme.error
        default: return Theme.textMuted
        }
    }

    // MARK: - GMO Status Badge
    private func gmoStatusBadge(_ status: String) -> some View {
        StatusBadge(
            gmoStatusLabel(status),
            icon: gmoStatusIcon(status),
            variant: gmoStatusVariant(status)
        )
    }

    private func gmoStatusLabel(_ status: String) -> String {
        switch status.lowercased() {
        case "confirmed_gmo": return "Contains GMOs"
        case "non_gmo_certified": return "Non-GMO Certified"
        case "high_risk_unknown": return "May Contain GMO"
        case "no_risk": return "No GMO Risk"
        default: return status
        }
    }

    private func gmoStatusIcon(_ status: String) -> String {
        switch status.lowercased() {
        case "confirmed_gmo": return "exclamationmark.triangle.fill"
        case "non_gmo_certified": return "checkmark.seal.fill"
        case "high_risk_unknown": return "exclamationmark.triangle.fill"
        case "no_risk": return "checkmark.circle.fill"
        default: return "info.circle.fill"
        }
    }

    private func gmoStatusVariant(_ status: String) -> StatusBadge.BadgeVariant {
        switch status.lowercased() {
        case "confirmed_gmo": return .error
        case "non_gmo_certified": return .success
        case "high_risk_unknown": return .warning
        case "no_risk": return .success
        default: return .neutral
        }
    }

    // MARK: - Analysis Confidence Section
    private var analysisConfidenceSection: some View {
        VStack(spacing: Spacing.md) {
            collapsibleSectionHeader(
                title: "Analysis Confidence",
                icon: "chart.bar.xaxis",
                color: confidenceColor(result.confidence),
                sectionKey: "confidence"
            )

            if expandedSections.contains("confidence") {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    // Confidence percentage display
                    HStack(spacing: Spacing.md) {
                        Text("\(Int(result.confidence))%")
                            .font(.system(size: 36, weight: .bold))
                            .foregroundColor(confidenceColor(result.confidence))

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Confidence")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(Theme.textSecondary)

                            // Progress bar
                            GeometryReader { geometry in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color.white.opacity(0.08))
                                        .frame(height: 8)
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(confidenceColor(result.confidence))
                                        .frame(width: geometry.size.width * min(result.confidence / 100.0, 1.0), height: 8)
                                }
                            }
                            .frame(height: 8)
                        }
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.ultraThinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(confidenceColor(result.confidence).opacity(0.2), lineWidth: 1)
                            )
                    )

                    // Safety Confidence Explanation (if available)
                    if let explanation = result.safetyConfidenceExplanation {
                        StatusBadge(explanation.confidenceLevel, icon: "shield.checkered", variant: confidenceLevelVariant(explanation.confidenceLevel))

                        // What this means
                        HStack(alignment: .top, spacing: Spacing.sm) {
                            Image(systemName: "info.circle.fill")
                                .font(.system(size: 14))
                                .foregroundColor(Theme.info)
                            Text(explanation.whatThisMeans)
                                .font(.system(size: 13))
                                .foregroundColor(Theme.textSecondary)
                        }
                        .padding(Spacing.sm)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(.ultraThinMaterial)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(Theme.info.opacity(0.15), lineWidth: 1)
                                )
                        )

                        // Detailed reasons
                        if !explanation.detailedReasons.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(explanation.detailedReasons, id: \.self) { reason in
                                    HStack(alignment: .top, spacing: 8) {
                                        Circle()
                                            .fill(Theme.textMuted)
                                            .frame(width: 5, height: 5)
                                            .padding(.top, 6)
                                        Text(reason)
                                            .font(.system(size: 12))
                                            .foregroundColor(Theme.textSecondary)
                                    }
                                }
                            }
                            .padding(Spacing.sm)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(.ultraThinMaterial)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                                    )
                            )
                        }

                        // Recommended action
                        HStack(alignment: .top, spacing: Spacing.sm) {
                            Image(systemName: "lightbulb.fill")
                                .font(.system(size: 14))
                                .foregroundColor(Theme.warning)
                            Text(explanation.recommendedAction)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(Theme.textPrimary)
                        }
                        .padding(Spacing.sm)
                        .background(Theme.warning.opacity(0.08))
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Theme.warning.opacity(0.2), lineWidth: 1)
                        )
                    } else if !result.confidenceFactors.isEmpty {
                        // Fallback: show confidence factors
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Factors")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(Theme.textSecondary)
                            ForEach(result.confidenceFactors, id: \.self) { factor in
                                HStack(alignment: .top, spacing: 8) {
                                    Circle()
                                        .fill(Theme.textMuted)
                                        .frame(width: 5, height: 5)
                                        .padding(.top, 6)
                                    Text(factor)
                                        .font(.system(size: 12))
                                        .foregroundColor(Theme.textSecondary)
                                }
                            }
                        }
                        .padding(Spacing.sm)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(.ultraThinMaterial)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                                )
                        )
                    }
                }
                .transition(.opacity)
            }
        }
    }

    private func confidenceColor(_ confidence: Double) -> Color {
        if confidence >= 80 { return Theme.success }
        if confidence >= 50 { return Theme.warning }
        return Theme.error
    }

    private func confidenceLevelVariant(_ level: String) -> StatusBadge.BadgeVariant {
        switch level.lowercased() {
        case "very high", "high": return .success
        case "medium": return .warning
        case "low", "very low": return .error
        default: return .neutral
        }
    }

    // MARK: - Scores Section (Visual Cards)
    private var scoresSection: some View {
        VStack(spacing: Spacing.md) {
            sectionHeader(title: "Scores", icon: "chart.bar.fill", color: Theme.primary)

            HStack(spacing: Spacing.md) {
                scoreCard(
                    title: "Overall",
                    score: result.overallScore,
                    icon: "star.fill",
                    color: scoreColor(result.overallScore)
                )

                scoreCard(
                    title: "Health",
                    score: result.healthScore,
                    icon: "heart.fill",
                    color: scoreColor(result.healthScore)
                )

                scoreCard(
                    title: "Environment",
                    score: result.environmentalScore,
                    icon: "leaf.fill",
                    color: scoreColor(result.environmentalScore)
                )
            }
        }
    }

    private func scoreCard(title: String, score: Double, icon: String, color: Color) -> some View {
        VStack(spacing: Spacing.sm) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(color)
            }

            Text("\(Int(score))")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(Theme.textPrimary)

            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(color.opacity(0.2), lineWidth: 1)
                )
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) score: \(Int(score)) out of 100")
    }

    private func scoreColor(_ score: Double) -> Color {
        if score >= 70 { return Theme.success }
        if score >= 50 { return Theme.warning }
        return Theme.error
    }

    // MARK: - Safety Issues Section
    private var safetyIssuesSection: some View {
        VStack(spacing: Spacing.md) {
            sectionHeader(title: "Safety Issues", icon: "exclamationmark.shield.fill", color: Theme.error)

            VStack(spacing: Spacing.sm) {
                // Violations (High priority)
                if !result.violations.isEmpty {
                    ForEach(result.violations, id: \.self) { violation in
                        issueRow(
                            text: cleanIssueText(violation),
                            icon: "xmark.circle.fill",
                            color: Theme.error,
                            bgColor: Theme.error.opacity(0.15)
                        )
                    }
                }

                // Warnings (Medium priority)
                if !result.warnings.isEmpty {
                    ForEach(result.warnings, id: \.self) { warning in
                        issueRow(
                            text: cleanIssueText(warning),
                            icon: "exclamationmark.triangle.fill",
                            color: Theme.warning,
                            bgColor: Theme.warning.opacity(0.15)
                        )
                    }
                }

                // Cautions (Low priority)
                if !result.cautionWarnings.isEmpty {
                    ForEach(result.cautionWarnings, id: \.self) { caution in
                        issueRow(
                            text: cleanIssueText(caution),
                            icon: "info.circle.fill",
                            color: Theme.warning,
                            bgColor: Theme.warning.opacity(0.15)
                        )
                    }
                }
            }
        }
    }

    private func issueRow(text: String, icon: String, color: Color, bgColor: Color) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(color)

            Text(text)
                .font(.system(size: 14))
                .foregroundColor(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(bgColor)
        .cornerRadius(12)
    }

    private func cleanIssueText(_ text: String) -> String {
        // Remove emoji prefixes like ⛔, ⚠️, 🧬, ℹ️, ❌, ✓, etc
        var cleaned = text
        while let first = cleaned.unicodeScalars.first,
              !first.properties.isAlphabetic && !first.properties.isASCIIHexDigit && first != "(" {
            cleaned = String(cleaned.unicodeScalars.dropFirst())
        }
        return cleaned.trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Environmental Section
    private var environmentalSection: some View {
        VStack(spacing: Spacing.md) {
            sectionHeader(title: "Environmental Impact", icon: "globe.americas.fill", color: Theme.info)

            VStack(spacing: Spacing.sm) {
                // CO2 with visual bar
                environmentalMetric(
                    icon: "cloud.fill",
                    label: "CO₂ Emissions",
                    value: String(format: "%.1f kg", result.co2Emissions),
                    normalizedValue: normalizedCO2(result.co2Emissions),
                    color: co2Color(result.co2Emissions)
                )

                // Water with visual bar
                environmentalMetric(
                    icon: "drop.fill",
                    label: "Water Usage",
                    value: String(format: "%.0f L", result.waterUsage),
                    normalizedValue: normalizedWater(result.waterUsage),
                    color: waterColor(result.waterUsage)
                )

                // Animal Impact
                impactBadge(
                    icon: "pawprint.fill",
                    label: "Animal Impact",
                    value: result.animalImpact,
                    color: impactColor(result.animalImpact)
                )

                // Land Use
                impactBadge(
                    icon: "mountain.2.fill",
                    label: "Land Use",
                    value: result.landUse,
                    color: impactColor(result.landUse)
                )

                // Packaging Score
                if result.packagingScore > 0 {
                    impactBadge(
                        icon: "shippingbox.fill",
                        label: "Packaging",
                        value: "\(Int(result.packagingScore))/100",
                        color: scoreColor(result.packagingScore)
                    )
                }

                // Animal Welfare Score
                if result.animalWelfareScore > 0 {
                    impactBadge(
                        icon: "hands.and.sparkles.fill",
                        label: "Animal Welfare",
                        value: "\(Int(result.animalWelfareScore))/100",
                        color: scoreColor(result.animalWelfareScore)
                    )
                }
            }

            // Environmental Breakdown (Collapsible)
            if !result.environmentalBreakdown.isEmpty {
                VStack(spacing: Spacing.xs) {
                    collapsibleSectionHeader(
                        title: "Impact by Ingredient",
                        icon: "chart.pie.fill",
                        color: Theme.info,
                        sectionKey: "envBreakdown"
                    )

                    if expandedSections.contains("envBreakdown") {
                        VStack(spacing: Spacing.xs) {
                            ForEach(result.environmentalBreakdown) { breakdown in
                                HStack {
                                    Text(breakdown.ingredient)
                                        .font(.system(size: 13))
                                        .foregroundColor(Theme.textSecondary)

                                    Spacer()

                                    if let co2 = breakdown.co2 {
                                        Text("\(String(format: "%.2f", co2)) kg CO₂")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundColor(Theme.textPrimary)
                                    }

                                    if let percentage = breakdown.percentage {
                                        Text("(\(Int(percentage))%)")
                                            .font(.system(size: 12))
                                            .foregroundColor(Theme.textMuted)
                                    }
                                }
                                .padding(.horizontal, Spacing.sm)
                                .padding(.vertical, Spacing.xs)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(.ultraThinMaterial)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(Color.white.opacity(0.06), lineWidth: 1)
                                        )
                                )
                            }
                        }
                        .padding(.top, Spacing.xs)
                        .transition(.opacity)
                    }
                }
            }
        }
    }

    private func environmentalMetric(icon: String, label: String, value: String, normalizedValue: Double, color: Color) -> some View {
        VStack(spacing: Spacing.xs) {
            HStack {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.15))
                        .frame(width: 32, height: 32)
                    Image(systemName: icon)
                        .font(.system(size: 14))
                        .foregroundColor(color)
                }

                Text(label)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Theme.textSecondary)

                Spacer()

                Text(value)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(Theme.textPrimary)
            }

            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.08))
                        .frame(height: 8)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(color)
                        .frame(width: geometry.size.width * normalizedValue, height: 8)
                }
            }
            .frame(height: 8)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private func impactBadge(icon: String, label: String, value: String, color: Color) -> some View {
        HStack {
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 32, height: 32)
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(color)
            }

            Text(label)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Theme.textSecondary)

            Spacer()

            Text(value)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(color)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(color.opacity(0.15))
                .cornerRadius(8)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    // Normalization helpers
    private func normalizedCO2(_ value: Double) -> Double {
        // 0-0.5 = excellent, 0.5-2.0 = good, 2.0-5.0 = fair, 5.0+ = poor
        return min(value / 5.0, 1.0)
    }

    private func normalizedWater(_ value: Double) -> Double {
        // 0-200 = excellent, 200-500 = good, 500-1000 = fair, 1000+ = poor
        return min(value / 1000.0, 1.0)
    }

    private func co2Color(_ value: Double) -> Color {
        if value < 0.5 { return Theme.success }
        if value < 2.0 { return Theme.success }
        if value < 5.0 { return Theme.warning }
        return Theme.error
    }

    private func waterColor(_ value: Double) -> Color {
        if value < 200 { return Theme.success }
        if value < 500 { return Theme.success }
        if value < 1000 { return Theme.warning }
        return Theme.error
    }

    private func impactColor(_ impact: String) -> Color {
        let lower = impact.lowercased()
        if lower.contains("low") { return Theme.success }
        if lower.contains("high") { return Theme.error }
        return Theme.warning
    }

    // MARK: - Health Details Section
    private var healthDetailsSection: some View {
        VStack(spacing: Spacing.md) {
            sectionHeader(title: "Health Details", icon: "heart.text.square.fill", color: Theme.error)

            VStack(spacing: Spacing.sm) {
                // Concerns
                if !result.healthConcerns.isEmpty {
                    ForEach(result.healthConcerns, id: \.self) { concern in
                        healthItem(text: concern, isPositive: false)
                    }
                }

                // Benefits
                if !result.healthBenefits.isEmpty {
                    ForEach(result.healthBenefits, id: \.self) { benefit in
                        healthItem(text: benefit, isPositive: true)
                    }
                }

                // Additives (Collapsible sub-section)
                if !result.additives.isEmpty {
                    additivesSubSection
                }
            }
        }
    }

    // MARK: - Additives Sub-Section
    private var additivesSubSection: some View {
        VStack(spacing: Spacing.sm) {
            Button(action: {
                withAnimation(.spring(response: 0.3)) {
                    if expandedSections.contains("additives") {
                        expandedSections.remove("additives")
                    } else {
                        expandedSections.insert("additives")
                    }
                }
            }) {
                HStack(spacing: Spacing.sm) {
                    // Icon with background
                    ZStack {
                        Circle()
                            .fill(Theme.warning.opacity(0.15))
                            .frame(width: 36, height: 36)
                        Image(systemName: "flask.fill")
                            .font(.system(size: 16))
                            .foregroundColor(Theme.warning)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Additives & E-Numbers")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(Theme.textPrimary)

                        Text("\(result.additives.count) detected")
                            .font(.system(size: 12))
                            .foregroundColor(Theme.textSecondary)
                    }

                    Spacer()

                    Image(systemName: expandedSections.contains("additives") ? "chevron.up.circle.fill" : "chevron.down.circle")
                        .font(.system(size: 20))
                        .foregroundColor(Theme.primary)
                }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.md)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Theme.warning.opacity(0.2), lineWidth: 1)
                        )
                )
            }

            if expandedSections.contains("additives") {
                VStack(spacing: Spacing.xs) {
                    ForEach(result.additives) { additive in
                        additiveCard(additive)
                    }
                }
                .transition(.opacity)
            }
        }
    }

    private func additiveCard(_ additive: AnalysisResult.AdditiveInfo) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack {
                // Risk icon
                Image(systemName: additive.riskIcon)
                    .font(.system(size: 16))
                    .foregroundColor(additiveRiskColor(additive.riskLevel))

                // Code and name
                VStack(alignment: .leading, spacing: 2) {
                    Text(additive.code)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(Theme.textPrimary)

                    Text(additive.name)
                        .font(.system(size: 12))
                        .foregroundColor(Theme.textSecondary)
                }

                Spacer()

                // Risk level badge
                StatusBadge(
                    additive.riskLevel.capitalized,
                    icon: additive.riskIcon,
                    variant: .custom(
                        backgroundColor: additiveRiskColor(additive.riskLevel).opacity(0.2),
                        foregroundColor: additiveRiskColor(additive.riskLevel),
                        borderColor: additiveRiskColor(additive.riskLevel).opacity(0.4)
                    ),
                    size: .small
                )
            }

            // Category
            Text(additive.category)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Theme.textMuted)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.white.opacity(0.06))
                .cornerRadius(5)

            // Description
            Text(additive.description)
                .font(.system(size: 12))
                .foregroundColor(Theme.textSecondary)
                .lineSpacing(3)

            // Source
            HStack {
                Text("Source:")
                    .font(.system(size: 10))
                    .foregroundColor(Theme.textMuted)
                Text(additive.source)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Theme.textSecondary)
            }
        }
        .padding(Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(additiveRiskColor(additive.riskLevel).opacity(0.3), lineWidth: 1)
                )
        )
    }

    private func additiveRiskColor(_ riskLevel: String) -> Color {
        switch riskLevel.lowercased() {
        case "high": return Theme.error
        case "moderate": return Theme.warning
        case "low": return Theme.success
        default: return Theme.textMuted
        }
    }

    private func healthItem(text: String, isPositive: Bool) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: isPositive ? "checkmark.circle.fill" : "minus.circle.fill")
                .font(.system(size: 16))
                .foregroundColor(isPositive ? Theme.success : Theme.error)

            Text(text)
                .font(.system(size: 14))
                .foregroundColor(Theme.textSecondary)

            Spacer()
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill((isPositive ? Theme.success : Theme.error).opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke((isPositive ? Theme.success : Theme.error).opacity(0.15), lineWidth: 1)
                )
        )
    }

    // MARK: - Ingredients Section
    private var ingredientsSection: some View {
        VStack(spacing: Spacing.md) {
            collapsibleSectionHeader(
                title: "Ingredients",
                icon: "list.bullet.rectangle.fill",
                color: Theme.accent,
                sectionKey: "ingredients"
            )

            if expandedSections.contains("ingredients") {
                FlowLayout(spacing: 6) {
                    ForEach(result.ingredients, id: \.self) { ingredient in
                        StatusBadge(
                            ingredient,
                            variant: .neutral,
                            size: .small
                        )
                    }
                }
                .padding(Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        )
                )
                .transition(.opacity)
            }
        }
    }

    // MARK: - Ingredient Education Section
    private func ingredientEducationSection(education: [AnalysisResult.IngredientEducation]) -> some View {
        VStack(spacing: Spacing.md) {
            collapsibleSectionHeader(
                title: "Ingredient Education",
                icon: "book.fill",
                color: Theme.accent,
                sectionKey: "ingredientEducation"
            )

            if expandedSections.contains("ingredientEducation") {
                VStack(spacing: Spacing.xs) {
                    ForEach(education) { item in
                        let isExpanded = expandedEducationItems.contains(item.ingredient)
                        Button(action: {
                            withAnimation(.spring(response: 0.3)) {
                                if isExpanded {
                                    expandedEducationItems.remove(item.ingredient)
                                } else {
                                    expandedEducationItems.insert(item.ingredient)
                                }
                            }
                        }) {
                            VStack(alignment: .leading, spacing: isExpanded ? Spacing.sm : 0) {
                                // Header row
                                HStack(spacing: Spacing.sm) {
                                    Image(systemName: educationSafetyIcon(item.isSafe))
                                        .font(.system(size: 14))
                                        .foregroundColor(educationSafetyColor(item.isSafe))

                                    Text(item.ingredient)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(Theme.textPrimary)

                                    Spacer()

                                    Text(item.whatItIs)
                                        .font(.system(size: 11))
                                        .foregroundColor(Theme.textSecondary)
                                        .lineLimit(1)
                                        .frame(maxWidth: 140, alignment: .trailing)

                                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                        .font(.system(size: 11))
                                        .foregroundColor(Theme.textMuted)
                                }

                                // Expanded content
                                if isExpanded {
                                    VStack(alignment: .leading, spacing: Spacing.xs) {
                                        // What it is (full)
                                        Text(item.whatItIs)
                                            .font(.system(size: 13))
                                            .foregroundColor(Theme.textSecondary)

                                        // Why it matters
                                        if !item.whyItMatters.isEmpty {
                                            HStack(alignment: .top, spacing: 8) {
                                                Image(systemName: "exclamationmark.circle.fill")
                                                    .font(.system(size: 12))
                                                    .foregroundColor(Theme.warning)
                                                    .padding(.top, 1)
                                                Text(item.whyItMatters)
                                                    .font(.system(size: 12))
                                                    .foregroundColor(Theme.textSecondary)
                                            }
                                        }

                                        // Hidden sources
                                        if !item.hiddenSources.isEmpty {
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text("Hidden Sources:")
                                                    .font(.system(size: 11, weight: .semibold))
                                                    .foregroundColor(Theme.textMuted)
                                                ForEach(item.hiddenSources, id: \.self) { source in
                                                    HStack(spacing: 6) {
                                                        Circle()
                                                            .fill(Theme.textMuted)
                                                            .frame(width: 4, height: 4)
                                                        Text(source)
                                                            .font(.system(size: 11))
                                                            .foregroundColor(Theme.textSecondary)
                                                    }
                                                }
                                            }
                                        }
                                    }
                                    .padding(.top, 4)
                                }
                            }
                            .padding(Spacing.sm)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(.ultraThinMaterial)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(educationSafetyColor(item.isSafe).opacity(0.3), lineWidth: 1)
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .transition(.opacity)
            }
        }
    }

    private func educationSafetyIcon(_ isSafe: Bool?) -> String {
        switch isSafe {
        case true: return "checkmark.circle.fill"
        case false: return "xmark.circle.fill"
        case nil: return "info.circle.fill"
        default: return "info.circle.fill"
        }
    }

    private func educationSafetyColor(_ isSafe: Bool?) -> Color {
        switch isSafe {
        case true: return Theme.success
        case false: return Theme.error
        case nil: return Theme.warning
        default: return Theme.warning
        }
    }

    // MARK: - Recommendations Section
    private var recommendationsSection: some View {
        VStack(spacing: Spacing.md) {
            collapsibleSectionHeader(
                title: "Recommendations",
                icon: "lightbulb.fill",
                color: Theme.warning,
                sectionKey: "recommendations"
            )

            if expandedSections.contains("recommendations") {
                VStack(spacing: Spacing.xs) {
                    ForEach(Array(result.recommendations.prefix(5).enumerated()), id: \.offset) { index, recommendation in
                        HStack(alignment: .top, spacing: Spacing.sm) {
                            Text("\(index + 1)")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(Theme.primary)
                                .frame(width: 24, height: 24)
                                .background(Circle().fill(Theme.primary.opacity(0.15)))

                            Text(recommendation)
                                .font(.system(size: 14))
                                .foregroundColor(Theme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)

                            Spacer()
                        }
                        .padding(.horizontal, Spacing.md)
                        .padding(.vertical, Spacing.sm)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(.ultraThinMaterial)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                                )
                        )
                    }
                }
                .transition(.opacity)
            }
        }
    }

    // MARK: - Section Headers
    private func sectionHeader(title: String, icon: String, color: Color) -> some View {
        HStack(spacing: Spacing.sm) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 32, height: 32)
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(color)
            }

            Text(title)
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(Theme.textPrimary)

            Spacer()
        }
    }

    private func collapsibleSectionHeader(title: String, icon: String, color: Color, sectionKey: String) -> some View {
        Button(action: {
            withAnimation(.spring(response: 0.3)) {
                if expandedSections.contains(sectionKey) {
                    expandedSections.remove(sectionKey)
                } else {
                    expandedSections.insert(sectionKey)
                }
            }
        }) {
            HStack(spacing: Spacing.sm) {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.15))
                        .frame(width: 32, height: 32)
                    Image(systemName: icon)
                        .font(.system(size: 14))
                        .foregroundColor(color)
                }

                Text(title)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(Theme.textPrimary)

                Spacer()

                Image(systemName: expandedSections.contains(sectionKey) ? "chevron.up.circle.fill" : "chevron.down.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(Theme.primary)
            }
        }
    }
}
