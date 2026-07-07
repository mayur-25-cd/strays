import Foundation

// MARK: - View-facing controls

enum SortOption: String, CaseIterable, Identifiable {
    case project = "Project"
    case port = "Port"
    case started = "Recently started"
    case process = "Name"
    var id: String { rawValue }
}

enum GroupOption: String, CaseIterable, Identifiable {
    case project = "Project"
    case category = "Type"
    case none = "Flat"
    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .project: return "folder"
        case .category: return "square.stack.3d.up"
        case .none: return "list.bullet"
        }
    }
}

enum RowDensity: String, CaseIterable, Identifiable {
    case comfortable = "Comfortable"
    case compact = "Compact"
    var id: String { rawValue }
    var rowHeight: CGFloat { self == .comfortable ? 46 : 32 }
}

/// Sidebar facets that scope the content list.
enum SidebarFilter: Hashable {
    case all
    case aiSessions
    case allPorts
    case working
    case sessionNew
    case idle
    case category(ProcessCategory)
    case exposed
    case recentlyKilled
}

// MARK: - PortEntry — one listening port on one process (the row identity)

/// A single row in the UI: one process (PID) listening on one port. IPv4 and
/// IPv6 bindings of the same PID+port are collapsed into one entry.
struct PortEntry: Identifiable, Hashable {
    let pid: Int32
    let port: Int
    let command: String
    let user: String
    let networkProtocol: String
    let families: Set<NetFamily>
    let addresses: [String]

    let fullCommand: String?
    let workingDirectory: String?
    let startDate: Date?
    let cpuPercent: Double?
    let memoryKB: Int?
    let category: ProcessCategory
    let framework: DetectedFramework?

    /// Stable identity — SwiftUI diffs in place so live updates never flash.
    var id: String { "\(pid)-\(port)" }

    var memoryMB: Double? { memoryKB.map { Double($0) / 1024 } }

    var memoryString: String? {
        guard let mb = memoryMB else { return nil }
        if mb >= 1024 { return String(format: "%.1f GB", mb / 1024) }
        return String(format: "%.0f MB", mb)
    }

    var cpuString: String? {
        guard let cpu = cpuPercent else { return nil }
        return String(format: "%.0f%%", cpu)
    }

    /// A process that has been up a while and eats CPU is worth a glance.
    var isBusy: Bool { (cpuPercent ?? 0) >= 25 }

    var exposure: Exposure {
        var result: Exposure = .localOnly
        for address in addresses {
            let e = PortBinding(port: port, address: address, family: .other, networkProtocol: networkProtocol).exposure
            if e == .allInterfaces { return .allInterfaces }
            if e == .specific { result = .specific }
        }
        return result
    }

    var isExposed: Bool { exposure != .localOnly }

    var title: String { framework?.name ?? prettyCommand }

    /// Cleans lsof's short command (e.g. "Code\x20H" is already decoded upstream).
    private var prettyCommand: String {
        command == "Python" ? "Python" : command
    }

    var symbol: String { framework?.symbol ?? category.symbol }

    var projectName: String? {
        guard let workingDirectory, !workingDirectory.isEmpty, workingDirectory != "/" else { return nil }
        let name = URL(fileURLWithPath: workingDirectory).lastPathComponent
        return name.isEmpty ? nil : name
    }

    var isSystem: Bool {
        if category == .system { return true }
        // AI tools / dev servers / databases launched from "/" are still real — never hide them.
        if category == .aiTool || category == .devServer || category == .database { return false }
        if let wd = workingDirectory, wd == "/" { return true }
        return false
    }

    var ownedByCurrentUser: Bool { user == NSUserName() }

    var familyLabel: String {
        let hasV4 = families.contains(.ipv4)
        let hasV6 = families.contains(.ipv6)
        switch (hasV4, hasV6) {
        case (true, true): return "IPv4 + IPv6"
        case (true, false): return "IPv4"
        case (false, true): return "IPv6"
        default: return "—"
        }
    }

    /// The most representative bind address for compact display.
    var primaryAddress: String {
        if addresses.contains("*") { return "0.0.0.0" }
        if let specific = addresses.first(where: { $0 != "127.0.0.1" && $0 != "::1" && $0 != "[::1]" }) {
            return specific
        }
        return addresses.first ?? "—"
    }

    /// http(s)-reachable dev servers get an "open in browser" affordance.
    var isBrowsable: Bool {
        category == .devServer && !isSystem
    }

    var browserURL: URL? {
        guard isBrowsable else { return nil }
        return URL(string: "http://localhost:\(port)")
    }

    func uptimeString(reference: Date = Date()) -> String? {
        guard let startDate else { return nil }
        let seconds = max(0, Int(reference.timeIntervalSince(startDate)))
        return PortEntry.humanize(seconds)
    }

    static func humanize(_ seconds: Int) -> String {
        if seconds < 60 { return "up \(seconds)s" }
        let minutes = seconds / 60
        if minutes < 60 { return "up \(minutes)m" }
        let hours = minutes / 60
        let remMinutes = minutes % 60
        if hours < 24 { return remMinutes > 0 ? "up \(hours)h \(remMinutes)m" : "up \(hours)h" }
        let days = hours / 24
        let remHours = hours % 24
        return remHours > 0 ? "up \(days)d \(remHours)h" : "up \(days)d"
    }

    var killCommand: String { "kill -9 \(pid)" }

    // MARK: Build entries from PID-grouped scan output

    static func flatten(_ processes: [ListeningProcess]) -> [PortEntry] {
        var result: [PortEntry] = []
        for process in processes {
            let byPort = Dictionary(grouping: process.bindings, by: { $0.port })
            for (port, binds) in byPort {
                let families = Set(binds.map { $0.family })
                let addresses = Array(Set(binds.map { $0.address })).sorted()
                result.append(
                    PortEntry(
                        pid: process.pid,
                        port: port,
                        command: process.command,
                        user: process.user,
                        networkProtocol: binds.first?.networkProtocol ?? "TCP",
                        families: families,
                        addresses: addresses,
                        fullCommand: process.fullCommand,
                        workingDirectory: process.workingDirectory,
                        startDate: process.startDate,
                        cpuPercent: process.cpuPercent,
                        memoryKB: process.memoryKB,
                        category: process.category,
                        framework: process.framework
                    )
                )
            }
        }
        return result
    }
}

// MARK: - Grouping

struct PortGroup: Identifiable {
    let id: String
    let title: String
    let subtitle: String?
    let symbol: String
    let isSystemBucket: Bool
    let entries: [PortEntry]

    var killableCount: Int {
        entries.filter { !$0.isSystem && $0.ownedByCurrentUser }.count
    }
}

// MARK: - Kill history

struct KilledRecord: Identifiable {
    let id = UUID()
    let title: String
    let port: Int
    let projectName: String?
    let fullCommand: String?
    let workingDirectory: String?
    let killedAt: Date
}
