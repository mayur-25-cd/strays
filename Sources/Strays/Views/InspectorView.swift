import SwiftUI

struct InspectorView: View {
    @Environment(PortStore.self) private var store

    var body: some View {
        if let session = store.selectedSessionValue() {
            SessionDossier(session: session)
        } else if let entry = store.selectedEntry {
            PortDossier(entry: entry)
        } else {
            AtRestSummary()
        }
    }
}

// MARK: - AI session dossier

private struct SessionDossier: View {
    let session: AISession
    @Environment(PortStore.self) private var store

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 10) {
                    Image(systemName: session.tool.symbol)
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(session.tool.tint)
                        .symbolRenderingMode(.hierarchical)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(session.title).font(.system(size: 17, weight: .semibold))
                        if let model = session.modelShort {
                            Text(model).font(Theme.mono(12)).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }

                HStack(spacing: 8) {
                    Image(systemName: "circle.fill").font(.system(size: 8))
                    Text(store.sessionIsWorking(session) ? "Live · working" : "Live · idle")
                        .font(.system(size: 11, weight: .medium))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(store.sessionIsWorking(session) ? Theme.local : Color.secondary)
                .padding(10)
                .background((store.sessionIsWorking(session) ? Theme.local : Color.secondary).opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

                if let wd = session.workingDirectory, !wd.isEmpty {
                    Field(label: "Project") {
                        Button { store.revealInFinder(wd) } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "folder")
                                Text(displayPath(wd)).font(Theme.mono(11)).multilineTextAlignment(.leading)
                            }.foregroundStyle(Color.accentColor)
                        }
                        .buttonStyle(.plain)
                        .help("Reveal in Finder")
                    }
                }

                Field(label: "Details") {
                    VStack(alignment: .leading, spacing: 6) {
                        if let branch = session.gitBranch { InfoRow(key: "Branch", value: branch) }
                        if let msgs = session.messageCount { InfoRow(key: "Messages", value: "\(msgs)") }
                        if let tokens = session.tokenString { InfoRow(key: "Tokens", value: tokens) }
                        if let cache = session.cacheString { InfoRow(key: "Cache", value: cache) }
                        if let pid = session.pid { InfoRow(key: "PID", value: String(pid)) }
                        if let started = session.startedAt {
                            InfoRow(key: "Started", value: started.formatted(date: .abbreviated, time: .shortened))
                        }
                    }
                }

                if let cost = session.costString {
                    Field(label: "Estimated cost") {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(cost).font(Theme.mono(13, weight: .medium))
                            Text("Approximate, based on token usage and public pricing.")
                                .font(.system(size: 10)).foregroundStyle(.tertiary)
                        }
                    }
                }

                let projectPorts = store.ports(under: session)
                if !projectPorts.isEmpty {
                    Field(label: "Ports in this project") {
                        VStack(alignment: .leading, spacing: 7) {
                            ForEach(projectPorts) { port in
                                HStack(spacing: 8) {
                                    CategoryGlyph(entry: port, size: 12)
                                    Text(port.title).font(.system(size: 12))
                                    Text(":\(String(port.port))").font(Theme.mono(11)).foregroundStyle(.secondary)
                                    Spacer(minLength: 4)
                                    ExposureIndicator(entry: port)
                                }
                            }
                        }
                    }
                }

                Spacer(minLength: 8)
            }
            .padding(20)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                Divider()
                HStack(spacing: 10) {
                    if session.canStop {
                        Button(role: .destructive) { store.requestStopSession(session) } label: {
                            Label("Stop session", systemImage: "stop.circle.fill").frame(maxWidth: .infinity)
                        }
                        .controlSize(.large)
                        .tint(Theme.destructive)
                    } else {
                        Text("No process to stop").font(.system(size: 12)).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                    }
                }
                .padding(12)
            }
            .background(.bar)
        }
    }

    private func displayPath(_ path: String) -> String {
        let home = NSHomeDirectory()
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}

// MARK: - Dossier

private struct PortDossier: View {
    let entry: PortEntry
    @Environment(PortStore.self) private var store

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                statusRow
                ExposureBanner(entry: entry, lanIP: store.lanIP)

                if let full = entry.fullCommand {
                    Field(label: "Command") {
                        Text(full)
                            .font(Theme.mono(11))
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    } trailing: {
                        CopyButton(text: full)
                    }
                }

                if let wd = entry.workingDirectory, !wd.isEmpty {
                    Field(label: "Working directory") {
                        Button {
                            store.revealInFinder(wd)
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "folder")
                                Text(displayPath(wd)).font(Theme.mono(11)).multilineTextAlignment(.leading)
                            }
                            .foregroundStyle(Color.accentColor)
                        }
                        .buttonStyle(.plain)
                        .help("Reveal in Finder")
                    }
                }

                if let started = entry.startDate {
                    Field(label: "Started") {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(started.formatted(date: .abbreviated, time: .standard))
                                .font(Theme.mono(11)).textSelection(.enabled)
                            if let up = entry.uptimeString(reference: store.now) {
                                Text(up).font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                identityGrid
                connections

                Spacer(minLength: 8)
            }
            .padding(20)
        }
        .safeAreaInset(edge: .bottom) { actionBar }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: entry.symbol)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(entry.isSystem ? Color.secondary : entry.category.tint)
                .symbolRenderingMode(.hierarchical)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(entry.title).font(.system(size: 17, weight: .semibold))
                    Text(":\(String(entry.port))").font(Theme.mono(16, weight: .medium)).foregroundStyle(.secondary)
                }
                Text(entry.category.rawValue).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    @ViewBuilder private var statusRow: some View {
        let tags = statusTags
        if !tags.isEmpty {
            HStack(spacing: 6) {
                ForEach(tags, id: \.text) { tag in
                    InspectorTag(icon: tag.icon, text: tag.text, tint: tag.tint)
                }
            }
        }
    }

    private var statusTags: [(icon: String, text: String, tint: Color)] {
        var tags: [(String, String, Color)] = []
        if store.isNewThisSession(entry) {
            let ago = store.firstSeenByID[entry.id].map { PortEntry.humanize(max(0, Int(store.now.timeIntervalSince($0)))).replacingOccurrences(of: "up ", with: "") }
            tags.append(("sparkles", ago.map { "New · \($0)" } ?? "New this session", .accentColor))
        }
        if store.isIdle(entry) {
            tags.append(("moon.zzz.fill", "Idle", Theme.local))
        }
        let conns = store.connectionCount(entry)
        if conns > 0 {
            tags.append(("point.3.connected.trianglepath.dotted", "\(conns) connected", Theme.local))
        }
        return tags.map { (icon: $0.0, text: $0.1, tint: $0.2) }
    }

    private var identityGrid: some View {
        Field(label: "Identity") {
            VStack(alignment: .leading, spacing: 6) {
                InfoRow(key: "PID", value: String(entry.pid))
                InfoRow(key: "User", value: entry.user)
                InfoRow(key: "Protocol", value: entry.networkProtocol)
                InfoRow(key: "IP family", value: entry.familyLabel)
                InfoRow(key: "Bind", value: entry.addresses.joined(separator: ", "))
                if let cpu = entry.cpuString { InfoRow(key: "CPU", value: cpu) }
                if let mem = entry.memoryString { InfoRow(key: "Memory", value: mem) }
            }
        }
    }

    @ViewBuilder private var connections: some View {
        Field(label: "Active connections") {
            if store.connectionsLoading && store.selectedConnections.isEmpty {
                Text("Checking…").font(.system(size: 11)).foregroundStyle(.tertiary)
            } else if store.selectedConnections.isEmpty {
                Text("No active connections").font(.system(size: 11)).foregroundStyle(.tertiary)
            } else {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(store.selectedConnections) { conn in
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.right").font(.system(size: 8)).foregroundStyle(.tertiary)
                            Text(conn.peer).font(Theme.mono(11)).textSelection(.enabled)
                        }
                    }
                }
            }
        }
    }

    private var actionBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 10) {
                if store.canKill(entry) {
                    Button(role: .destructive) {
                        store.requestKill(entry)
                    } label: {
                        Label("Kill", systemImage: "xmark.circle.fill").frame(maxWidth: .infinity)
                    }
                    .controlSize(.large)
                    .tint(Theme.destructive)

                    Button {
                        store.requestKill(entry, force: true)
                    } label: {
                        Label("Force", systemImage: "xmark.octagon.fill")
                    }
                    .controlSize(.large)
                    .help("Force kill (SIGKILL) — always confirmed")
                } else {
                    Label("Managed by macOS", systemImage: "lock.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(12)
        }
        .background(.bar)
    }

    private func displayPath(_ path: String) -> String {
        let home = NSHomeDirectory()
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}

// MARK: - At-rest summary

private struct AtRestSummary: View {
    @Environment(PortStore.self) private var store

    private var tallies: [(ProcessCategory, Int)] {
        ProcessCategory.allCases.compactMap { category in
            let count = store.entries.filter { $0.category == category }.count
            return count > 0 ? (category, count) : nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Overview")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                ForEach(tallies, id: \.0) { category, count in
                    HStack(spacing: 8) {
                        Image(systemName: category.symbol)
                            .foregroundStyle(category.tint)
                            .symbolRenderingMode(.hierarchical)
                            .frame(width: 20)
                        Text(category.rawValue).font(.system(size: 12))
                        Spacer()
                        Text("\(count)").font(.system(size: 12, weight: .medium)).monospacedDigit().foregroundStyle(.secondary)
                    }
                }
            }

            if store.exposedCount > 0 {
                Divider()
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.shield.fill").foregroundStyle(Theme.exposed)
                    Text("\(store.exposedCount) exposed to network").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.exposed)
                }
            }

            Spacer()
            Text("Select a port to inspect it.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(20)
    }
}

// MARK: - Small building blocks

private struct Field<Content: View, Trailing: View>: View {
    let label: String
    @ViewBuilder var content: Content
    @ViewBuilder var trailing: Trailing

    init(label: String, @ViewBuilder content: () -> Content, @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.label = label
        self.content = content()
        self.trailing = trailing()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(label.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.5)
                    .foregroundStyle(.secondary)
                Spacer()
                trailing
            }
            content
        }
    }
}

private struct InfoRow: View {
    let key: String
    let value: String
    var body: some View {
        HStack(alignment: .top) {
            Text(key).font(.system(size: 11)).foregroundStyle(.secondary).frame(width: 64, alignment: .leading)
            Text(value).font(Theme.mono(11)).textSelection(.enabled)
            Spacer(minLength: 0)
        }
    }
}

private struct CopyButton: View {
    let text: String
    @Environment(PortStore.self) private var store
    @State private var copied = false
    var body: some View {
        Button {
            store.copyToClipboard(text)
            copied = true
        } label: {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help("Copy")
    }
}

struct ExposureBanner: View {
    let entry: PortEntry
    let lanIP: String?

    var body: some View {
        let exposed = entry.isExposed
        HStack(spacing: 8) {
            Image(systemName: entry.exposure.symbol)
                .foregroundStyle(entry.exposure.tint)
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(entry.exposure.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        .opacity(entry.isSystem && !exposed ? 0.8 : 1)
    }

    private var message: String {
        if entry.isExposed {
            if let lanIP { return "Reachable from your network — e.g. \(lanIP):\(entry.port)" }
            return "Reachable from your network (bound to \(entry.primaryAddress))"
        }
        return "Local only — reachable only from this Mac (\(entry.primaryAddress))"
    }
}
