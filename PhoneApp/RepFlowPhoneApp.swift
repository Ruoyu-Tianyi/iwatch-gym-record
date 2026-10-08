import SwiftUI
import RepFlowCore

@main
struct RepFlowPhoneApp: App {
    @StateObject private var store = AppStore.shared

    var body: some Scene {
        WindowGroup {
            PhoneRootView()
                .environmentObject(store)
                .tint(PhoneTheme.lime)
                .preferredColorScheme(.dark)
        }
    }
}

enum PhoneTab: Hashable {
    case overview, plans, history, settings
}

struct PhoneRootView: View {
    @EnvironmentObject private var store: AppStore
    @State private var selection = PhoneTab.overview

    var body: some View {
        TabView(selection: $selection) {
            NavigationStack { OverviewView(selection: $selection) }
                .tabItem { Label("概览", systemImage: "square.grid.2x2.fill") }
                .tag(PhoneTab.overview)
            NavigationStack { PlanListView() }
                .tabItem { Label("计划", systemImage: "list.bullet.clipboard.fill") }
                .tag(PhoneTab.plans)
            NavigationStack { HistoryView() }
                .tabItem { Label("记录", systemImage: "chart.bar.xaxis") }
                .tag(PhoneTab.history)
            NavigationStack { SettingsView() }
                .tabItem { Label("设置", systemImage: "gearshape.fill") }
                .tag(PhoneTab.settings)
        }
        .alert("需要留意", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )) {
            Button("知道了", role: .cancel) { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "")
        }
    }
}
