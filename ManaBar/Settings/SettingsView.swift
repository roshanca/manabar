import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var devinAPIKey = ""
    @State private var kimiWebToken = ""

    private var settings: AppSettings { appState.settings }

    var body: some View {
        Form {
            Section("Providers") {
                ForEach(ProviderID.allCases) { provider in
                    HStack {
                        Toggle(provider.displayName, isOn: binding(for: provider))
                        Spacer()
                        Picker("Menu bar", selection: metricBinding(for: provider)) {
                            ForEach(MetricKind.allCases) { kind in
                                Text(kind.label).tag(kind)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: 140)
                        .disabled(!settings.enabledProviders.contains(provider))
                    }
                }
                Picker("Menu bar shows", selection: primaryProviderBinding) {
                    ForEach(ProviderID.allCases) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
            }

            Section("General") {
                Picker("Refresh", selection: refreshIntervalBinding) {
                    ForEach(AppSettings.RefreshInterval.allCases) { interval in
                        Text(interval.label).tag(interval)
                    }
                }
                Toggle("Show remaining instead of used", isOn: showRemainingBinding)
                Toggle("Launch at login", isOn: launchAtLoginBinding)
                Toggle(#""Out of mana" alert when critical"#, isOn: outOfManaBinding)
            }

            Section("Kimi web session") {
                SecureField("refresh_token", text: $kimiWebToken)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Button("Save") {
                        let trimmed = kimiWebToken.trimmingCharacters(in: .whitespacesAndNewlines)
                        Task {
                            if trimmed.isEmpty {
                                await KimiWebCredentialStore.shared.clear()
                            } else {
                                await KimiWebCredentialStore.shared.importRefreshToken(trimmed)
                            }
                            kimiWebToken = ""
                            await appState.refresh()
                        }
                    }
                    .disabled(kimiWebToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              && KeychainHelper.read(service: KeychainHelper.kimiWebService,
                                                     account: KeychainHelper.kimiWebAccount) == nil)
                    if KeychainHelper.read(service: KeychainHelper.kimiWebService,
                                           account: KeychainHelper.kimiWebAccount) != nil {
                        Label("Token saved", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                    }
                }
                Text("Shows the real booster recharge balance. Copy from kimi.com: "
                     + "DevTools → Console → localStorage.getItem('refresh_token'). "
                     + "Valid ~90 days.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Devin API key") {
                SecureField("API key (stored in Keychain)", text: $devinAPIKey)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Button("Save") {
                        let trimmed = devinAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmed.isEmpty {
                            KeychainHelper.delete(
                                service: KeychainHelper.devinService,
                                account: KeychainHelper.devinAccount)
                        } else {
                            KeychainHelper.save(
                                service: KeychainHelper.devinService,
                                account: KeychainHelper.devinAccount,
                                value: trimmed)
                        }
                        devinAPIKey = ""
                        Task { await appState.refresh() }
                    }
                    .disabled(devinAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              && KeychainHelper.read(service: KeychainHelper.devinService,
                                                     account: KeychainHelper.devinAccount) == nil)
                    if KeychainHelper.read(service: KeychainHelper.devinService,
                                           account: KeychainHelper.devinAccount) != nil {
                        Label("Key saved", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 560)
    }

    // MARK: - Bindings (AppSettings is @Observable; explicit bindings keep didSet persistence)

    private func binding(for provider: ProviderID) -> Binding<Bool> {
        Binding(
            get: { settings.enabledProviders.contains(provider) },
            set: { enabled in
                if enabled { settings.enabledProviders.insert(provider) }
                else { settings.enabledProviders.remove(provider) }
            })
    }

    private func metricBinding(for provider: ProviderID) -> Binding<MetricKind> {
        Binding(
            get: { settings.menuBarKind(for: provider) },
            set: { settings.setMenuBarKind($0, for: provider) })
    }

    private var primaryProviderBinding: Binding<ProviderID> {
        Binding(
            get: { settings.primaryProvider },
            set: { settings.primaryProvider = $0 })
    }

    private var refreshIntervalBinding: Binding<AppSettings.RefreshInterval> {
        Binding(
            get: { settings.refreshInterval },
            set: {
                settings.refreshInterval = $0
                appState.restartCadence()
            })
    }

    private var showRemainingBinding: Binding<Bool> {
        Binding(
            get: { settings.showRemaining },
            set: { settings.showRemaining = $0 })
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { settings.launchAtLogin },
            set: { newValue in
                do {
                    if newValue { try SMAppService.mainApp.register() }
                    else { try SMAppService.mainApp.unregister() }
                    settings.launchAtLogin = newValue
                } catch {
                    settings.launchAtLogin = SMAppService.mainApp.status == .enabled
                }
            })
    }

    private var outOfManaBinding: Binding<Bool> {
        Binding(
            get: { settings.outOfManaAlert },
            set: { settings.outOfManaAlert = $0 })
    }
}
