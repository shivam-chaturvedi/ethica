//
//  ContentView.swift
//  Ethica
//
//  Modernized with premium design system
//
import SwiftUI

struct ContentView: View {
    @StateObject private var preferencesManager = PreferencesManager.shared
    @EnvironmentObject var authService: AuthenticationService
    @State private var selectedTab = 0

    var body: some View {
        ZStack(alignment: .bottom) {
            // Background
            Theme.backgroundPrimary
                .ignoresSafeArea()

            // Tab content (no stock TabView)
            Group {
                switch selectedTab {
                case 0:
                    NavigationStack {
                        ScannerView(preferencesManager: preferencesManager, showScanner: nil)
                    }
                case 1:
                    HistoryView()
                case 2:
                    DashboardView()
                case 3:
                    NavigationStack {
                        PreferencesView(
                            preferencesManager: preferencesManager,
                            onComplete: nil
                        )
                    }
                default:
                    EmptyView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Pad bottom so content doesn't hide behind tab bar
            .padding(.bottom, Spacing.Height.tabBar + Spacing.md)

            // Custom tab bar
            EthicaTabBar(selectedTab: $selectedTab)
        }
        .ignoresSafeArea(.keyboard)
        .onChange(of: selectedTab) { _, _ in
            NotificationCenter.default.post(name: Notification.Name("ethica.tabDidChange"), object: selectedTab)
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("switchToTab"))) { notification in
            if let tab = notification.object as? Int {
                withAnimation(AnimationSystem.springSmooth) {
                    selectedTab = tab
                }
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(AuthenticationService.shared)
    }
}
