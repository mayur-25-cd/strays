import SwiftUI

struct SidebarView: View {
    @Environment(PortStore.self) private var store

    // AI tools live under the top-level "AI" facet, not in Types.
    private let categoryOrder: [ProcessCategory] = [.devServer, .database, .docker, .editor, .other]

    var body: some View {
        @Bindable var store = store

        List(selection: Binding(get: { store.sidebarFilter }, set: { store.sidebarFilter = $0 ?? .all })) {
            Section {
                facetRow(.all, title: "All", symbol: "square.grid.2x2.fill", tint: .accentColor)
                facetRow(.aiSessions, title: "AI", symbol: "sparkles", tint: Theme.ai)
                facetRow(.allPorts, title: "All Ports", symbol: "powerplug.fill", tint: .accentColor)
            }

            Section("Types") {
                ForEach(categoryOrder, id: \.self) { category in
                    if store.count(for: .category(category)) > 0 {
                        facetRow(.category(category), title: category.rawValue, symbol: category.symbol, tint: category.tint)
                    }
                }
            }

            Section("Right Now") {
                facetRow(.working, title: "Working", symbol: "bolt.fill", tint: Theme.local)
                facetRow(.idle, title: "Idle / Forgotten", symbol: "moon.zzz.fill", tint: .secondary)
            }

            Section("Watch") {
                facetRow(.sessionNew, title: "Started This Session", symbol: "plus.circle.fill", tint: .accentColor)
                facetRow(.exposed, title: "Exposed to Network", symbol: "exclamationmark.shield.fill", tint: Theme.exposed)
                facetRow(.recentlyKilled, title: "Recently Killed", symbol: "clock.arrow.circlepath", tint: .secondary)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                Divider()
                Toggle(isOn: $store.hideSystem) {
                    Text("Hide System & Apple").font(.system(size: 12))
                }
                .toggleStyle(.switch)
                .controlSize(.mini)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
            }
            .background(.bar)
        }
    }

    @ViewBuilder
    private func facetRow(_ filter: SidebarFilter, title: String, symbol: String, tint: Color) -> some View {
        let count = store.count(for: filter)
        Label {
            HStack {
                Text(title).font(.system(size: 13))
                Spacer()
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 11, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .symbolRenderingMode(.hierarchical)
        }
        .tag(filter)
    }
}
