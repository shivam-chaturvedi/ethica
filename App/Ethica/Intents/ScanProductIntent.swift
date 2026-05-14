//
//  ScanProductIntent.swift
//  Ethica
//
//  Siri App Intent for scanning products

import AppIntents

@available(iOS 16.0, *)
struct ScanProductIntent: AppIntent {
    static var title: LocalizedStringResource = "Scan Product"
    static var description = IntentDescription("Open Ethica scanner")
    static var openAppWhenRun: Bool = true
    
    func perform() async throws -> some IntentResult {
        return .result()
    }
}

@available(iOS 16.0, *)
struct EthicaAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ScanProductIntent(),
            phrases: [
                "Scan product in \(.applicationName)",
                "Scan with \(.applicationName)",
                "Check ingredients in \(.applicationName)"
            ],
            shortTitle: "Scan",
            systemImageName: "camera.viewfinder"
        )
    }
}

