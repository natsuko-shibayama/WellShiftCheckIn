import SwiftUI

@main
struct WellShiftCheckinApp: App {
    static let checkInDemoWindowID = "check-in-demo"

    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView()
                .environmentObject(appState)
        } label: {
            MenuBarLabelView()
                .environmentObject(appState)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(appState)
        }

        Window("チェックインデモ", id: Self.checkInDemoWindowID) {
            DemoCheckInPopupView()
        }
        .defaultSize(width: 360, height: 480)
    }
}
