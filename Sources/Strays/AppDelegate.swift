import AppKit
import ServiceManagement
import SwiftUI

enum SettingsKey {
    static let refreshInterval = "refreshInterval"
    static let autoRefresh = "autoRefresh"
    static let hideSystem = "hideSystem"
    static let density = "density"
    static let notifyOnExposure = "notifyOnExposure"
    static let menuBarOnly = "menuBarOnly"
    static let launchAtLogin = "launchAtLogin"
    static let idleThreshold = "idleThresholdSeconds"
}

/// Handles process-level concerns SwiftUI scenes can't: Dock-icon visibility
/// (menu-bar-only mode), launch-at-login, and notification authorization.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let defaults = UserDefaults.standard

        let menuBarOnly = defaults.object(forKey: SettingsKey.menuBarOnly) as? Bool ?? false
        AppEnvironment.applyActivationPolicy(menuBarOnly: menuBarOnly, closeExistingWindows: menuBarOnly)

        let wantsLogin = defaults.object(forKey: SettingsKey.launchAtLogin) as? Bool ?? true
        AppEnvironment.syncLaunchAtLogin(wantsLogin)

        let notify = defaults.object(forKey: SettingsKey.notifyOnExposure) as? Bool ?? true
        if notify {
            Task { @MainActor in ExposureNotifier.shared.requestAuthorizationIfNeeded() }
        }
    }

    // Keep running when the last window closes (it's a menu-bar app).
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

enum AppEnvironment {
    static func applyActivationPolicy(menuBarOnly: Bool, closeExistingWindows: Bool) {
        NSApp.setActivationPolicy(menuBarOnly ? .accessory : .regular)
        if !menuBarOnly {
            NSApp.activate(ignoringOtherApps: true)
        }
        if closeExistingWindows {
            // The Window scene may auto-open at launch; a menu-bar-only app
            // starts hidden until summoned. Retry to catch a late-created window.
            let closeMain = {
                for window in NSApp.windows where window.title == "Strays" {
                    window.close()
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: closeMain)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: closeMain)
        }
    }

    static func syncLaunchAtLogin(_ enabled: Bool) {
        let service = SMAppService.mainApp
        do {
            if enabled, service.status != .enabled {
                try service.register()
            } else if !enabled, service.status == .enabled {
                try service.unregister()
            }
        } catch {
            // Unsigned/ad-hoc local builds may not persist a login item; ignore.
        }
    }
}

/// Renders the menu-bar item: a plug glyph plus a live count of your servers,
/// filled when anything is exposed to the network. Drawn as a template image
/// so it tints correctly for light/dark menu bars.
enum MenuBarIcon {
    static func make(count: Int, exposed: Bool) -> NSImage {
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        // Fall back through candidates so the menu-bar item is never blank —
        // an invisible item would be unrecoverable in menu-bar-only mode.
        let symbol = NSImage(systemSymbolName: exposed ? "powerplug.fill" : "powerplug", accessibilityDescription: "Strays")?.withSymbolConfiguration(config)
            ?? NSImage(systemSymbolName: "bolt.horizontal.circle", accessibilityDescription: "Strays")?.withSymbolConfiguration(config)

        let text = count > 0 ? "\(count)" : ""
        let font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
        let textSize = text.isEmpty ? .zero : (text as NSString).size(withAttributes: attributes)

        let symbolSize = symbol?.size ?? .zero
        let symbolWidth = symbolSize.width > 0 ? symbolSize.width : 16
        let symbolHeight = symbolSize.height > 0 ? symbolSize.height : 16
        let gap: CGFloat = text.isEmpty ? 0 : 3
        let height: CGFloat = 18
        let width = ceil(symbolWidth + gap + textSize.width)

        let image = NSImage(size: NSSize(width: max(width, 16), height: height))
        image.lockFocus()
        symbol?.draw(in: NSRect(x: 0, y: (height - symbolHeight) / 2, width: symbolWidth, height: symbolHeight))
        if !text.isEmpty {
            (text as NSString).draw(at: NSPoint(x: symbolWidth + gap, y: (height - textSize.height) / 2), withAttributes: attributes)
        }
        image.unlockFocus()
        image.isTemplate = true
        return image
    }
}
