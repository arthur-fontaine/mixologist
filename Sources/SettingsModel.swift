import AppKit
import ServiceManagement
import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case menuBarItems
    case about

    var id: Self { self }

    var title: String {
        switch self {
        case .general: "General"
        case .menuBarItems: "Menu Bar Items"
        case .about: "About"
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .menuBarItems: "menubar.rectangle"
        case .about: "info.circle"
        }
    }
}

/// One switchable row: an app, hidden by bundle identifier, or one of Apple's
/// modules, hidden through the system-item list.
struct MenuBarApp: Identifiable, Equatable {
    enum Target: Hashable {
        case bundle(String)
        case systemItem(Int)
    }

    let target: Target
    let name: String
    let detail: String
    var path: String?
    /// Apple modules have no bundle of their own to take an icon from.
    var symbol: String?
    let isHidden: Bool

    var id: Target { target }
}

/// The nine `MBSystemItemIdentifier` cases, by raw value.
private let appleModules: [Int: (name: String, symbol: String)] = [
    0: ("Battery", "battery.100percent"),
    1: ("Bluetooth", "dot.radiowaves.left.and.right"),
    2: ("Clock", "clock"),
    3: ("Display", "display"),
    4: ("Keyboard Brightness", "light.max"),
    5: ("Sound", "speaker.wave.2.fill"),
    6: ("Wi‑Fi", "wifi"),
    7: ("Control Center", "switch.2"),
    8: ("Screen Mirroring", "rectangle.on.rectangle"),
]

/// SwiftUI's view of `MXVisibilityController`, refreshed from its notifications.
@MainActor
final class SettingsModel: ObservableObject {
    @Published var tab: SettingsTab = .general
    @Published private(set) var apps: [MenuBarApp] = []
    @Published private(set) var appleItems: [MenuBarApp] = []
    @Published private(set) var accessibilityTrusted = false
    @Published private(set) var accessibilityLost = false
    @Published private(set) var apiAvailable = false
    @Published private(set) var apiUnavailableReason: String?
    @Published private(set) var status = ""
    @Published private(set) var errorMessage: String?
    @Published private(set) var revealing = false
    @Published private(set) var hiddenCount = 0
    @Published private(set) var scanning = false
    @Published private(set) var resettingAccessibility = false
    @Published private(set) var loginItemStatus: SMAppService.Status = .notRegistered
    @Published var loginItemError: String?

    private let controller: MXVisibilityController
    private var observers: [NSObjectProtocol] = []

    init(controller: MXVisibilityController) {
        self.controller = controller
        for name in [
            NSNotification.Name.MXVisibilityDidChange,
            .MXScanDidChange,
            .MXAccessibilityTrustDidChange,
        ] {
            observers.append(
                NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) {
                    [weak self] _ in
                    MainActor.assumeIsolated { self?.reload() }
                })
        }
        reload()
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    func reload() {
        let permissions = MXPermissions.shared
        accessibilityTrusted = permissions.isAccessibilityTrusted
        accessibilityLost = permissions.accessibilityWasLost
        apiAvailable = controller.isPrivateAPIAvailable
        apiUnavailableReason = MXAssessmentMode.shared.unavailableReason
        status = controller.statusDescription
        errorMessage = controller.lastError?.localizedDescription
        revealing = controller.isRevealing
        hiddenCount = Int(controller.hiddenCount)
        let scan = controller.lastScan
        let hiddenBundles = controller.store.hiddenBundleIdentifiers
        let hiddenSystemItems = Set(controller.store.hiddenSystemItems.map(\.intValue))
        apps = Self.appRows(scan: scan, hidden: hiddenBundles, apple: false)
        appleItems =
            Self.moduleRows(scan: scan, hidden: hiddenSystemItems)
            + Self.appRows(scan: scan, hidden: hiddenBundles, apple: true)
        loginItemStatus = SMAppService.mainApp.status
    }

    /// Hidden apps stay listed even when the scan no longer sees them, otherwise
    /// an app whose items are hidden (or that quit) could only come back through
    /// Show All.
    private static func appRows(scan: MXScanResult, hidden: Set<String>, apple: Bool) -> [MenuBarApp] {
        var rows: [MenuBarApp] = []
        var seen = Set<String>()
        for app in scan.apps
        where app.isSystemApp == apple && !app.bundleIdentifier.isEmpty
            // Its items are the Apple modules, listed one by one instead.
            && app.bundleIdentifier != "com.apple.MenuBarAgent"
        {
            guard seen.insert(app.bundleIdentifier).inserted else { continue }
            let count = app.items.count
            // Apple's helpers are named after the process (Siri owns Spotlight,
            // SystemUIServer owns VPN), so their items say more than their name.
            let titles = app.items.map(\.title).filter { !$0.isEmpty && !$0.hasPrefix("Item") }
            rows.append(
                MenuBarApp(
                    target: .bundle(app.bundleIdentifier),
                    name: apple && !titles.isEmpty ? titles.joined(separator: ", ") : app.appName,
                    detail: apple
                        ? "\(app.appName) · \(app.bundleIdentifier)"
                        : "\(app.bundleIdentifier) · \(count) item\(count == 1 ? "" : "s")",
                    path: app.bundlePath.isEmpty ? nil : app.bundlePath,
                    isHidden: hidden.contains(app.bundleIdentifier)))
        }
        for bundleID in hidden where !seen.contains(bundleID) && bundleID.hasPrefix("com.apple.") == apple {
            let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
            let url = running?.bundleURL ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            let name =
                running?.localizedName
                ?? url.map { FileManager.default.displayName(atPath: $0.path) }
                ?? bundleID
            rows.append(
                MenuBarApp(
                    target: .bundle(bundleID),
                    name: (name as NSString).deletingPathExtension,
                    detail: running == nil ? "\(bundleID) · not running" : "\(bundleID) · hidden",
                    path: url?.path,
                    isHidden: true))
        }
        return rows.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private static func moduleRows(scan: MXScanResult, hidden: Set<Int>) -> [MenuBarApp] {
        var present = Set<Int>()
        for app in scan.apps where app.bundleIdentifier == "com.apple.MenuBarAgent" {
            for item in app.items {
                if let rawValue = MXVisibilityPlan.systemItemRawValue(forItemIdentifier: item.identifier) {
                    present.insert(rawValue.intValue)
                }
            }
        }
        // A hidden module may drop out of the scan; keep it so it can come back.
        return present.union(hidden).sorted().compactMap { rawValue in
            guard let module = appleModules[rawValue] else { return nil }
            return MenuBarApp(
                target: .systemItem(rawValue),
                name: module.name,
                detail: present.contains(rawValue) ? "Built into macOS" : "Built into macOS · hidden",
                symbol: module.symbol,
                isHidden: hidden.contains(rawValue))
        }
    }

    func setVisible(_ visible: Bool, for app: MenuBarApp) {
        switch app.target {
        case .bundle(let bundleID):
            controller.setBundle(bundleID, hidden: !visible)
        case .systemItem(let rawValue):
            controller.setSystemItem(rawValue, hidden: !visible)
        }
    }

    func rescan() {
        scanning = true
        // Both ObjC completions below are delivered on the main queue.
        controller.refreshScan { [weak self] _ in
            MainActor.assumeIsolated { self?.scanning = false }
        }
    }

    func toggleReveal() {
        if controller.isRevealing {
            controller.setRevealing(false)
        } else {
            controller.reveal(forSeconds: 15)
        }
    }

    func hideAll() {
        controller.hideAllThirdPartyApps()
    }

    func showAll() {
        controller.showAllAppsPermanently()
    }

    func grantAccessibility() {
        MXPermissions.shared.requestAccessibility()
    }

    func resetAccessibility() {
        resettingAccessibility = true
        MXPermissions.shared.resetAccessibility { [weak self] _ in
            MainActor.assumeIsolated {
                self?.resettingAccessibility = false
                self?.reload()
            }
        }
    }

    func relaunch() {
        MXPermissions.relaunch()
    }

    var launchAtLogin: Bool {
        get { loginItemStatus == .enabled || loginItemStatus == .requiresApproval }
        set {
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                loginItemError = error.localizedDescription
            }
            loginItemStatus = SMAppService.mainApp.status
        }
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
