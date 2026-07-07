import AppKit
import SwiftUI

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

extension Color {
    init(hex: UInt32) {
        self = Color(nsColor: NSColor(hex: hex))
    }

    /// A color that resolves differently in light vs dark appearance.
    static func dynamic(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        })
    }
}

/// Semantic palette. Neutrals carry ~95% of the UI; these colors encode
/// *meaning* only (exposure, category, destructive action) — never decoration.
enum Theme {
    // Exposure
    static let local = Color.dynamic(0x5B9AA0, 0x6FB4BA)       // teal — private
    static let exposed = Color.dynamic(0xC7841E, 0xE0A542)     // amber — caution
    static let systemRing = Color(hex: 0x8E8E93)               // hollow "hands off" ring

    // Destructive — reserved SOLELY for kill affordances
    static let destructive = Color.dynamic(0xE0322A, 0xFF453A)

    /// AI / agent accent — reserved for AI coding tools and sessions.
    static let ai = Color.dynamic(0x7A5AF8, 0x9A82FF)

    // Category glyph tints (muted so they read as labels, not alarms)
    static func category(_ category: ProcessCategory) -> Color {
        switch category {
        case .aiTool: return Theme.ai
        case .devServer: return Color(hex: 0x5E5CE6)
        case .database:  return Color(hex: 0x2C9C8E)
        case .docker:    return Color(hex: 0x2A8FD8)
        case .editor:    return Color(hex: 0x7C7C82)
        case .system:    return Color(hex: 0x98989D)
        case .other:     return Color(hex: 0x6E7681)
        }
    }

    static let hairline = Color.dynamic(0x000000, 0xFFFFFF).opacity(0.09)

    // Typography helpers
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

extension Exposure {
    var tint: Color {
        switch self {
        case .localOnly: return Theme.local
        case .allInterfaces, .specific: return Theme.exposed
        }
    }
    var symbol: String {
        switch self {
        case .localOnly: return "lock.fill"
        case .allInterfaces, .specific: return "exclamationmark.shield.fill"
        }
    }
    var shortLabel: String {
        switch self {
        case .localOnly: return "Local"
        case .allInterfaces, .specific: return "Exposed"
        }
    }
}

extension ProcessCategory {
    var tint: Color { Theme.category(self) }
}

extension AITool {
    var tint: Color { Theme.ai }
}
