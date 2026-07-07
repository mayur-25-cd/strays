import SwiftUI

struct PortRow: View {
    let entry: PortEntry
    var inPopover = false
    var hoverHighlight = false   // popover draws its own hover bg; List/Table don't

    @Environment(PortStore.self) private var store
    @State private var hovering = false

    private var portFontSize: CGFloat { inPopover ? 15 : 13 }

    var body: some View {
        HStack(spacing: 10) {
            CategoryGlyph(entry: entry, size: inPopover ? 15 : 14)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(entry.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(entry.isSystem ? Color.secondary : Color.primary)
                        .lineLimit(1)
                    Text(":\(String(entry.port))")
                        .font(Theme.mono(portFontSize, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(entry.isSystem ? Color.secondary : Color.primary)
                    if store.isRecentlyBorn(entry) {
                        Text("NEW")
                            .font(.system(size: 8, weight: .bold))
                            .tracking(0.3)
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.accentColor.opacity(0.15), in: Capsule())
                            .transition(.opacity)
                    }
                }
                subtitle
            }

            Spacer(minLength: 8)

            trailing
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: rowHeight)
        .opacity(store.isPending(entry) ? 0.55 : 1)
        .contentShape(Rectangle())
        .background(hoverHighlight && hovering ? Color.primary.opacity(0.06) : Color.clear)
        .onHover { hovering = $0 }
        .animation(.easeInOut(duration: 0.15), value: hovering)
    }

    private var rowHeight: CGFloat {
        inPopover ? 40 : store.density.rowHeight
    }

    @ViewBuilder private var subtitle: some View {
        HStack(spacing: 6) {
            Text("PID \(String(entry.pid))")
                .monospacedDigit()
            if let uptime = entry.uptimeString(reference: store.now) {
                Text("·")
                Text(uptime).monospacedDigit()
            }
            if inPopover, let project = entry.projectName {
                Text("·")
                Text(project).lineLimit(1)
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
    }

    @ViewBuilder private var trailing: some View {
        HStack(spacing: 8) {
            actions
            ExposureIndicator(entry: entry)
                .frame(width: 18, alignment: .center)
        }
    }

    @ViewBuilder private var actions: some View {
        if store.isTerminating(entry) {
            if store.isStubborn(entry) {
                KillPill(label: "Force", systemImage: "xmark.octagon.fill") {
                    store.requestKill(entry, force: true)
                }
            } else {
                HStack(spacing: 5) {
                    ProgressView().controlSize(.small).scaleEffect(0.7)
                    Text("Stopping…").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
        } else if store.isPending(entry) {
            Text("Stopping…").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
        } else if hovering {
            HStack(spacing: 6) {
                if entry.isBrowsable {
                    IconButton(systemImage: "safari", help: "Open http://localhost:\(entry.port)") {
                        store.openInBrowser(entry)
                    }
                }
                if store.canKill(entry) {
                    KillPill(label: "Kill", systemImage: "xmark.circle.fill") {
                        store.requestKill(entry)
                    }
                } else {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .help(entry.ownedByCurrentUser ? "Managed by macOS" : "Owned by another user — requires admin")
                }
            }
            .transition(.opacity.combined(with: .move(edge: .trailing)))
        }
    }
}

/// The destructive kill affordance — red is used ONLY here.
struct KillPill: View {
    let label: String
    let systemImage: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: systemImage).font(.system(size: 10, weight: .semibold))
                Text(label).font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(Theme.destructive)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Theme.destructive.opacity(hovering ? 0.22 : 0.13), in: Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

struct IconButton: View {
    let systemImage: String
    var help: String = ""
    let action: () -> Void
    @State private var hovering = false
    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(hovering ? Color.primary : Color.secondary)
                .padding(4)
                .background(hovering ? Color.primary.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}
