import SwiftUI

@main
@MainActor
struct RepFlowWatchApp: App {
    @StateObject private var store: AppStore
    @StateObject private var coordinator: WorkoutCoordinator
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let sharedStore = AppStore.shared
        _store = StateObject(wrappedValue: sharedStore)
        _coordinator = StateObject(wrappedValue: WorkoutCoordinator(store: sharedStore))
    }

    var body: some Scene {
        WindowGroup {
            WatchHomeView()
                .environmentObject(store)
                .environmentObject(coordinator)
                .tint(.repLime)
                .preferredColorScheme(.dark)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { coordinator.tick() }
                    else { coordinator.saveBeforeBackground() }
                }
        }
    }
}

extension Color {
    static let repLime = Color(red: 0.78, green: 0.97, blue: 0.32)
    static let repSurface = Color(red: 0.10, green: 0.13, blue: 0.16)
}
