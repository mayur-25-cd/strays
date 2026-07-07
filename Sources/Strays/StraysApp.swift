import SwiftUI

@main
struct StraysApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = PortStore()

    var body: some Scene {
        Window("Strays", id: "main") {
            MainWindowView()
                .environment(store)
                .frame(minWidth: 760, minHeight: 460)
        }
        .defaultSize(width: 1000, height: 660)
        .commands { PortCommands(store: store) }

        MenuBarExtra {
            PopoverRootView().environment(store)
        } label: {
            MenuBarLabel(store: store)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView().environment(store)
        }
    }
}

/// The menu-bar glyph: a plug + a live count of your servers. The plug fills in
/// as an ambient "something is exposed to the network" cue.
private struct MenuBarLabel: View {
    let store: PortStore

    private var serverCount: Int {
        store.entries.filter { !$0.isSystem && $0.ownedByCurrentUser }.count
    }

    var body: some View {
        Image(nsImage: MenuBarIcon.make(count: serverCount, exposed: store.exposedCount > 0))
            .renderingMode(.template)
    }
}

struct PortCommands: Commands {
    let store: PortStore

    var body: some Commands {
        CommandGroup(after: .sidebar) {
            Button("Refresh Ports") { Task { await store.refresh() } }
                .keyboardShortcut("r", modifiers: .command)
        }

        CommandMenu("Ports") {
            Button("Kill Selected") {
                if let entry = store.selectedEntry { store.requestKill(entry) }
            }
            .keyboardShortcut("k", modifiers: .command)
            .disabled(store.selectedEntry == nil)

            Button("Force Kill Selected") {
                if let entry = store.selectedEntry { store.requestKill(entry, force: true) }
            }
            .keyboardShortcut("k", modifiers: [.command, .shift])
            .disabled(store.selectedEntry == nil)

            Button("Open in Browser") {
                if let entry = store.selectedEntry { store.openInBrowser(entry) }
            }
            .keyboardShortcut("b", modifiers: .command)
            .disabled(store.selectedEntry?.isBrowsable != true)

            Divider()

            Button("Free a Port…") { store.freePortPresented = true }
                .keyboardShortcut("l", modifiers: .command)

            Button("Stop Servers Started This Session") { store.reapSession() }
                .keyboardShortcut("k", modifiers: [.command, .option])
                .disabled(store.newThisSessionEntries.isEmpty)

            Button("Stop Idle Servers") { store.reapIdle() }
                .disabled(store.idleEntries.isEmpty)

            Divider()

            Button("Show All") { store.sidebarFilter = .all }
                .keyboardShortcut("1", modifiers: .command)
            Button("AI") { store.sidebarFilter = .aiSessions }
                .keyboardShortcut("2", modifiers: .command)
            Button("All Ports") { store.sidebarFilter = .allPorts }
                .keyboardShortcut("3", modifiers: .command)
        }
    }
}
