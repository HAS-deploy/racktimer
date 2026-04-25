import SwiftUI

struct RootTabView: View {
    var body: some View {
        TabView {
            TimerView()
                .trackScreen("timer")
                .tabItem { Label("Timer", systemImage: "timer") }

            LogView()
                .trackScreen("log")
                .tabItem { Label("Log", systemImage: "plus.circle") }

            TemplatesView()
                .tabItem { Label("Templates", systemImage: "list.bullet.rectangle") }

            HistoryView()
                .trackScreen("history")
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }

            SettingsView()
                .trackScreen("settings")
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}
