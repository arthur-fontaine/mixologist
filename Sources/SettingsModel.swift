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

struct MenuBarApp: Identifiable, Equatable {
    /// The bundle identifier: the only thing the system restriction can match on.
    let id: String
    let name: String
    let detail: String
    let path: String?
    let isHidden: Bool
}

/// SwiftUI's view of `MXVisibilityController`, refreshed from its notifications.
@MainActor
final class SettingsModel: ObservableObject {
    @Published var tab: SettingsTab = .general
    @Published private(set) var apps: [MenuBarApp] = []
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
        let hidden = controller.store.hiddenBundleIdentifiers
        hiddenCount = hidden.count
        apps = Self.rows(scan: controller.lastScan, hidden: hidden)
        loginItemStatus = SMAppService.mainApp.status
    }

    /// Hidden apps stay listed even when the scan no longer sees them, otherwise
    /// an app whose items are hidden (or that quit) could only come back through
    /// Show All.
    private static func rows(scan: MXScanResult, hidden: Set<String>) -> [MenuBarApp] {
        var rows: [MenuBarApp] = []
        var seen = Set<String>()
        for app in scan.apps where !app.isSystemApp && !app.bundleIdentifier.isEmpty {
            guard seen.insert(app.bundleIdentifier).inserted else { continue }
            let count = app.items.count
            rows.append(
                MenuBarApp(
                    id: app.bundleIdentifier,
                    name: app.appName,
                    detail: "\(app.bundleIdentifier) · \(count) item\(count == 1 ? "" : "s")",
                    path: app.bundlePath.isEmpty ? nil : app.bundlePath,
                    isHidden: hidden.contains(app.bundleIdentifier)))
        }
        for bundleID in hidden where !seen.contains(bundleID) {
            let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
            let url = running?.bundleURL ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            let name =
                running?.localizedName
                ?? url.map { FileManager.default.displayName(atPath: $0.path) }
                ?? bundleID
            rows.append(
                MenuBarApp(
                    id: bundleID,
                    name: (name as NSString).deletingPathExtension,
                    detail: running == nil ? "\(bundleID) · not running" : "\(bundleID) · hidden",
                    path: url?.path,
                    isHidden: true))
        }
        return rows.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func setVisible(_ visible: Bool, for app: MenuBarApp) {
        controller.setBundle(app.id, hidden: !visible)
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
