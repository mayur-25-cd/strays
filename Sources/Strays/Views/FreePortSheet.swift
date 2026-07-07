import SwiftUI

/// "Something's already on :3000" — type a port, see who holds it, stop it.
struct FreePortSheet: View {
    @Environment(PortStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var portText = ""
    @FocusState private var focused: Bool

    private var port: Int? {
        guard let value = Int(portText.trimmingCharacters(in: .whitespaces)), (1...65535).contains(value) else { return nil }
        return value
    }
    private var holders: [PortEntry] { port.map { store.holders(ofPort: $0) } ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "bolt.horizontal.circle.fill")
                    .font(.system(size: 17))
                    .foregroundStyle(Color.accentColor)
                Text("Free a Port").font(.system(size: 15, weight: .semibold))
                Spacer()
            }
            Text("Enter a port to see what's holding it — and stop it.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            HStack(spacing: 7) {
                Image(systemName: "number").foregroundStyle(.secondary)
                TextField("e.g. 3000", text: $portText)
                    .textFieldStyle(.plain)
                    .font(Theme.mono(14))
                    .focused($focused)
            }
            .padding(10)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.hairline, lineWidth: 1))

            result

            Spacer(minLength: 0)
            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 400, height: 340)
        .onAppear { focused = true }
    }

    @ViewBuilder private var result: some View {
        if portText.isEmpty {
            Spacer(minLength: 0)
        } else if port == nil {
            Label("Enter a valid port (1–65535).", systemImage: "exclamationmark.circle")
                .font(.system(size: 12)).foregroundStyle(.secondary)
        } else if holders.isEmpty {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.local)
                Text("Port \(port!) is free").font(.system(size: 13, weight: .medium))
            }
            .padding(.vertical, 4)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("HELD BY").font(.system(size: 10, weight: .semibold)).tracking(0.5).foregroundStyle(.secondary)
                ForEach(holders) { entry in
                    HStack(spacing: 10) {
                        CategoryGlyph(entry: entry, size: 14)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(entry.title).font(.system(size: 13, weight: .medium))
                            Text(entry.projectName ?? "PID \(String(entry.pid))")
                                .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        if store.isTerminating(entry) {
                            Text("Stopping…").font(.system(size: 11)).foregroundStyle(.secondary)
                        } else if store.canKill(entry) {
                            KillPill(label: "Stop", systemImage: "xmark.circle.fill") { store.requestKill(entry) }
                        } else {
                            Image(systemName: "lock.fill").font(.system(size: 10)).foregroundStyle(.tertiary)
                                .help("Managed by macOS")
                        }
                    }
                    .padding(10)
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }
}
