//
//  HistoryView.swift
//  Ethica
//
//  Enhanced history view with timeline visualization and behavioral insights
//

import SwiftUI

struct HistoryView: View {
    @State private var scans: [ScanHistory] = []
    @State private var searchText = ""
    @State private var viewMode: ViewMode = .timeline
    @State private var filterOption: FilterOption = .all
    @State private var showingClearConfirmation = false
    @State private var selectedScan: ScanHistory?

    enum ViewMode: String, CaseIterable {
        case timeline = "Timeline"
        case list = "List"

        var icon: String {
            switch self {
            case .timeline: return "clock.fill"
            case .list: return "list.bullet"
            }
        }
    }

    enum FilterOption: String, CaseIterable {
        case all = "All"
        case safe = "Safe"
        case violations = "Violations"
        case thisWeek = "This Week"
    }

    var filteredScans: [ScanHistory] {
        var filtered = scans

        switch filterOption {
        case .all:
            break
        case .safe:
            filtered = filtered.filter { $0.isSafe }
        case .violations:
            filtered = filtered.filter { !$0.isSafe }
        case .thisWeek:
            let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
            filtered = filtered.filter { $0.timestamp >= weekAgo }
        }

        if !searchText.isEmpty {
            filtered = filtered.filter { $0.productName.localizedCaseInsensitiveContains(searchText) }
        }

        return filtered
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.backgroundPrimary
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Filter picker
                    HStack(spacing: Spacing.md) {
                        Picker("Filter", selection: $filterOption) {
                            ForEach(FilterOption.allCases, id: \.self) { option in
                                Text(option.rawValue).tag(option)
                            }
                        }
                        .pickerStyle(.segmented)
                        .tint(Theme.primary)
                        .onChange(of: filterOption) { _, _ in
                            HapticManager.shared.trigger(.selectionChanged)
                        }
                        .accessibilityLabel("Filter scans")
                        .accessibilityHint("Select a category to filter your scan history")

                        // View mode toggle
                        Picker("View Mode", selection: $viewMode) {
                            ForEach(ViewMode.allCases, id: \.self) { mode in
                                Image(systemName: mode.icon)
                                    .tag(mode)
                                    .accessibilityLabel("\(mode.rawValue) view")
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 100)
                        .tint(Theme.accent)
                        .accessibilityLabel("View mode: \(viewMode.rawValue)")
                        .accessibilityHint("Switch between timeline and list view")
                    }
                    .padding(.horizontal, Spacing.screenHorizontal)
                    .padding(.vertical, Spacing.md)

                    if filteredScans.isEmpty {
                        emptyState
                    } else {
                        ScrollView {
                            LazyVStack(spacing: Spacing.lg) {
                                // Insights card (only show when not filtered)
                                if filterOption == .all && searchText.isEmpty {
                                    InsightsCard(scans: scans)
                                                            .accessibilityLabel("Scan insights summary")
                                }

                                // Timeline or list view
                                if viewMode == .timeline {
                                    timelineView
                                } else {
                                    listView
                                }
                            }
                            .padding(.vertical, Spacing.md)
                            .animation(AnimationSystem.springSmooth, value: filterOption)
                        }
                        .refreshable {
                            await loadHistoryAsync()
                        }
                    }
                }
            }
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $searchText, prompt: "Search products")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button(role: .destructive) {
                            showingClearConfirmation = true
                        } label: {
                            Label("Clear All History", systemImage: "trash")
                        }
                        .accessibilityLabel("Clear all scan history")
                        .accessibilityHint("Permanently removes all scan records")
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("History options")
                    .accessibilityHint("Opens menu with options to clear history")
                    .confirmationDialog(
                        "Clear All History",
                        isPresented: $showingClearConfirmation,
                        titleVisibility: .visible
                    ) {
                        Button("Clear All", role: .destructive, action: clearHistory)
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("This will permanently delete all your scan history. This action cannot be undone.")
                    }
                }
            }
        }
        .task { await loadHistoryAsync() }
        .onReceive(NotificationCenter.default.publisher(for: UIScene.willEnterForegroundNotification)) { _ in
            Task { await loadHistoryAsync() }
        }
        .overlay {
            // Hero detail overlay
            if let scan = selectedScan {
                heroDetailOverlay(scan)
            }
        }
    }

    // MARK: - Hero Detail Overlay

    @ViewBuilder
    private func heroDetailOverlay(_ scan: ScanHistory) -> some View {
        ZStack {
            // Background fills behind status bar
            Theme.backgroundPrimary
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Close button bar
                HStack {
                    Button {
                        HapticManager.shared.trigger(.impactLight)
                        withAnimation(AnimationSystem.springSmooth) {
                            selectedScan = nil
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(Theme.textMuted)
                    }
                    .accessibilityLabel("Close details")

                    Spacer()

                    Text("Scan Details")
                        .textStyleH3()

                    Spacer()

                    // Invisible spacer for centering
                    Color.clear.frame(width: 28, height: 28)
                }
                .padding(.horizontal, Spacing.screenHorizontal)
                .padding(.top, Spacing.md)
                .padding(.bottom, Spacing.sm)

                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        // A. Safety verdict header
                        GlassCard(variant: scan.isSafe ? .success : .error) {
                            HStack(spacing: Spacing.sm) {
                                Image(systemName: scan.isSafe ? "checkmark.shield.fill" : "xmark.shield.fill")
                                    .font(.system(size: 32))
                                    .foregroundColor(scan.isSafe ? Theme.success : Theme.error)

                                VStack(alignment: .leading, spacing: Spacing.xs) {
                                    Text(scan.productName)
                                        .textStyleH2()
                                        .lineLimit(2)
                                    Text("Scanned \(scan.timestamp.formatted(date: .abbreviated, time: .shortened))")
                                        .textStyleCaption()
                                }

                                Spacer()

                                StatusBadge(
                                    scan.isSafe ? "Safe" : "Avoid",
                                    icon: scan.isSafe ? "checkmark.circle.fill" : "xmark.circle.fill",
                                    variant: scan.isSafe ? .success : .error,
                                    size: .medium
                                )
                            }
                        }

                        // B. Scores row (compact, side by side)
                        HStack(spacing: 0) {
                            if scan.healthScore > 0 {
                                ScoreCircle(
                                    score: scan.healthScore,
                                    size: .small,
                                    showLabel: true,
                                    label: "Health"
                                )
                                .frame(maxWidth: .infinity)
                            }

                            VStack(spacing: Spacing.xs) {
                                Image(systemName: animalImpactIcon(scan.animalImpact))
                                    .font(.system(size: 24))
                                    .foregroundColor(animalImpactColor(scan.animalImpact))
                                Text(scan.animalImpact)
                                    .font(Typography.h4)
                                    .foregroundColor(animalImpactColor(scan.animalImpact))
                                Text("Animal Impact")
                                    .textStyleCaption()
                            }
                            .frame(maxWidth: .infinity)

                            VStack(spacing: Spacing.xs) {
                                Text("\(scan.violationsCount)")
                                    .font(Typography.h3)
                                    .foregroundColor(scan.violationsCount > 0 ? Theme.error : Theme.success)
                                Text("Violations")
                                    .textStyleCaption()
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .padding(.vertical, Spacing.sm)

                        // C. Purchase decision (if not just scanned)
                        if scan.purchaseDecision != .scanned {
                            GlassCard(variant: .secondary, padding: Spacing.sm) {
                                HStack(spacing: Spacing.sm) {
                                    Image(systemName: decisionIcon(scan.purchaseDecision))
                                        .foregroundColor(decisionColor(scan.purchaseDecision))

                                    Text("Decision:")
                                        .textStyleBody()

                                    StatusBadge(
                                        scan.purchaseDecision.rawValue.capitalized,
                                        variant: scan.purchaseDecision == .purchased ? .success : (scan.purchaseDecision == .avoided ? .error : .warning),
                                        size: .small
                                    )

                                    Spacer()

                                    if let decisionTime = scan.decisionTimestamp {
                                        Text(decisionTime.formatted(date: .omitted, time: .shortened))
                                            .textStyleCaption()
                                    }
                                }
                            }
                        }

                        // D. Violations (collapsed by default, capped at 3)
                        if !scan.violations.isEmpty {
                            ExpandableSection.error(
                                "Violations",
                                badge: "\(scan.violations.count)",
                                defaultExpanded: false
                            ) {
                                VStack(alignment: .leading, spacing: Spacing.sm) {
                                    ForEach(Array(scan.violations.prefix(3).enumerated()), id: \.offset) { _, violation in
                                        Text("• \(violation)")
                                            .textStyleBody()
                                    }
                                    if scan.violations.count > 3 {
                                        Text("+ \(scan.violations.count - 3) more")
                                            .textStyleCaption()
                                            .foregroundColor(Theme.textSecondary)
                                    }
                                }
                            }
                        }

                        // E. Environmental impact
                        if scan.co2Emissions > 0 || scan.waterUsage > 0 {
                            GlassCard.primary {
                                VStack(alignment: .leading, spacing: Spacing.sm) {
                                    Text("Environmental Impact")
                                        .textStyleH3()

                                    HStack(spacing: Spacing.lg) {
                                        if scan.co2Emissions > 0 {
                                            VStack(spacing: Spacing.xs) {
                                                Text("🌍")
                                                    .font(.system(size: 24))
                                                Text(String(format: "%.1f kg", scan.co2Emissions))
                                                    .font(Typography.h4)
                                                    .foregroundColor(Theme.primary)
                                                Text("CO₂")
                                                    .textStyleCaption()
                                            }
                                            .frame(maxWidth: .infinity)
                                        }

                                        if scan.waterUsage > 0 {
                                            VStack(spacing: Spacing.xs) {
                                                Text("💧")
                                                    .font(.system(size: 24))
                                                Text("\(Int(scan.waterUsage)) L")
                                                    .font(Typography.h4)
                                                    .foregroundColor(Theme.info)
                                                Text("Water")
                                                    .textStyleCaption()
                                            }
                                            .frame(maxWidth: .infinity)
                                        }

                                        VStack(spacing: Spacing.xs) {
                                            Image(systemName: animalImpactIcon(scan.animalImpact))
                                                .font(.system(size: 24))
                                                .foregroundColor(animalImpactColor(scan.animalImpact))
                                            Text(scan.animalImpact)
                                                .font(Typography.h4)
                                                .foregroundColor(animalImpactColor(scan.animalImpact))
                                            Text("Animals")
                                                .textStyleCaption()
                                        }
                                        .frame(maxWidth: .infinity)
                                    }
                                }
                            }
                        }

                        // F. Alternative chosen (if applicable)
                        if let altName = scan.alternativeName {
                            GlassCard.primary {
                                HStack(spacing: Spacing.sm) {
                                    Image(systemName: "arrow.triangle.swap")
                                        .font(.system(size: 20))
                                        .foregroundColor(Theme.accent)

                                    VStack(alignment: .leading, spacing: Spacing.xs) {
                                        Text("Chose Alternative")
                                            .textStyleCaption()
                                        Text(altName)
                                            .textStyleH4(color: Theme.accent)
                                    }

                                    Spacer()
                                }
                            }
                        }

                        // G. Action buttons
                        HStack(spacing: Spacing.md) {
                            Button {
                                HapticManager.shared.trigger(.impactMedium)
                                withAnimation(AnimationSystem.springSmooth) {
                                    selectedScan = nil
                                }
                                NotificationCenter.default.post(name: Notification.Name("switchToTab"), object: 0)
                            } label: {
                                HStack(spacing: Spacing.sm) {
                                    Image(systemName: "arrow.counterclockwise")
                                    Text("Rescan")
                                }
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(Theme.primary)
                                .frame(maxWidth: .infinity)
                                .frame(height: Spacing.Height.buttonSmall)
                                .background(Theme.primary.opacity(0.15))
                                .clipShape(RoundedRectangle(cornerRadius: Spacing.radiusSM))
                            }

                            Button {
                                HapticManager.shared.trigger(.warning)
                                deleteScan(scan)
                                withAnimation(AnimationSystem.springSmooth) {
                                    selectedScan = nil
                                }
                            } label: {
                                HStack(spacing: Spacing.sm) {
                                    Image(systemName: "trash")
                                    Text("Delete")
                                }
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(Theme.error)
                                .frame(maxWidth: .infinity)
                                .frame(height: Spacing.Height.buttonSmall)
                                .background(Theme.error.opacity(0.15))
                                .clipShape(RoundedRectangle(cornerRadius: Spacing.radiusSM))
                            }
                        }
                        .padding(.top, Spacing.sm)
                    }
                    .padding(.horizontal, Spacing.screenHorizontal)
                    .padding(.vertical, Spacing.md)
                }
            }
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .gesture(
            DragGesture()
                .onEnded { value in
                    if value.translation.height > 100 || value.predictedEndTranslation.height > 300 {
                        HapticManager.shared.trigger(.impactLight)
                        withAnimation(AnimationSystem.springSmooth) {
                            selectedScan = nil
                        }
                    }
                }
        )
    }

    // MARK: - Detail Overlay Helpers

    private func animalImpactIcon(_ impact: String) -> String {
        switch impact.lowercased() {
        case "low": return "pawprint.fill"
        case "medium": return "hare.fill"
        case "high": return "exclamationmark.triangle.fill"
        default: return "pawprint.fill"
        }
    }

    private func animalImpactColor(_ impact: String) -> Color {
        switch impact.lowercased() {
        case "low": return Theme.success
        case "medium": return Theme.warning
        case "high": return Theme.error
        default: return Theme.textSecondary
        }
    }

    private func decisionIcon(_ decision: PurchaseDecision) -> String {
        switch decision {
        case .purchased: return "cart.fill"
        case .avoided: return "hand.raised.fill"
        case .alternative: return "arrow.triangle.swap"
        case .scanned: return "barcode.viewfinder"
        }
    }

    private func decisionColor(_ decision: PurchaseDecision) -> Color {
        switch decision {
        case .purchased: return Theme.success
        case .avoided: return Theme.error
        case .alternative: return Theme.warning
        case .scanned: return Theme.textSecondary
        }
    }

    // MARK: - Timeline View

    @ViewBuilder
    private var timelineView: some View {
        let groups = filteredScans.groupedByTimeframe()

        ForEach(Array(groups.enumerated()), id: \.element.id) { groupIndex, group in
            VStack(spacing: Spacing.md) {
                // Date section header with summary
                dateSectionHeader(group, isFirst: groupIndex == 0)

                // Scans in this group
                ForEach(Array(group.scans.enumerated()), id: \.element.id) { scanIndex, scan in
                    HStack(alignment: .top, spacing: Spacing.md) {
                        // Timeline connector with safety-colored dot
                        timelineConnector(
                            isFirst: groupIndex == 0 && scanIndex == 0,
                            isLast: groupIndex == groups.count - 1 && scanIndex == group.scans.count - 1,
                            isSafe: scan.isSafe,
                            isRecent: scan.timestamp > Date().addingTimeInterval(-3600)
                        )

                        // Swipeable history card
                        SwipeableHistoryCard(scan: scan) {
                            timelineCard(scan)
                        } onDelete: {
                            deleteScan(scan)
                        } onShare: {
                            // share handled via context menu for now
                        } onRescan: {
                            NotificationCenter.default.post(name: Notification.Name("switchToTab"), object: 0)
                        }
                    }
                    .padding(.horizontal, Spacing.screenHorizontal)
                }
            }
        }
    }

    @ViewBuilder
    private func dateSectionHeader(_ group: ScanHistoryGroup, isFirst: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(group.title)
                    .textStyleH3()

                HStack(spacing: Spacing.md) {
                    HStack(spacing: 4) {
                        Text("\(group.scans.count)")
                            .fontWeight(.semibold)
                        Text("scans")
                    }

                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(Theme.success)
                        Text("\(group.safeCount)")
                    }

                    if group.violationCount > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(Theme.error)
                            Text("\(group.violationCount)")
                        }
                    }
                }
                .textStyleCaption()
                .foregroundColor(Theme.textSecondary)
            }

            Spacer()

            // Average health score
            if group.avgHealthScore > 0 {
                VStack(spacing: Spacing.xs) {
                    Text("\(Int(group.avgHealthScore))")
                        .font(Typography.h4)
                        .foregroundColor(Theme.healthScoreColor(group.avgHealthScore))
                    Text("avg health")
                        .font(.system(size: 10))
                        .foregroundColor(Theme.textMuted)
                }
            }
        }
        .padding(.horizontal, Spacing.screenHorizontal)
        .padding(.top, isFirst ? 0 : Spacing.lg)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(group.title), \(group.scans.count) scans, \(group.safeCount) safe\(group.violationCount > 0 ? ", \(group.violationCount) with violations" : "")\(group.avgHealthScore > 0 ? ", average health score \(Int(group.avgHealthScore))" : "")")
    }

    @ViewBuilder
    private func timelineConnector(isFirst: Bool, isLast: Bool, isSafe: Bool = true, isRecent: Bool = false) -> some View {
        let dotColor = isSafe ? Theme.success : Theme.error

        VStack(spacing: 0) {
            // Top line
            if !isFirst {
                Rectangle()
                    .fill(Theme.primary.opacity(0.3))
                    .frame(width: 2, height: 16)
            }

            // Safety-colored dot
            Circle()
                .fill(dotColor)
                .frame(width: 12, height: 12)
                .overlay(
                    Circle()
                        .stroke(dotColor.opacity(0.5), lineWidth: 3)
                )
                .modifier(ConditionalPulsingModifier(shouldPulse: isRecent))

            // Bottom line
            if !isLast {
                Rectangle()
                    .fill(Theme.primary.opacity(0.3))
                    .frame(width: 2)
                        .frame(minHeight: 60)
            }
        }
        .frame(width: 30)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func timelineCard(_ scan: ScanHistory) -> some View {
        Button {
            HapticManager.shared.trigger(.impactLight)
            withAnimation(AnimationSystem.springSmooth) {
                selectedScan = scan
            }
        } label: {
            GlassCard(
                variant: scan.isSafe ? .success : .error,
                padding: Spacing.md
            ) {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    HStack {
                        // Product name
                        Text(scan.productName)
                            .textStyleH4(color: Theme.textPrimary)
                            .lineLimit(2)

                        Spacer()

                        // Health score
                        if scan.healthScore > 0 {
                            Text("\(Int(scan.healthScore))")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(Theme.healthScoreColor(scan.healthScore))
                        }
                    }

                    // Time
                    Text(scan.timestamp.formatted(date: .omitted, time: .shortened))
                        .textStyleCaption()

                    // Decision + metrics row
                    HStack(spacing: Spacing.sm) {
                        // Decision badge
                        let decision = scan.purchaseDecision
                        StatusBadge(
                            decision.rawValue,
                            variant: decision == .purchased ? .success : (decision == .avoided ? .error : .warning),
                            size: .small
                        )

                        Spacer()

                        // Quick metrics
                        if scan.purchaseDecision == .avoided || scan.purchaseDecision == .alternative {
                            HStack(spacing: 4) {
                                Image(systemName: "leaf.fill")
                                    .font(.system(size: 10))
                                    .foregroundColor(Theme.success)
                                Text(String(format: "%.1fkg", scan.co2Emissions))
                                    .textStyleCaption()
                                    .foregroundColor(Theme.success)
                            }
                        }
                    }
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(scan.productName), health score \(Int(scan.healthScore)), \(scan.isSafe ? "safe" : "has violations"), \(scan.purchaseDecision.rawValue), scanned at \(scan.timestamp.formatted(date: .omitted, time: .shortened))")
        .accessibilityHint("Double tap to view details")
    }

    // MARK: - List View

    @ViewBuilder
    private var listView: some View {
        LazyVStack(spacing: Spacing.md) {
            ForEach(Array(filteredScans.enumerated()), id: \.element.id) { index, scan in
                historyCard(scan)
                    .contextMenu {
                        Button(role: .destructive) {
                            deleteScan(scan)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
            }
        }
        .padding(.horizontal, Spacing.screenHorizontal)
    }

    @ViewBuilder
    private func historyCard(_ scan: ScanHistory) -> some View {
        Button {
            HapticManager.shared.trigger(.impactLight)
            withAnimation(AnimationSystem.springSmooth) {
                selectedScan = scan
            }
        } label: {
            GlassCard(
                variant: scan.isSafe ? .success : .error,
                padding: Spacing.md
            ) {
                HStack(spacing: Spacing.md) {
                    // Status icon
                    ZStack {
                        Circle()
                            .fill(scan.isSafe ? Theme.success.opacity(0.2) : Theme.error.opacity(0.2))
                            .frame(width: 48, height: 48)

                        Image(systemName: scan.isSafe ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(scan.isSafe ? Theme.success : Theme.error)
                    }

                    // Product info
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(scan.productName)
                            .textStyleH4(color: Theme.textPrimary)
                            .lineLimit(1)

                        Text(scan.timestamp.formatted(date: .abbreviated, time: .shortened))
                            .textStyleCaption()

                        // Decision badge
                        let decision = scan.purchaseDecision
                        StatusBadge(
                            decision.rawValue,
                            variant: decision == .purchased ? .success : (decision == .avoided ? .error : .warning),
                            size: .small
                        )
                    }

                    Spacer()

                    // Health score
                    if scan.healthScore > 0 {
                        VStack(spacing: Spacing.xs) {
                            Text("\(Int(scan.healthScore))")
                                .font(Typography.h3)
                                .foregroundColor(Theme.healthScoreColor(scan.healthScore))
                            Text("health")
                                .textStyleCaption()
                        }
                    }

                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Theme.textMuted)
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(scan.productName), health score \(Int(scan.healthScore)), \(scan.isSafe ? "safe" : "has violations"), \(scan.purchaseDecision.rawValue), \(scan.timestamp.formatted(date: .abbreviated, time: .shortened))")
        .accessibilityHint("Double tap to view details")
    }

    // MARK: - Empty State

    @ViewBuilder
    private var emptyState: some View {
        EmptyState(
            icon: "clock.fill",
            title: filterOption == .all ? "No Scan History" : "No Results",
            message: filterOption == .all
                ? "Your scanned products will appear here"
                : "Try adjusting your filter or search",
            actionTitle: filterOption == .all ? nil : "Clear Filter",
            action: filterOption == .all ? nil : {
                filterOption = .all
                searchText = ""
            }
        )
        .scaleIn()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(filterOption == .all ? "No scan history. Your scanned products will appear here." : "No results. Try adjusting your filter or search.")
    }

    // MARK: - Data Management

    private func loadHistoryAsync() async {
        let fetched = await Task.detached(priority: .userInitiated) {
            HistoryService.shared.fetchAllScans()
        }.value
        scans = fetched
    }

    private func loadHistory() {
        scans = HistoryService.shared.fetchAllScans()
    }

    private func deleteScan(_ scan: ScanHistory) {
        HapticManager.shared.trigger(.impactLight)
        HistoryService.shared.deleteScan(id: scan.id)
        withAnimation(AnimationSystem.springSmooth) {
            scans.removeAll { $0.id == scan.id }
        }
    }

    private func clearHistory() {
        HistoryService.shared.clearAllHistory()
        loadHistory()
    }
}

// MARK: - Conditional Pulsing Modifier

private struct ConditionalPulsingModifier: ViewModifier {
    let shouldPulse: Bool

    func body(content: Content) -> some View {
        if shouldPulse {
            content.pulsing(duration: 2.0)
        } else {
            content
        }
    }
}

// MARK: - Swipeable History Card

struct SwipeableHistoryCard<CardContent: View>: View {
    let scan: ScanHistory
    @ViewBuilder let content: () -> CardContent
    let onDelete: () -> Void
    let onShare: () -> Void
    let onRescan: () -> Void

    @State private var offset: CGFloat = 0
    @State private var showActions = false

    private let actionThreshold: CGFloat = 70

    var body: some View {
        ZStack(alignment: .trailing) {
            // Trailing actions (delete/share) — revealed on swipe left
            if offset < -20 {
                HStack(spacing: 12) {
                    Button {
                        HapticManager.shared.trigger(.impactLight)
                        withAnimation(AnimationSystem.springResponsive) { offset = 0 }
                        onShare()
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 44, height: 44)
                            .background(Theme.accent)
                            .clipShape(Circle())
                    }

                    Button {
                        HapticManager.shared.trigger(.warning)
                        withAnimation(AnimationSystem.springResponsive) { offset = 0 }
                        onDelete()
                    } label: {
                        Image(systemName: "trash.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 44, height: 44)
                            .background(Theme.error)
                            .clipShape(Circle())
                    }
                }
                .transition(.opacity)
                .padding(.trailing, 8)
            }

            // Leading action (re-scan) — revealed on swipe right
            if offset > 20 {
                HStack {
                    Button {
                        HapticManager.shared.trigger(.impactMedium)
                        withAnimation(AnimationSystem.springResponsive) { offset = 0 }
                        onRescan()
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 44, height: 44)
                            .background(Theme.primary)
                            .clipShape(Circle())
                    }
                    .padding(.leading, 8)

                    Spacer()
                }
                .transition(.opacity)
            }

            // Card content
            content()
                .offset(x: offset)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            let translation = value.translation.width
                            // Rubber-band effect past threshold
                            if abs(translation) > actionThreshold {
                                let excess = abs(translation) - actionThreshold
                                let dampened = actionThreshold + excess * 0.3
                                offset = translation > 0 ? dampened : -dampened
                            } else {
                                offset = translation
                            }
                        }
                        .onEnded { value in
                            if abs(offset) > actionThreshold {
                                // Snap to show actions
                                withAnimation(AnimationSystem.springResponsive) {
                                    offset = offset > 0 ? actionThreshold : -actionThreshold
                                    showActions = true
                                }
                            } else {
                                // Snap back
                                withAnimation(AnimationSystem.springResponsive) {
                                    offset = 0
                                    showActions = false
                                }
                            }
                        }
                )
        }
        .clipped()
    }
}
