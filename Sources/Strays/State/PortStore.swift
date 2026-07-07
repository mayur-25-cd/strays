import AppKit
import Foundation
import Observation

/// A graceful kill that has been requested but not yet sent — the honest
/// basis for "Undo": during this window no signal has been delivered.
struct PendingKill: Identifiable, Equatable {
    let id = UUID()
    let entry: PortEntry
    var secondsRemaining: Int
    static func == (lhs: PendingKill, rhs: PendingKill) -> Bool { lhs.id == rhs.id }
}

/// A higher-stakes kill (database / exposed / force / group) that must be
/// explicitly confirmed by name before any signal is sent.
struct KillConfirmRequest: Identifiable {
    let id = UUID()
    let entries: [PortEntry]
    let force: Bool
    let title: String
    let message: String
    let confirmLabel: String
}

struct ErrorToast: Identifiable, Equatable {
    let id = UUID()
    let text: String
}

@MainActor
@Observable
final class PortStore {
    // Data
    private(set) var entries: [PortEntry] = []
    private(set) var sessions: [AISession] = []
    private(set) var hasLoadedOnce = false
    private(set) var isScanning = false
    private(set) var lastScan: Date?
    private(set) var isStale = false
    private(set) var lanIP: String?

    // Controls
    var searchText = ""
    var sort: SortOption = .project
    var grouping: GroupOption = .project
    var sidebarFilter: SidebarFilter = .all

    // Persisted preferences
    var hideSystem = true { didSet { UserDefaults.standard.set(hideSystem, forKey: SettingsKey.hideSystem) } }
    var autoRefresh = true { didSet { UserDefaults.standard.set(autoRefresh, forKey: SettingsKey.autoRefresh) } }
    var refreshInterval: TimeInterval = 2 { didSet { UserDefaults.standard.set(refreshInterval, forKey: SettingsKey.refreshInterval) } }
    var density: RowDensity = .comfortable { didSet { UserDefaults.standard.set(density.rawValue, forKey: SettingsKey.density) } }
    var idleThreshold: TimeInterval = 7200 { didSet { UserDefaults.standard.set(idleThreshold, forKey: SettingsKey.idleThreshold) } }

    // Session & health tracking
    private(set) var sessionStart = Date()
    private(set) var connectionCountByPort: [Int: Int] = [:]
    private var hasSweptConnections = false
    private var baselineIDs: Set<String> = []
    private var sessionBaselineCaptured = false
    private(set) var firstSeenByID: [String: Date] = [:]

    // Selection & inspector
    var selectedID: PortEntry.ID?
    private(set) var selectedConnections: [Connection] = []
    private(set) var connectionsLoading = false

    // Kill coordination
    private(set) var pendingKill: PendingKill?
    private(set) var terminatingPIDs: Set<Int32> = []
    private(set) var stubbornPIDs: Set<Int32> = []
    var killConfirm: KillConfirmRequest?
    var sessionConfirm: AISession?
    var errorToast: ErrorToast?
    var freePortPresented = false
    private(set) var killedHistory: [KilledRecord] = []

    // Live clock so uptime labels tick without touching row identity.
    private(set) var now = Date()

    private let scanner = PortScanner()
    private let sessionScanner = AISessionScanner()
    private let connectionResolver = ConnectionResolver()
    private var refreshTask: Task<Void, Never>?
    private var pendingKillTask: Task<Void, Never>?
    private var stubbornTasks: [Int32: Task<Void, Never>] = [:]

    // Exposure-notification tracking
    private var exposureBaselineSeeded = false
    private var knownExposedIDs: Set<String> = []

    init() {
        let defaults = UserDefaults.standard
        hideSystem = defaults.object(forKey: SettingsKey.hideSystem) as? Bool ?? true
        autoRefresh = defaults.object(forKey: SettingsKey.autoRefresh) as? Bool ?? true
        refreshInterval = defaults.object(forKey: SettingsKey.refreshInterval) as? Double ?? 2
        density = (defaults.string(forKey: SettingsKey.density)).flatMap(RowDensity.init(rawValue:)) ?? .comfortable
        idleThreshold = defaults.object(forKey: SettingsKey.idleThreshold) as? Double ?? 7200
    }

    // MARK: - Lifecycle

    func start() {
        lanIP = NetworkInfo.primaryLANAddress()
        guard refreshTask == nil else { return }
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if self.autoRefresh || !self.hasLoadedOnce {
                    await self.refresh()
                } else {
                    self.now = Date()
                }
                let interval = max(0.5, self.refreshInterval)
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
    }

    func stop() {
        refreshTask?.cancel(); refreshTask = nil
    }

    func refresh() async {
        if isScanning { return }
        isScanning = true
        async let portsTask = scanner.scan()
        async let sessionsTask = sessionScanner.scan()
        async let connectionsTask = connectionResolver.inboundCounts()
        let scanned = await portsTask
        let scannedSessions = await sessionsTask
        let conns = await connectionsTask
        isScanning = false
        now = Date()

        connectionCountByPort = conns
        hasSweptConnections = true
        sessions = scannedSessions

        if scanned.isEmpty && hasLoadedOnce && !entries.isEmpty {
            // lsof may have hiccuped; hold the last good snapshot rather than blanking.
            isStale = true
        } else {
            entries = PortEntry.flatten(scanned)
            isStale = false
            hasLoadedOnce = true
            trackSession()
            evaluateExposureNotifications()
        }
        lastScan = Date()

        // Reconcile kill state against reality.
        let livePIDs = Set(entries.map(\.pid))
        terminatingPIDs.formIntersection(livePIDs)
        stubbornPIDs.formIntersection(livePIDs)
        for (pid, task) in stubbornTasks where !livePIDs.contains(pid) {
            task.cancel(); stubbornTasks[pid] = nil
        }

        if let selectedID, resolveItem(selectedID) == nil {
            self.selectedID = nil       // also covers sessions, not just ports
            selectedConnections = []
        }
        await loadConnectionsForSelection()
    }

    /// Fire a notification when a user-owned port becomes network-exposed. The
    /// first scan only seeds the baseline so pre-existing exposed ports at
    /// launch don't all fire at once.
    private func evaluateExposureNotifications() {
        let currentExposed = Set(entries.filter { $0.isExposed && !$0.isSystem }.map(\.id))
        defer { knownExposedIDs = currentExposed }

        guard exposureBaselineSeeded else {
            exposureBaselineSeeded = true
            return
        }

        let notify = UserDefaults.standard.object(forKey: SettingsKey.notifyOnExposure) as? Bool ?? true
        guard notify else { return }

        let newlyExposed = currentExposed.subtracting(knownExposedIDs)
        guard !newlyExposed.isEmpty else { return }
        let newEntries = entries.filter { newlyExposed.contains($0.id) }
        ExposureNotifier.shared.notifyNewlyExposed(newEntries)
    }

    // MARK: - Session & health

    private func trackSession() {
        let ids = Set(entries.map(\.id)).union(sessions.map(\.id))
        if !sessionBaselineCaptured {
            baselineIDs = ids
            sessionBaselineCaptured = true
        }
        for id in ids where firstSeenByID[id] == nil { firstSeenByID[id] = now }
        firstSeenByID = firstSeenByID.filter { ids.contains($0.key) }
    }

    /// Appeared after the app started watching (not part of the launch baseline).
    func isNewThisSession(id: String) -> Bool {
        sessionBaselineCaptured && !baselineIDs.contains(id)
    }
    func isNewThisSession(_ entry: PortEntry) -> Bool { isNewThisSession(id: entry.id) }

    /// Just born — drives the brief "new" pulse on a row.
    func isRecentlyBorn(_ entry: PortEntry) -> Bool {
        guard isNewThisSession(entry), let seen = firstSeenByID[entry.id] else { return false }
        return now.timeIntervalSince(seen) < 90
    }

    func connectionCount(_ entry: PortEntry) -> Int {
        connectionCountByPort[entry.port] ?? 0
    }

    /// Up a while with no active connections — probably a forgotten server.
    func isIdle(_ entry: PortEntry) -> Bool {
        guard hasSweptConnections, !entry.isSystem, entry.ownedByCurrentUser else { return false }
        guard let start = entry.startDate else { return false }
        return now.timeIntervalSince(start) >= idleThreshold && connectionCount(entry) == 0
    }

    func idleDuration(_ entry: PortEntry) -> String? {
        entry.uptimeString(reference: now)
    }

    var newThisSessionEntries: [PortEntry] {
        entries.filter { isNewThisSession($0) && !$0.isSystem }
    }

    var idleEntries: [PortEntry] {
        entries.filter { isIdle($0) }
    }

    // MARK: - AI sessions & unified project view

    func sessionIsWorking(_ s: AISession) -> Bool {
        guard s.isLive, let last = s.lastActivity else { return false }
        return now.timeIntervalSince(last) < 600      // active in the last 10 min
    }
    func sessionIsIdle(_ s: AISession) -> Bool { s.isLive && !sessionIsWorking(s) }
    var liveSessions: [AISession] { sessions.filter { $0.isLive } }
    var activeSessionCount: Int { liveSessions.count }
    func selectedSessionValue() -> AISession? {
        guard let selectedID else { return nil }
        return sessions.first { $0.id == selectedID }
    }
    private func portIsWorking(_ p: PortEntry) -> Bool { connectionCount(p) > 0 }

    private var visiblePorts: [PortEntry] {
        hideSystem ? entries.filter { !$0.isSystem } : entries
    }

    /// Ports listening in the same project folder as a session — "what it's running."
    func ports(under session: AISession) -> [PortEntry] {
        guard let cwd = session.workingDirectory, !cwd.isEmpty else { return [] }
        return entries.filter { $0.workingDirectory == cwd }.sorted { $0.port < $1.port }
    }

    func resolveItem(_ id: String) -> RowItem? {
        if let p = entries.first(where: { $0.id == id }) { return .port(p) }
        if let s = sessions.first(where: { $0.id == id }) { return .session(s) }
        return nil
    }

    private func matchesSessionSearch(_ s: AISession, _ q: String) -> Bool {
        s.title.lowercased().contains(q)
            || (s.model?.lowercased().contains(q) ?? false)
            || (s.projectName?.lowercased().contains(q) ?? false)
            || (s.workingDirectory?.lowercased().contains(q) ?? false)
    }

    private func projectKey(cwd: String?, isSystem: Bool) -> String {
        if isSystem { return "__system__" }
        guard let c = cwd, !c.isEmpty, c != "/" else { return "__unknown__" }
        return c
    }

    /// The main content: one bucket per project, its AI session(s) leading and
    /// that project's ports nested beneath — filtered by the selected sidebar lens.
    var projectGroups: [ProjectGroup] {
        let q = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        var portsByKey: [String: [PortEntry]] = [:]
        var sessionsByKey: [String: [AISession]] = [:]
        var order: [String] = []

        for p in visiblePorts {
            let k = projectKey(cwd: p.workingDirectory, isSystem: p.isSystem)
            if portsByKey[k] == nil && sessionsByKey[k] == nil { order.append(k) }
            portsByKey[k, default: []].append(p)
        }
        for s in liveSessions {
            let k = projectKey(cwd: s.workingDirectory, isSystem: false)
            if portsByKey[k] == nil && sessionsByKey[k] == nil { order.append(k) }
            sessionsByKey[k, default: []].append(s)
        }

        var groups: [ProjectGroup] = []
        for k in order {
            var grpSessions = sessionsByKey[k] ?? []
            var grpPorts = (portsByKey[k] ?? []).sorted { $0.port < $1.port }

            switch sidebarFilter {
            case .all, .recentlyKilled: break
            case .allPorts: grpSessions = []
            case .aiSessions:
                // "AI" = agent sessions (with their nested ports) AND AI IDE apps.
                if grpSessions.isEmpty { grpPorts = grpPorts.filter { $0.category == .aiTool } }
            case .working:
                grpSessions = grpSessions.filter { sessionIsWorking($0) }
                grpPorts = grpPorts.filter { portIsWorking($0) }
            case .idle:
                grpSessions = grpSessions.filter { sessionIsIdle($0) }
                grpPorts = grpPorts.filter { isIdle($0) }
            case .sessionNew:
                grpSessions = grpSessions.filter { isNewThisSession(id: $0.id) }
                grpPorts = grpPorts.filter { isNewThisSession($0) }
            case .exposed:
                grpSessions = []
                grpPorts = grpPorts.filter { $0.isExposed }
            case .category(let c):
                grpSessions = []
                grpPorts = grpPorts.filter { $0.category == c }
            }

            if !q.isEmpty {
                grpSessions = grpSessions.filter { matchesSessionSearch($0, q) }
                grpPorts = grpPorts.filter { matchesSearch($0, q) }
            }
            if grpSessions.isEmpty && grpPorts.isEmpty { continue }

            let items = grpSessions.map(RowItem.session) + grpPorts.map(RowItem.port)
            let isSys = k == "__system__"
            let sampleName = grpSessions.first?.projectName ?? grpPorts.first?.projectName
            let title = isSys ? "System & Apple" : (k == "__unknown__" ? "Unknown location" : (sampleName ?? "Unknown"))
            let subtitle = (isSys || k == "__unknown__") ? nil : abbreviate(k)
            groups.append(ProjectGroup(id: k, title: title, subtitle: subtitle, symbol: isSys ? "gearshape.fill" : "folder.fill", isSystemBucket: isSys, items: items))
        }
        groups.sort { a, b in a.isSystemBucket != b.isSystemBucket ? !a.isSystemBucket : false }
        return groups
    }

    // MARK: - Stop an AI session

    func requestStopSession(_ session: AISession) {
        guard session.canStop else {
            errorToast = ErrorToast(text: "\(session.title) has no process to stop.")
            return
        }
        sessionConfirm = session      // stopping an agent is always confirmed
    }

    func confirmStopSession() {
        guard let session = sessionConfirm, let pid = session.pid else { sessionConfirm = nil; return }
        sessionConfirm = nil
        let outcome = ProcessKiller.terminate(pid: pid, force: false)
        switch outcome {
        case .success, .noSuchProcess:
            sessions.removeAll { $0.pid == pid }   // the vanishing row is the confirmation
            if selectedID == session.id { selectedID = nil }
        case .notPermitted:
            errorToast = ErrorToast(text: "\(session.title) requires admin rights to stop.")
        case .failure(let code):
            errorToast = ErrorToast(text: "Couldn't stop \(session.title) (error \(code)).")
        }
        Task { await refresh() }
    }

    func cancelStopSession() { sessionConfirm = nil }

    // MARK: - Selection & connections

    func select(_ id: PortEntry.ID?) {
        guard id != selectedID else { return }
        selectedID = id
        selectedConnections = []
        Task { await loadConnectionsForSelection() }
    }

    var selectedEntry: PortEntry? {
        guard let selectedID else { return nil }
        return entries.first { $0.id == selectedID }
    }

    private func loadConnectionsForSelection() async {
        guard let entry = selectedEntry else { selectedConnections = []; return }
        connectionsLoading = true
        let result = await connectionResolver.connections(forPort: entry.port, excludingPID: entry.pid)
        // Only apply if selection hasn't changed underneath us.
        if selectedID == entry.id {
            selectedConnections = result
            connectionsLoading = false
        }
    }

    // MARK: - Derived data

    var filteredEntries: [PortEntry] {
        var result = entries

        switch sidebarFilter {
        case .all, .allPorts:
            if hideSystem { result = result.filter { !$0.isSystem } }
        case .working:
            result = result.filter { connectionCount($0) > 0 }
        case .sessionNew:
            result = result.filter { isNewThisSession($0) && !$0.isSystem }
        case .idle:
            result = result.filter { isIdle($0) }
        case .category(let category):
            result = result.filter { $0.category == category }
        case .exposed:
            result = result.filter { $0.isExposed }
        case .aiSessions, .recentlyKilled:
            result = []
        }

        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        if !query.isEmpty {
            result = result.filter { matchesSearch($0, query) }
        }

        return result.sorted(by: comparator)
    }

    private func matchesSearch(_ entry: PortEntry, _ query: String) -> Bool {
        entry.command.lowercased().contains(query)
        || entry.title.lowercased().contains(query)
        || (entry.framework?.name.lowercased().contains(query) ?? false)
        || (entry.projectName?.lowercased().contains(query) ?? false)
        || (entry.fullCommand?.lowercased().contains(query) ?? false)
        || String(entry.port).contains(query)
        || String(entry.pid).contains(query)
        || entry.addresses.contains { $0.lowercased().contains(query) }
    }

    // MARK: - Popover-scoped data (independent of the sidebar facet)

    /// Non-system, search-filtered, project-grouped — the popover's world.
    var popoverGroups: [PortGroup] {
        var result = entries.filter { !$0.isSystem }
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        if !query.isEmpty { result = result.filter { matchesSearch($0, query) } }
        result.sort { a, b in
            let pa = a.projectName ?? "~~~", pb = b.projectName ?? "~~~"
            if pa != pb { return pa.localizedCaseInsensitiveCompare(pb) == .orderedAscending }
            return a.port < b.port
        }

        var buckets: [String: [PortEntry]] = [:]
        var order: [String] = []
        for entry in result {
            let key = entry.workingDirectory.flatMap { $0.isEmpty ? nil : $0 } ?? "__unknown__"
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(entry)
        }
        return order.compactMap { key in
            guard let bucket = buckets[key] else { return nil }
            let title = bucket.first?.projectName ?? "Unknown location"
            return PortGroup(id: key, title: title, subtitle: nil, symbol: "folder.fill", isSystemBucket: false, entries: bucket)
        }
    }

    /// First killable entry in the popover — the target for Return / ⌘K.
    var popoverTopMatch: PortEntry? {
        popoverGroups.flatMap(\.entries).first { canKill($0) }
    }

    var systemHiddenCount: Int { entries.filter { $0.isSystem }.count }

    private var comparator: (PortEntry, PortEntry) -> Bool {
        switch sort {
        case .project:
            return { a, b in
                let pa = a.projectName ?? "~~~", pb = b.projectName ?? "~~~"
                if pa != pb { return pa.localizedCaseInsensitiveCompare(pb) == .orderedAscending }
                return a.port < b.port
            }
        case .port:
            return { $0.port < $1.port }
        case .started:
            return { ($0.startDate ?? .distantPast) > ($1.startDate ?? .distantPast) }
        case .process:
            return { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        }
    }

    var groups: [PortGroup] {
        let items = filteredEntries
        switch grouping {
        case .none:
            return [PortGroup(id: "all", title: "All Ports", subtitle: nil, symbol: "list.bullet", isSystemBucket: false, entries: items)]

        case .project:
            var buckets: [String: [PortEntry]] = [:]
            var order: [String] = []
            for entry in items {
                let key = groupKey(for: entry)
                if buckets[key] == nil { order.append(key) }
                buckets[key, default: []].append(entry)
            }
            var groups = order.compactMap { key -> PortGroup? in
                guard let bucket = buckets[key] else { return nil }
                let sample = bucket.first
                let isSystemBucket = (key == "__system__")
                let title: String
                let subtitle: String?
                if isSystemBucket {
                    title = "System & Apple"; subtitle = nil
                } else if key == "__unknown__" {
                    title = "Unknown location"; subtitle = "cwd could not be resolved"
                } else {
                    title = sample?.projectName ?? "Unknown"
                    subtitle = abbreviate(key)
                }
                return PortGroup(id: key, title: title, subtitle: subtitle, symbol: isSystemBucket ? "gearshape.fill" : "folder.fill", isSystemBucket: isSystemBucket, entries: bucket)
            }
            // System bucket always sinks to the bottom.
            groups.sort { a, b in
                if a.isSystemBucket != b.isSystemBucket { return !a.isSystemBucket }
                return false
            }
            return groups

        case .category:
            var buckets: [ProcessCategory: [PortEntry]] = [:]
            for entry in items { buckets[entry.category, default: []].append(entry) }
            return ProcessCategory.allCases.compactMap { category in
                guard let bucket = buckets[category], !bucket.isEmpty else { return nil }
                return PortGroup(id: category.rawValue, title: category.rawValue, subtitle: nil, symbol: category.symbol, isSystemBucket: category == .system, entries: bucket)
            }
        }
    }

    private func groupKey(for entry: PortEntry) -> String {
        if entry.isSystem { return "__system__" }
        guard let wd = entry.workingDirectory, !wd.isEmpty else { return "__unknown__" }
        return wd
    }

    // Sidebar counts (respect nothing but category membership).
    func count(for filter: SidebarFilter) -> Int {
        switch filter {
        case .recentlyKilled: return killedHistory.count
        case .aiSessions: return liveSessions.count + visiblePorts.filter { $0.category == .aiTool }.count
        case .allPorts: return visiblePorts.count
        case .all: return visiblePorts.count + liveSessions.count
        case .working: return visiblePorts.filter { portIsWorking($0) }.count + liveSessions.filter { sessionIsWorking($0) }.count
        case .idle: return visiblePorts.filter { isIdle($0) }.count + liveSessions.filter { sessionIsIdle($0) }.count
        case .sessionNew: return visiblePorts.filter { isNewThisSession($0) }.count + liveSessions.filter { isNewThisSession(id: $0.id) }.count
        case .exposed: return visiblePorts.filter { $0.isExposed }.count
        case .category(let c): return visiblePorts.filter { $0.category == c }.count
        }
    }

    var localCount: Int { filteredEntries.filter { !$0.isExposed }.count }
    var exposedCount: Int { entries.filter { $0.isExposed && !$0.isSystem }.count }
    var totalListening: Int { entries.count }

    // MARK: - Row lifecycle helpers (for views)

    func isPending(_ entry: PortEntry) -> Bool { pendingKill?.entry.id == entry.id }
    func isTerminating(_ entry: PortEntry) -> Bool { terminatingPIDs.contains(entry.pid) }
    func isStubborn(_ entry: PortEntry) -> Bool { stubbornPIDs.contains(entry.pid) }
    func canKill(_ entry: PortEntry) -> Bool { !entry.isSystem && entry.ownedByCurrentUser }

    // MARK: - Kill flow

    private func requiresNamedConfirm(_ entry: PortEntry, force: Bool) -> Bool {
        force || entry.category == .database || entry.isExposed
    }

    /// Entry point for a single kill request from any surface.
    func requestKill(_ entry: PortEntry, force: Bool = false) {
        guard canKill(entry) else {
            errorToast = ErrorToast(text: "\(entry.title) is managed by macOS and can't be terminated here.")
            return
        }
        if requiresNamedConfirm(entry, force: force) {
            killConfirm = makeConfirm(for: [entry], force: force)
        } else {
            beginDeferredKill(entry)
        }
    }

    func requestKillGroup(_ group: PortGroup) {
        let victims = group.entries.filter { canKill($0) }
        guard !victims.isEmpty else { return }
        killConfirm = makeConfirm(for: victims, force: false, groupTitle: group.title)
    }

    /// Reap an arbitrary set (session-new, idle, …) behind one named confirmation.
    func requestReap(_ entries: [PortEntry], label: String) {
        let victims = entries.filter { canKill($0) }
        guard !victims.isEmpty else { return }
        let shown = victims.prefix(12).map { "• \($0.title) :\($0.port)" }.joined(separator: "\n")
        let more = victims.count > 12 ? "\n…and \(victims.count - 12) more" : ""
        killConfirm = KillConfirmRequest(
            entries: victims, force: false,
            title: "Stop \(victims.count) \(victims.count == 1 ? "server" : "servers") \(label)?",
            message: "This will terminate:\n\(shown)\(more)\n\nUnsaved work may be lost.",
            confirmLabel: "Stop \(victims.count)"
        )
    }

    func reapSession() { requestReap(newThisSessionEntries, label: "started this session") }
    func reapIdle() { requestReap(idleEntries, label: "that look idle") }

    /// Who is holding a given port (for the Free-a-Port flow).
    func holders(ofPort port: Int) -> [PortEntry] {
        entries.filter { $0.port == port }
    }

    private func makeConfirm(for entries: [PortEntry], force: Bool, groupTitle: String? = nil) -> KillConfirmRequest {
        let verb = force ? "Force kill" : "Kill"
        if let groupTitle {
            let list = entries.map { "• \($0.title) :\($0.port)" }.joined(separator: "\n")
            return KillConfirmRequest(
                entries: entries, force: force,
                title: "\(verb) \(entries.count) processes in \(groupTitle)?",
                message: "This will terminate:\n\(list)\n\nUnsaved work may be lost.",
                confirmLabel: "\(verb) All"
            )
        }
        let entry = entries[0]
        let where_ = entry.projectName.map { " in \($0)" } ?? ""
        var reason = ""
        if entry.category == .database { reason = "This is a database — open connections and unsaved transactions may be lost. " }
        else if entry.isExposed { reason = "This port is reachable from your network. " }
        return KillConfirmRequest(
            entries: entries, force: force,
            title: "\(verb) \(entry.title) on :\(entry.port)\(where_)?",
            message: reason + (force ? "Force kill (SIGKILL) stops it immediately without cleanup." : "The process will be asked to stop (SIGTERM)."),
            confirmLabel: verb
        )
    }

    func confirmPendingConfirmation() {
        guard let request = killConfirm else { return }
        killConfirm = nil
        executeKill(request.entries, force: request.force)
    }

    func cancelConfirmation() { killConfirm = nil }

    // Deferred graceful kill with a true Undo window.
    private func beginDeferredKill(_ entry: PortEntry) {
        // Committing any previous pending kill first keeps behavior predictable.
        commitPendingKillImmediately()

        pendingKill = PendingKill(entry: entry, secondsRemaining: 4)
        pendingKillTask = Task { [weak self] in
            for remaining in stride(from: 3, through: 0, by: -1) {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }
                guard let self, self.pendingKill?.entry.id == entry.id else { return }
                self.pendingKill?.secondsRemaining = remaining
            }
            if Task.isCancelled { return }
            guard let self, self.pendingKill?.entry.id == entry.id else { return }
            self.pendingKill = nil
            self.executeKill([entry], force: false)
        }
    }

    func undoPendingKill() {
        pendingKillTask?.cancel(); pendingKillTask = nil
        pendingKill = nil
    }

    private func commitPendingKillImmediately() {
        guard let pending = pendingKill else { return }
        pendingKillTask?.cancel(); pendingKillTask = nil
        pendingKill = nil
        executeKill([pending.entry], force: false)
    }

    private func executeKill(_ requested: [PortEntry], force: Bool) {
        // Re-validate against the live scan before sending any signal: a PID
        // captured when the dialog/undo-window opened may have exited and been
        // recycled onto a different process. id is "pid-port", so an id match
        // confirms the same process still owns the same port.
        let liveByID = Dictionary(entries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let victims = requested.compactMap { liveByID[$0.id] }
        guard !victims.isEmpty else {
            errorToast = ErrorToast(text: requested.count == 1 ? "\(requested[0].title) is no longer running." : "Those processes are no longer running.")
            return
        }
        for entry in victims {
            let outcome = ProcessKiller.terminate(pid: entry.pid, force: force)
            switch outcome {
            case .success:
                terminatingPIDs.insert(entry.pid)
                recordKill(entry)
                scheduleStubbornCheck(for: entry, alreadyForced: force)
            case .noSuchProcess:
                recordKill(entry) // it's gone; the next poll drops the row
            case .notPermitted:
                errorToast = ErrorToast(text: "\(entry.title) requires admin rights to terminate.")
            case .failure(let code):
                errorToast = ErrorToast(text: "Couldn't terminate \(entry.title) (error \(code)).")
            }
        }
        Task { await refresh() }
    }

    private func scheduleStubbornCheck(for entry: PortEntry, alreadyForced: Bool) {
        guard !alreadyForced else { return }
        stubbornTasks[entry.pid]?.cancel()
        stubbornTasks[entry.pid] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if Task.isCancelled { return }
            guard let self else { return }
            if self.entries.contains(where: { $0.pid == entry.pid }) {
                self.stubbornPIDs.insert(entry.pid)
            }
            self.stubbornTasks[entry.pid] = nil
        }
    }

    private func recordKill(_ entry: PortEntry) {
        killedHistory.insert(
            KilledRecord(title: entry.title, port: entry.port, projectName: entry.projectName, fullCommand: entry.fullCommand, workingDirectory: entry.workingDirectory, killedAt: Date()),
            at: 0
        )
        if killedHistory.count > 30 { killedHistory.removeLast(killedHistory.count - 30) }
    }

    // MARK: - Utility actions

    func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func revealInFinder(_ path: String) {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
    }

    func openInBrowser(_ entry: PortEntry) {
        guard let url = entry.browserURL else { return }
        NSWorkspace.shared.open(url)
    }

    func openMainWindow() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func abbreviate(_ path: String) -> String {
        let home = NSHomeDirectory()
        if path.hasPrefix(home) { return "~" + path.dropFirst(home.count) }
        return path
    }
}
