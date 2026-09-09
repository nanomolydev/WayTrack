import SwiftUI

@main
struct WayTrackApp: App {
    @StateObject private var store = Store()

    var body: some Scene {
        WindowGroup {
            TabView {
                TimelineScreen()
                    .tabItem { Label("Таймлайн", systemImage: "capsule.portrait") }
                NowScreen()
                    .tabItem { Label("Сейчас", systemImage: "circle.dashed") }
            }
            .environmentObject(store)
            .preferredColorScheme(.dark)
            .task { Notifications.requestAccess() }
        }
    }
}
