import SwiftUI

/// The honest Undo: a graceful kill is *scheduled*, not yet sent. This toast
/// counts down the window during which Undo cancels it before any signal fires.
struct UndoToastView: View {
    @Environment(PortStore.self) private var store

    var body: some View {
        if let pending = store.pendingKill {
            HStack(spacing: 12) {
                ProgressView().controlSize(.small).scaleEffect(0.8)
                Text("Stopping \(pending.entry.title) :\(String(pending.entry.port))")
                    .font(.system(size: 12, weight: .medium))
                Text("\(pending.secondsRemaining)s")
                    .font(Theme.mono(11)).monospacedDigit().foregroundStyle(.secondary)
                Divider().frame(height: 16)
                Button("Undo") { store.undoPendingKill() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
            .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
            .padding(.bottom, 18)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: store.pendingKill)
        }
    }
}

struct ErrorToastView: View {
    @Environment(PortStore.self) private var store

    var body: some View {
        Group {
            if let toast = store.errorToast {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.exposed)
                    Text(toast.text).font(.system(size: 12, weight: .medium))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
                .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
                .padding(.bottom, 18)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .task(id: toast.id) {
                    try? await Task.sleep(nanoseconds: 3_500_000_000)
                    if store.errorToast?.id == toast.id { store.errorToast = nil }
                }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: store.errorToast)
    }
}

struct RecentlyKilledView: View {
    @Environment(PortStore.self) private var store

    var body: some View {
        if store.killedHistory.isEmpty {
            EmptyStateView(message: "Nothing killed yet", detail: "Terminated ports will appear here for this session.")
        } else {
            List {
                ForEach(store.killedHistory) { record in
                    HStack(spacing: 10) {
                        Image(systemName: "clock.arrow.circlepath")
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 5) {
                                Text(record.title).font(.system(size: 13, weight: .medium))
                                Text(":\(String(record.port))").font(Theme.mono(12)).foregroundStyle(.secondary)
                            }
                            HStack(spacing: 6) {
                                if let project = record.projectName {
                                    Text(project)
                                    Text("·")
                                }
                                Text(record.killedAt.formatted(date: .omitted, time: .standard))
                            }
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let full = record.fullCommand {
                            IconButton(systemImage: "doc.on.doc", help: "Copy launch command") {
                                store.copyToClipboard(full)
                            }
                        }
                    }
                    .padding(.vertical, 3)
                }
            }
            .listStyle(.inset)
        }
    }
}
