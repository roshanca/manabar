import AppKit
import SwiftUI

/// The menu-bar mana bar. Rendered as a plain NSImage (deterministic in the
/// menu bar, unlike arbitrary SwiftUI content). Fills follow the primary
/// provider's configured display — one window, or both stacked in dual
/// mode. Any displayed window >95% turns the icon critical and starts a
/// blink with an optional "Out of mana" easter egg; the blink task only
/// runs while critical, so idle costs zero timer wakeups.
///
/// NOTE: do not use TimelineView or live Text(.timer) here — self-invalidating
/// views in a MenuBarExtra label trigger an update/layout feedback loop
/// (100% CPU, unbounded memory; FB22359008). Manual @State updates are safe.
struct ManaBarLabel: View {
    @Environment(AppState.self) private var appState
    @State private var blinkPhase = false

    private var bars: [MenuBarBar] { appState.menuBarBars }
    private var isCritical: Bool {
        bars.contains { ($0.metric?.usedRatio ?? 0) > 0.95 }
            || UserDefaults.standard.bool(forKey: "debugForceCritical")
    }

    var body: some View {
        image
            .opacity(isCritical && blinkPhase ? 0.3 : 1)
            .task(id: isCritical) {
                blinkPhase = false
                while isCritical && !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(0.6))
                    blinkPhase.toggle()
                }
            }
    }

    private var image: some View {
        Image(nsImage: ManaBarImage.make(
            bars: bars,
            outOfMana: isCritical && appState.settings.outOfManaAlert))
    }
}
