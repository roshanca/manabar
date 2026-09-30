import AppKit
import SwiftUI

@main
struct ManaBarApp: App {
    @State private var appState: AppState

    /// Debug aids: `defaults write com.roshan.manabar debugShowPopover -bool true`
    /// (and/or debugShowSettings) open those views in regular windows at launch,
    /// for screenshots and UI testing.
    private let showDebugWindow = UserDefaults.standard.bool(forKey: "debugShowPopover")
    private let showDebugSettings = UserDefaults.standard.bool(forKey: "debugShowSettings")

    var body: some Scene {
        MenuBarExtra {
            PopoverView()
                .environment(appState)
        } label: {
            ManaBarLabel()
                .environment(appState)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(appState)
        }

        WindowGroup("ManaBar Preview", id: "debug-preview") {
            if showDebugSettings {
                SettingsView()
                    .environment(appState)
            } else {
                PopoverView()
                    .environment(appState)
            }
        }
        .defaultLaunchBehavior((showDebugWindow || showDebugSettings) ? .presented : .suppressed)
    }

    init() {
        // Start fetching immediately; the cadence loop idles (zero CPU)
        // between refreshes.
        let appState = AppState()
        _appState = State(initialValue: appState)
        appState.startCadence()
    }
}
