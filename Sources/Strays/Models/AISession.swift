import Foundation

/// Which entity types the main view is showing — the "just show me ports" switch.
enum EntityScope: String, CaseIterable, Identifiable {
    case all = "All"
    case ports = "Ports"
    case ai = "AI"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .ports: return "powerplug"
        case .ai: return "sparkles"
        }
    }
}

enum AITool: String, Sendable {
    case claudeCode = "Claude Code"
    case copilotCLI = "Copilot CLI"
    case codex = "Codex"
    case antigravity = "Gemini Antigravity"
    case cursor = "Cursor"
    case cline = "Cline"
    case other = "AI Tool"

    var symbol: String {
        switch self {
        case .claudeCode: return "sparkle"
        case .copilotCLI: return "chevron.left.forwardslash.chevron.right"
        case .codex: return "curlybraces"
        case .antigravity: return "circle.hexagongrid.fill"
        case .cursor: return "cursorarrow.rays"
        case .cline: return "terminal"
        case .other: return "brain"
        }
    }
}

/// A running AI coding session, discovered from a tool's local session/lock files
/// and proven live by cross-checking the process start time.
struct AISession: Identifiable, Sendable {
    let tool: AITool
    let sessionKey: String        // sessionId / lock uuid / pid — unique per session
    let pid: Int32?
    let workingDirectory: String?
    let model: String?
    let isLive: Bool
    let startedAt: Date?
    let lastActivity: Date?
    let messageCount: Int?
    let inputTokens: Int?
    let outputTokens: Int?
    let cachedTokens: Int?
    let estimatedCostUSD: Double?
    let gitBranch: String?

    var id: String { "session-\(tool.rawValue)-\(sessionKey)" }

    var title: String { tool.rawValue }

    var projectName: String? {
        guard let workingDirectory, !workingDirectory.isEmpty, workingDirectory != "/" else { return nil }
        let name = URL(fileURLWithPath: workingDirectory).lastPathComponent
        return name.isEmpty ? nil : name
    }

    var ownedByCurrentUser: Bool { true }   // these files are the current user's
    var canStop: Bool { pid != nil }

    var modelShort: String? {
        guard let model else { return nil }
        // "claude-opus-4-8" → "opus-4-8"; keep others as-is but trimmed.
        if let range = model.range(of: "claude-") { return String(model[range.upperBound...]) }
        return model
    }

    var costString: String? {
        guard let cost = estimatedCostUSD, cost > 0 else { return nil }
        if cost < 0.01 { return "≈ <¢1" }
        if cost < 1 { return String(format: "≈ %.0f¢", cost * 100) }
        return String(format: "≈ $%.2f", cost)
    }

    static func fmtTokens(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.0fk", Double(n) / 1_000) }
        return "\(n)"
    }

    var tokenString: String? {
        guard let inp = inputTokens, let out = outputTokens, inp + out > 0 else { return nil }
        return "\(AISession.fmtTokens(inp)) in · \(AISession.fmtTokens(out)) out"
    }

    var cacheString: String? {
        guard let c = cachedTokens, c > 0 else { return nil }
        return AISession.fmtTokens(c)
    }
}

/// A project bucket in the unified view — its AI sessions and its ports together.
struct ProjectGroup: Identifiable {
    let id: String
    let title: String
    let subtitle: String?
    let symbol: String
    let isSystemBucket: Bool
    let items: [RowItem]

    var sessionCount: Int { items.filter { $0.isSession }.count }
    var portCount: Int { items.filter { !$0.isSession }.count }
}

/// A unified row in the project-grouped view: either a listening port or an AI session.
enum RowItem: Identifiable {
    case port(PortEntry)
    case session(AISession)

    var id: String {
        switch self {
        case .port(let p): return p.id
        case .session(let s): return s.id
        }
    }
    var projectDirectory: String? {
        switch self {
        case .port(let p): return p.isSystem ? nil : p.workingDirectory
        case .session(let s): return s.workingDirectory
        }
    }
    var projectName: String? {
        switch self {
        case .port(let p): return p.projectName
        case .session(let s): return s.projectName
        }
    }
    var startDate: Date? {
        switch self {
        case .port(let p): return p.startDate
        case .session(let s): return s.startedAt
        }
    }
    var isSession: Bool { if case .session = self { return true }; return false }
    var isSystem: Bool { if case .port(let p) = self { return p.isSystem }; return false }
}
