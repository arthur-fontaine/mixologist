import AppKit
import SwiftUI

@objc(MXSettingsWindowController)
public final class SettingsWindowController: NSWindowController {
    private let model: SettingsModel

    @objc public init(controller: MXVisibilityController) {
        let model = SettingsModel(controller: controller)
        self.model = model

        let hosting = NSHostingController(rootView: SettingsRootView(model: model))
        // SwiftUI owns the title and toolbar; the window only supplies the chrome.
        hosting.sceneBridgingOptions = [.title, .toolbars]
        hosting.sizingOptions = []

        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titleVisibility = .visible
        window.toolbarStyle = .unified
        // `.automatic` draws a hairline once content scrolls under the bar, splitting the surface.
        window.titlebarSeparatorStyle = .none
        window.isMovableByWindowBackground = false
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(
            width: SettingsMetrics.sidebarWidth + SettingsMetrics.detailMinimumWidth, height: 440)
        window.setContentSize(NSSize(width: 720, height: 580))
        window.center()
        window.setFrameAutosaveName("MixologistSettings")
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    @objc public func reloadData() {
        model.reload()
    }

    /// Opens on the pane that explains a missing permission, instead of wherever
    /// the user last left the window.
    @objc public func showPermissions() {
        model.tab = .general
    }
}
