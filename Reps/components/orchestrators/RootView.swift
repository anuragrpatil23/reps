import SwiftUI

/// Two homes: Today (log the loop) and Trends (see the history). Tab bar is
/// tinted paper so it reads as part of the ledger, not system chrome.
struct RootView: View {
    @State private var tab = 0

    var body: some View {
        TabView(selection: $tab) {
            TodayView()
                .tabItem { Label("Today", systemImage: "calendar.day.timeline.left") }
                .tag(0)
            TrendsView()
                .tabItem { Label("Trends", systemImage: "chart.xyaxis.line") }
                .tag(1)
        }
        .tint(Palette.madder)
        .toolbarBackground(Palette.paper, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
    }
}
