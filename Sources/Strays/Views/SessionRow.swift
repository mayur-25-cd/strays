import SwiftUI

struct SessionRow: View {
    let session: AISession
    var inPopover = false
    var hoverHighlight = false

    @Environment(PortStore.self) private var store
    @State private var hovering = false

    private var working: Bool { store.sessionIsWorking(session) }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: session.tool.symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(session.tool.tint)
                .symbolRenderingMode(.hierarchical)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(session.title)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                    if let model = session.modelShort {
                        Text(model)
                            .font(Theme.mono(10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                if let secondary = secondaryText {
                    Text(secondary)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, 14)
        .frame(height: inPopover ? 40 : store.density.rowHeight)
        .contentShape(Rectangle())
        .background(hoverHighlight && hovering ? Color.primary.opacity(0.06) : Color.clear)
        .onHover { hovering = $0 }
        .animation(.easeInOut(duration: 0.15), value: hovering)
    }

    /// One quiet line — activity, not a data dump. Everything else is in the inspector.
    private var secondaryText: String? {
        var parts: [String] = []
        if let last = session.lastActivity { parts.append(relativeShort(last)) }
        if let msgs = session.messageCount, msgs > 0 { parts.append("\(msgs) msgs") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    @ViewBuilder private var trailing: some View {
        if hovering, session.canStop {
            KillPill(label: "Stop", systemImage: "stop.circle.fill") {
                store.requestStopSession(session)
            }
            .transition(.opacity)
        } else {
            Circle()
                .fill(working ? Theme.local : Color.secondary.opacity(0.45))
                .frame(width: 7, height: 7)
                .frame(width: 16)
                .help(working ? "Active recently" : "Live but idle")
        }
    }

    private func relativeShort(_ date: Date) -> String {
        let s = max(0, Int(store.now.timeIntervalSince(date)))
        if s < 60 { return "\(s)s ago" }
        if s < 3600 { return "\(s / 60)m ago" }
        if s < 86400 { return "\(s / 3600)h ago" }
        return "\(s / 86400)d ago"
    }
}
