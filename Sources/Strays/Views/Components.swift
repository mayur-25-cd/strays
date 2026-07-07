import SwiftUI

/// Wraps NSVisualEffectView so the menu-bar popover reads as first-class system UI.
struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .menu
    var blending: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blending
        view.state = .active
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blending
    }
}

/// Fixed-width leading category icon — creates the clean vertical alignment seam.
struct CategoryGlyph: View {
    let entry: PortEntry
    var size: CGFloat = 15

    var body: some View {
        Image(systemName: entry.symbol)
            .font(.system(size: size, weight: .medium))
            .foregroundStyle(entry.isSystem ? Color.secondary : entry.category.tint)
            .symbolRenderingMode(.hierarchical)
            .frame(width: 22, alignment: .center)
    }
}

/// Trailing exposure indicator. System processes get a hollow "hands off" ring
/// (form, not just color — colorblind-safe); others get a filled dot + symbol.
struct ExposureIndicator: View {
    let entry: PortEntry
    var showLabel = false

    var body: some View {
        if entry.isSystem {
            Circle()
                .strokeBorder(Theme.systemRing, lineWidth: 1.5)
                .frame(width: 9, height: 9)
                .help("Managed by macOS")
        } else {
            HStack(spacing: 4) {
                Image(systemName: entry.exposure.symbol)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(entry.exposure.tint)
                if showLabel {
                    Text(entry.exposure.shortLabel)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(entry.exposure.tint)
                }
            }
            .help(entry.exposure == .localOnly ? "Local only — reachable only from this Mac" : "Exposed — reachable from your network")
        }
    }
}

/// A small count badge used in the sidebar and group headers.
struct CountPill: View {
    let count: Int
    var tint: Color = .secondary
    var body: some View {
        Text("\(count)")
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 1.5)
            .background(tint.opacity(0.14), in: Capsule())
    }
}

/// Quiet stat chip ("6 local", "1 exposed") for the popover summary strip.
struct StatChip: View {
    let icon: String
    let text: String
    let tint: Color
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
            Text(text)
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(tint.opacity(0.12), in: Capsule())
    }
}

/// A subtle keyboard-shortcut hint chip.
struct KeyCap: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .medium, design: .rounded))
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 4))
    }
}

/// A pulsing dot that signals whether live polling is alive (or stale).
struct PulseDot: View {
    let isStale: Bool
    @State private var pulsing = false
    var body: some View {
        Circle()
            .fill(isStale ? Color.secondary : Theme.local)
            .frame(width: 6, height: 6)
            .opacity(isStale ? 0.4 : (pulsing ? 0.35 : 1))
            .animation(isStale ? .default : .easeInOut(duration: 1.1).repeatForever(autoreverses: true), value: pulsing)
            .onAppear { pulsing = true }
            .help(isStale ? "Last update failed — showing the last known state" : "Live")
    }
}

/// A calm action bar shown above the Session/Idle facets — the batch "reap".
struct ReapBanner: View {
    let icon: String
    let message: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(tint)
                .symbolRenderingMode(.hierarchical)
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.primary)
            Spacer(minLength: 8)
            Button(action: action) {
                Text("Stop All").font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.destructive)
            .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(tint.opacity(0.08))
        .overlay(alignment: .bottom) { Divider() }
    }
}

/// Small pill used in the inspector to convey a port's status at a glance.
struct InspectorTag: View {
    let icon: String
    let text: String
    let tint: Color
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 9, weight: .semibold))
            Text(text).font(.system(size: 10, weight: .medium))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(tint.opacity(0.12), in: Capsule())
    }
}

/// Friendly empty state — never a blank void.
struct EmptyStateView: View {
    let message: String
    var detail: String? = nil
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "powerplug")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.tertiary)
            Text(message)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
            if let detail {
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}
