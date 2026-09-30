import AppKit
import SwiftUI

/// Root popover: one card per enabled provider + bottom action bar.
struct PopoverView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("ManaBar")
                    .font(.title3.bold())
                Spacer()
                if appState.isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                } else if let lastRefresh = appState.lastRefresh {
                    Text("updated \(RelativeReset.ageString(lastRefresh))")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            let providers = ProviderID.allCases.filter { appState.settings.enabledProviders.contains($0) }
            if providers.isEmpty {
                Text("No providers enabled — open Settings to pick some.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 24)
            } else {
                ForEach(providers) { provider in
                    ProviderCardView(providerID: provider)
                }
            }

            Divider()

            HStack(spacing: 12) {
                Button {
                    Task { await appState.refresh() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(appState.isRefreshing)

                Spacer()

                Button {
                    openSettings()
                    NSApp.activate()
                } label: {
                    Label("Settings", systemImage: "gear")
                }

                Button {
                    NSApp.terminate(nil)
                } label: {
                    Label("Quit", systemImage: "power")
                }
            }
            .buttonStyle(.borderless)
            .font(.callout)
        }
        .padding(14)
        .frame(width: 360)
        .onAppear {
            // Opening the popover always fetches fresh data.
            Task { await appState.refresh() }
        }
    }
}
