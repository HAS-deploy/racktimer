import SwiftUI

struct RootTabView: View {
    var body: some View {
        TabView {
            TimerView()
                .tabItem { Label("Timer", systemImage: "timer") }

            LogView()
                .tabItem { Label("Log", systemImage: "plus.circle") }

            TemplatesView()
                .tabItem { Label("Templates", systemImage: "list.bullet.rectangle") }

            HistoryView()
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}
