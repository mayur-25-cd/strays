import Foundation

// MARK: - Network primitives

enum NetFamily: String, Hashable, Sendable {
    case ipv4 = "IPv4"
    case ipv6 = "IPv6"
    case other = "Other"

    var shortLabel: String {
        switch self {
        case .ipv4: return "v4"
        case .ipv6: return "v6"
        case .other: return "?"
        }
    }
}

/// How reachable a bound socket is from the outside world.
enum Exposure: Sendable {
    case localOnly      // 127.0.0.1 / ::1 / localhost — only this machine
    case allInterfaces  // * / 0.0.0.0 / :: — reachable from the network
    case specific       // bound to one concrete interface IP

    var label: String {
        switch self {
        case .localOnly: return "Local only"
        case .allInterfaces: return "Exposed to network"
        case .specific: return "Bound interface"
        }
    }
}

/// A single listening socket: one port on one address/family.
struct PortBinding: Identifiable, Hashable, Sendable {
    let port: Int
    let address: String        // "127.0.0.1", "*", "[::1]"
    let family: NetFamily
    let networkProtocol: String // "TCP"

    var id: String { "\(networkProtocol)/\(family.rawValue)/\(address):\(port)" }

    var exposure: Exposure {
        switch address {
        case "*", "0.0.0.0", "::", "[::]", "[::0]":
            return .allInterfaces
        case "127.0.0.1", "::1", "[::1]", "localhost":
            return .localOnly
        default:
            // 127.x.x.x loopback range also counts as local.
            if address.hasPrefix("127.") { return .localOnly }
            return .specific
        }
    }
}

// MARK: - Process classification

enum ProcessCategory: String, CaseIterable, Sendable {
    case aiTool = "AI IDE"
    case devServer = "Dev Server"
    case database = "Database"
    case docker = "Docker"
    case editor = "Editor / IDE"
    case system = "System"
    case other = "Other"

    /// SF Symbol used to represent the category.
    var symbol: String {
        switch self {
        case .aiTool: return "sparkles"
        case .devServer: return "server.rack"
        case .database: return "cylinder.split.1x2"
        case .docker: return "shippingbox"
        case .editor: return "hammer"
        case .system: return "gearshape"
        case .other: return "app.dashed"
        }
    }
}

/// A more specific fingerprint of the tool behind a process (Vite, uvicorn, …).
struct DetectedFramework: Hashable, Sendable {
    let name: String
    let symbol: String
}

// MARK: - Listening process

/// One process (by PID) that is listening on one or more ports, enriched with
/// the launch command, working directory and start time so the user can tell
/// *what* it is and *where* it came from.
struct ListeningProcess: Identifiable, Sendable {
    let pid: Int32
    let command: String        // short name from lsof, e.g. "node", "Python"
    let user: String
    var bindings: [PortBinding]

    // Enriched (may be nil if the process vanished mid-scan or is protected).
    var fullCommand: String?
    var workingDirectory: String?
    var startDate: Date?
    var cpuPercent: Double?
    var memoryKB: Int?

    var category: ProcessCategory = .other
    var framework: DetectedFramework?

    var id: Int32 { pid }

    /// Distinct ports, ascending — what the user actually thinks in.
    var ports: [Int] {
        Array(Set(bindings.map(\.port))).sorted()
    }

    /// Folder the server was launched from — the key "where did this come from" signal.
    var projectName: String? {
        guard let workingDirectory, !workingDirectory.isEmpty else { return nil }
        let name = URL(fileURLWithPath: workingDirectory).lastPathComponent
        return name.isEmpty ? nil : name
    }

    /// True if any binding is reachable from the network (not just localhost).
    var isExposed: Bool {
        bindings.contains { $0.exposure == .allInterfaces }
    }

    /// Best human label: a framework name if we detected one, else the command.
    var title: String {
        framework?.name ?? command
    }

    var symbol: String {
        framework?.symbol ?? category.symbol
    }
}
