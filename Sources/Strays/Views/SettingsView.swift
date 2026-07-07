import SwiftUI

struct SettingsView: View {
    @Environment(PortStore.self) private var store

    @AppStorage(SettingsKey.launchAtLogin) private var launchAtLogin = true
    @AppStorage(SettingsKey.menuBarOnly) private var menuBarOnly = false
    @AppStorage(SettingsKey.notifyOnExposure) private var notifyOnExposure = true

    var body: some View {
        @Bindable var store = store

        Form {
            Section("Live Updates") {
                Toggle("Auto-refresh", isOn: $store.autoRefresh)
                Picker("Interval", selection: $store.refreshInterval) {
                    Text("1 second").tag(1.0)
                    Text("2 seconds").tag(2.0)
                    Text("5 seconds").tag(5.0)
                }
                .disabled(!store.autoRefresh)
            }

            Section("Appearance") {
                Picker("Row density", selection: $store.density) {
                    ForEach(RowDensity.allCases) { Text($0.rawValue).tag($0) }
                }
                Toggle("Hide System & Apple processes", isOn: $store.hideSystem)
            }

            Section("Health") {
                Picker("Flag as idle after", selection: $store.idleThreshold) {
                    Text("30 minutes").tag(1800.0)
                    Text("1 hour").tag(3600.0)
                    Text("2 hours").tag(7200.0)
                    Text("4 hours").tag(14400.0)
                }
                Text("A server up longer than this with no active connections is marked idle — a likely leftover from an old session.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Notifications") {
                Toggle("Notify when a port is exposed to the network", isOn: $notifyOnExposure)
                    .onChange(of: notifyOnExposure) { _, enabled in
                        if enabled { ExposureNotifier.shared.requestAuthorizationIfNeeded() }
                    }
                Text("Get a desktop alert the moment a server becomes reachable from other devices (bound to 0.0.0.0).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("General") {
                Toggle("Show in menu bar only (hide Dock icon)", isOn: $menuBarOnly)
                    .onChange(of: menuBarOnly) { _, only in
                        AppEnvironment.applyActivationPolicy(menuBarOnly: only, closeExistingWindows: false)
                    }
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        AppEnvironment.syncLaunchAtLogin(enabled)
                    }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 400)
    }
}
