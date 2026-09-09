import SwiftUI

@main
struct WayTrackApp: App {
    @StateObject private var store = Store()
    // ponytail: аргументы запуска нужны только смоуку в CI, чтобы снять оба экрана.
    @State private var tab = ProcessInfo.processInfo.arguments.contains("--now") ? 1 : 0

    var body: some Scene {
        WindowGroup {
            TabView(selection: $tab) {
                TimelineScreen()
                    .tabItem { Label("Таймлайн", systemImage: "capsule.portrait") }
                    .tag(0)
                NowScreen()
                    .tabItem { Label("Сейчас", systemImage: "circle.dashed") }
                    .tag(1)
            }
            .environmentObject(store)
            .preferredColorScheme(.dark)
        }
    }
}
