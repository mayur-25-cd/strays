import SwiftUI

struct PopoverRootView: View {
    @Environment(PortStore.self) private var store
    @Environment(\.openWindow) private var openWindow
    @FocusState private var searchFocused: Bool

    var body: some View {
        @Bindable var store = store

        VStack(spacing: 0) {
            searchField
            Divider()
            summaryStrip
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 380)
        .frame(minHeight: 260, maxHeight: 520)
        .background(VisualEffectView(material: .menu, blending: .behindWindow))
        .onAppear { searchFocused = true }
    }

    private var searchField: some View {
        @Bindable var store = store
        return HStack(spacing: 7) {
            Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(.secondary)
            TextField("Filter ports, projects, commands…", text: $store.searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($searchFocused)
                .onSubmit {
                    if let target = store.popoverTopMatch { store.requestKill(target) }
                }
            if !store.searchText.isEmpty {
                Button { store.searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 38)
    }

    private var summaryStrip: some View {
        HStack(spacing: 8) {
            StatChip(icon: "lock.fill", text: "\(store.localCount) local", tint: Theme.local)
            if store.exposedCount > 0 {
                StatChip(icon: "exclamationmark.shield.fill", text: "\(store.exposedCount) exposed", tint: Theme.exposed)
            }
            if store.activeSessionCount > 0 {
                StatChip(icon: "sparkles", text: "\(store.activeSessionCount) AI", tint: Theme.ai)
            }
            Spacer()
            if let top = store.popoverTopMatch, !store.searchText.isEmpty {
                HStack(spacing: 4) {
                    Text("Kill \(top.title):\(String(top.port))").font(.system(size: 10)).foregroundStyle(.secondary)
                    KeyCap(text: "↩")
                }
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 30)
    }

    private var content: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                if store.popoverGroups.isEmpty {
                    EmptyStateView(message: store.searchText.isEmpty ? "Nothing listening" : "No matches")
                        .frame(height: 180)
                } else {
                    ForEach(store.popoverGroups) { group in
                        Section {
                            ForEach(group.entries) { entry in
                                PortRow(entry: entry, inPopover: true, hoverHighlight: true)
                            }
                        } header: {
                            PopoverSectionHeader(group: group)
                        }
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            PulseDot(isStale: store.isStale)
            Text("\(store.totalListening) listening")
                .font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit()
            if store.systemHiddenCount > 0 {
                Text("· \(store.systemHiddenCount) system")
                    .font(.system(size: 11)).foregroundStyle(.tertiary)
            }
            Spacer()
            Button {
                store.openMainWindow()
                openWindow(id: "main")
            } label: {
                Text("Open Strays").font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)

            Menu {
                SettingsLink { Text("Settings…") }
                Button("Quit Strays") { NSApp.terminate(nil) }
            } label: {
                Image(systemName: "ellipsis.circle").font(.system(size: 13))
            }
            .menuStyle(.borderlessButton)
            .frame(width: 28)
        }
        .padding(.horizontal, 14)
        .frame(height: 34)
    }
}

private struct PopoverSectionHeader: View {
    let group: PortGroup
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "folder.fill").font(.system(size: 9)).foregroundStyle(.secondary)
            Text(group.title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary).lineLimit(1)
            Spacer()
            Text("\(group.entries.count)").font(.system(size: 10, weight: .medium)).foregroundStyle(.tertiary).monospacedDigit()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 5)
        .background(.ultraThinMaterial)
    }
}
