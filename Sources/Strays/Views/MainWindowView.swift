import SwiftUI

struct MainWindowView: View {
    @Environment(PortStore.self) private var store
    @State private var showInspector = true

    var body: some View {
        @Bindable var store = store
        splitView
            .overlay(alignment: .bottom) { UndoToastView() }
            .overlay(alignment: .bottom) { ErrorToastView() }
            .modifier(ConfirmationDialogs())
            .sheet(isPresented: $store.freePortPresented) { FreePortSheet().environment(store) }
            .task { store.start() }
    }

    private var splitView: some View {
        @Bindable var store = store
        return NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 210, max: 260)
        } detail: {
            PortListContainer()
                .inspector(isPresented: $showInspector) {
                    InspectorView()
                        .inspectorColumnWidth(min: 280, ideal: 300, max: 380)
                }
        }
        .navigationTitle("")
        .searchable(text: $store.searchText, placement: .toolbar, prompt: "Filter by port, project, command…")
        .toolbar { toolbar }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        @Bindable var store = store

        ToolbarItem(placement: .automatic) {
            Button { store.freePortPresented = true } label: {
                Label("Free a Port", systemImage: "bolt.horizontal.circle")
            }
            .help("Find and stop whatever is holding a port (⌘L)")
        }

        ToolbarItem(placement: .automatic) {
            Menu {
                Picker("Density", selection: $store.density) {
                    ForEach(RowDensity.allCases) { Text($0.rawValue).tag($0) }
                }
                Toggle("Hide System & Apple", isOn: $store.hideSystem)
            } label: {
                Label("View options", systemImage: "slider.horizontal.3")
            }
        }

        ToolbarItem(placement: .automatic) {
            HStack(spacing: 6) {
                PulseDot(isStale: store.isStale)
                Button { Task { await store.refresh() } } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh now (⌘R)")
            }
        }

        ToolbarItem(placement: .automatic) {
            Button { showInspector.toggle() } label: {
                Image(systemName: "sidebar.trailing")
            }
            .help("Toggle inspector")
        }
    }
}

/// Kept as a modifier so the main view's body stays cheap to type-check.
private struct ConfirmationDialogs: ViewModifier {
    @Environment(PortStore.self) private var store

    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                store.killConfirm?.title ?? "",
                isPresented: Binding(get: { store.killConfirm != nil }, set: { if !$0 { store.cancelConfirmation() } }),
                titleVisibility: .visible,
                presenting: store.killConfirm
            ) { request in
                Button(request.confirmLabel, role: .destructive) { store.confirmPendingConfirmation() }
                Button("Cancel", role: .cancel) { store.cancelConfirmation() }
            } message: { request in
                Text(request.message)
            }
            .confirmationDialog(
                store.sessionConfirm.map { "Stop \($0.title)?" } ?? "",
                isPresented: Binding(get: { store.sessionConfirm != nil }, set: { if !$0 { store.cancelStopSession() } }),
                titleVisibility: .visible,
                presenting: store.sessionConfirm
            ) { session in
                Button("Stop \(session.title)", role: .destructive) { store.confirmStopSession() }
                Button("Cancel", role: .cancel) { store.cancelStopSession() }
            } message: { session in
                Text("This ends the \(session.title) process\(session.projectName.map { " in \($0)" } ?? ""). Any unsaved work in that session may be lost.")
            }
    }
}
