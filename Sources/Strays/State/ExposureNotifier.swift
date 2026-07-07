import Foundation
import UserNotifications

/// Posts a desktop notification the moment a port becomes reachable from the
/// network. Guards against running without a bundle (e.g. `swift run`), where
/// UNUserNotificationCenter is unavailable and would crash.
@MainActor
final class ExposureNotifier {
    static let shared = ExposureNotifier()

    private var authorizationRequested = false

    /// UNUserNotificationCenter requires a real app bundle + identifier.
    private var isAvailable: Bool { Bundle.main.bundleIdentifier != nil }

    func requestAuthorizationIfNeeded() {
        guard isAvailable, !authorizationRequested else { return }
        authorizationRequested = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func notifyNewlyExposed(_ entries: [PortEntry]) {
        guard isAvailable, !entries.isEmpty else { return }
        requestAuthorizationIfNeeded()
        let center = UNUserNotificationCenter.current()
        for entry in entries {
            let content = UNMutableNotificationContent()
            content.title = "Port exposed to your network"
            let project = entry.projectName.map { " · \($0)" } ?? ""
            content.body = "\(entry.title) :\(entry.port) is now reachable from other devices on your network\(project)."
            content.sound = .default
            let stamp = Int(Date().timeIntervalSince1970)
            let request = UNNotificationRequest(
                identifier: "exposed-\(entry.id)-\(stamp)",
                content: content,
                trigger: nil
            )
            center.add(request)
        }
    }
}
