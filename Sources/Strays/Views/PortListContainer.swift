import SwiftUI

struct PortListContainer: View {
    @Environment(PortStore.self) private var store

    private var selection: Binding<PortEntry.ID?> {
        Binding(get: { store.selectedID }, set: { store.select($0) })
    }

    var body: some View {
        Group {
            if store.sidebarFilter == .recentlyKilled {
                RecentlyKilledView()
            } else if !store.hasLoadedOnce {
                loadingState
            } else if store.projectGroups.isEmpty {
                emptyState
            } else {
                unifiedList
            }
        }
        .frame(minWidth: 480)
        .safeAreaInset(edge: .top, spacing: 0) { reapBanner }
    }

    // MARK: - Unified project list: AI sessions lead, their ports nested beneath

    private var unifiedList: some View {
        List(selection: selection) {
            ForEach(store.projectGroups) { group in
                Section {
                    ForEach(group.items) { item in
                        row(for: item, nested: group.sessionCount > 0 && !item.isSession)
                            .tag(item.id)
                    }
                } header: {
                    UnifiedGroupHeader(group: group)
                }
            }
        }
        .listStyle(.inset)
        .environment(\.defaultMinListRowHeight, store.density.rowHeight)
    }

    @ViewBuilder private func row(for item: RowItem, nested: Bool) -> some View {
        switch item {
        case .session(let session):
            SessionRow(session: session)
                .contextMenu { SessionMenu(session: session) }
        case .port(let entry):
            PortRow(entry: entry)
                .padding(.leading, nested ? 22 : 0)   // quiet indent = "belongs to the session above"
                .contextMenu { RowMenu(entry: entry) }
        }
    }

    @ViewBuilder private var reapBanner: some View {
        if store.sidebarFilter == .sessionNew, !store.newThisSessionEntries.isEmpty {
            ReapBanner(
                icon: "plus.circle.fill",
                message: "\(store.newThisSessionEntries.count) \(plural(store.newThisSessionEntries.count, "server")) started since you opened Strays.",
                tint: .accentColor
            ) { store.reapSession() }
        } else if store.sidebarFilter == .idle, !store.idleEntries.isEmpty {
            ReapBanner(
                icon: "moon.zzz.fill",
                message: "\(store.idleEntries.count) \(plural(store.idleEntries.count, "server")) up a while with no active connections.",
                tint: Theme.local
            ) { store.reapIdle() }
        }
    }

    private func plural(_ n: Int, _ word: String) -> String { n == 1 ? word : word + "s" }

    // MARK: - States

    @ViewBuilder private var emptyState: some View {
        if !store.searchText.isEmpty {
            EmptyStateView(message: "No matches", detail: "Nothing matches “\(store.searchText)”.")
        } else {
            switch store.sidebarFilter {
            case .aiSessions:
                EmptyStateView(message: "No AI tools running", detail: "Start Claude Code, Copilot, or an AI IDE like Antigravity — they show up here.")
            case .working:
                EmptyStateView(message: "Nothing active right now", detail: "No sessions with recent activity and no ports with live connections.")
            case .sessionNew:
                EmptyStateView(message: "Nothing new yet", detail: "Sessions and servers started while Strays is open appear here.")
            case .idle:
                EmptyStateView(message: "Nothing idle", detail: "Everything running has recent activity. Nice and tidy.")
            case .exposed:
                EmptyStateView(message: "Nothing exposed", detail: "No ports are reachable from your network — all local only.")
            default:
                EmptyStateView(message: "Nothing here", detail: store.hideSystem ? "No local servers or sessions are running. System processes are hidden." : "Nothing is listening and no sessions are running.")
            }
        }
    }

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Scanning…").font(.system(size: 13)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Unified group header (the project spine)

struct UnifiedGroupHeader: View {
    let group: ProjectGroup
    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: group.symbol)
                .font(.system(size: 11))
                .foregroundStyle(group.isSystemBucket ? Color.secondary : Color.accentColor)
            Text(group.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(group.isSystemBucket ? Color.secondary : Color.primary)
            if let subtitle = group.subtitle {
                Text(subtitle)
                    .font(Theme.mono(10)).foregroundStyle(.tertiary)
                    .lineLimit(1).truncationMode(.head)
            }
            Spacer()
        }
    }
}

// MARK: - Context menus

struct SessionMenu: View {
    let session: AISession
    @Environment(PortStore.self) private var store
    var body: some View {
        if session.canStop {
            Button("Stop \(session.title)") { store.requestStopSession(session) }
            Divider()
        }
        if let wd = session.workingDirectory, !wd.isEmpty {
            Button("Reveal Project in Finder") { store.revealInFinder(wd) }
            Button("Copy Project Path") { store.copyToClipboard(wd) }
        }
        if let pid = session.pid {
            Button("Copy PID") { store.copyToClipboard(String(pid)) }
        }
    }
}

struct RowMenu: View {
    let entry: PortEntry
    @Environment(PortStore.self) private var store

    var body: some View {
        if store.canKill(entry) {
            Button("Kill \(entry.title) :\(entry.port)") { store.requestKill(entry) }
            Button("Force Kill (SIGKILL)") { store.requestKill(entry, force: true) }
            Divider()
        }
        if entry.isBrowsable {
            Button("Open in Browser") { store.openInBrowser(entry) }
        }
        if let wd = entry.workingDirectory, !wd.isEmpty, wd != "/" {
            Button("Reveal Project in Finder") { store.revealInFinder(wd) }
        }
        Divider()
        Button("Copy Port") { store.copyToClipboard(String(entry.port)) }
        Button("Copy PID") { store.copyToClipboard(String(entry.pid)) }
        Button("Copy Kill Command") { store.copyToClipboard(entry.killCommand) }
        if let full = entry.fullCommand {
            Button("Copy Full Command") { store.copyToClipboard(full) }
        }
    }
}
