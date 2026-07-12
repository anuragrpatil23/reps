import SwiftUI

@main
struct RepsApp: App {
    @State private var store = LogStore()

    var body: some Scene {
        WindowGroup {
            TodayView()
                .environment(store)
        }
    }
}
