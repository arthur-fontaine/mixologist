import SwiftUI

struct SettingsRootView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        NavigationSplitView {
            SettingsSidebar(model: model)
                // Ahead of the width: applied after it, the column shrinks to AppKit's default.
                .toolbar(removing: .sidebarToggle)
                .navigationSplitViewColumnWidth(
                    min: SettingsMetrics.sidebarWidth, ideal: SettingsMetrics.sidebarWidth,
                    max: SettingsMetrics.sidebarWidth)
        } detail: {
            detail.frame(minWidth: SettingsMetrics.detailMinimumWidth)
        }
        .navigationTitle(model.tab.title)
        .alert(
            "Couldn’t change the login item",
            isPresented: Binding(
                get: { model.loginItemError != nil },
                set: { if !$0 { model.loginItemError = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.loginItemError ?? "")
        }
    }

    @ViewBuilder private var detail: some View {
        switch model.tab {
        case .general: GeneralPane(model: model)
        case .menuBarItems: MenuBarItemsPane(model: model)
        case .about: AboutPane(model: model)
        }
    }
}

private struct SettingsSidebar: View {
    @ObservedObject var model: SettingsModel
    @Environment(\.appearsActive) private var appearsActive

    var body: some View {
        List(selection: selection) {
            ForEach(SettingsTab.allCases) { tab in
                Label {
                    Text(tab.title)
                } icon: {
                    SettingsTabIcon(
                        systemImage: tab.systemImage,
                        tint: appearsActive
                            ? (model.tab == tab ? Color.primary : Color.accentColor)
                            : Color.secondary)
                }
                .badge(badge(for: tab))
                .tag(tab)
            }
        }
        .listStyle(.sidebar)
        // Pin the style before mounting; the implicit sidebar style paints icons a frame late.
        .labelStyle(.titleAndIcon)
    }

    private func badge(for tab: SettingsTab) -> Text? {
        switch tab {
        case .general where !model.accessibilityTrusted:
            Text(Image(systemName: "exclamationmark.triangle.fill")).foregroundStyle(.orange)
        case .menuBarItems where model.hiddenCount > 0:
            Text("\(model.hiddenCount)")
        default:
            nil
        }
    }

    private var selection: Binding<SettingsTab?> {
        Binding(
            get: { model.tab },
            set: { if let tab = $0 { model.tab = tab } })
    }
}

// MARK: - General

private struct GeneralPane: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Section {
                SettingsRow(title: "Mixologist", subtitle: model.status) {
                    SettingsTabIcon(systemImage: "menubar.rectangle", tint: .accentColor, size: 34)
                } trailing: {
                    Button(model.revealing ? "Hide Again" : "Reveal for 15 s") { model.toggleReveal() }
                        .disabled(model.hiddenCount == 0 && !model.revealing)
                }
                if let error = model.errorMessage {
                    SettingsNotice(title: "Hiding isn’t active", message: error, tint: .red)
                }
            }

            PermissionsSection(model: model)

            Section("Startup") {
                Toggle(isOn: $model.launchAtLogin) {
                    Text("Open at login")
                    Text("Hidden items stay hidden after you restart your Mac.")
                }
                if model.loginItemStatus == .requiresApproval {
                    SettingsNotice(
                        title: "Waiting for approval",
                        message: "Allow Mixologist in System Settings › General › Login Items."
                    ) {
                        Button("Open Login Items…") { model.openLoginItemsSettings() }
                    }
                }
            }

            Section {
                SettingsRow(
                    title: "Reveal hidden items",
                    subtitle: "Works even when Mixologist’s own icon is hidden."
                ) {
                    KeyCaps(keys: ["⌃", "⌥", "⌘", "M"])
                }
            } header: {
                Text("Keyboard Shortcut")
            } footer: {
                Text("Quitting Mixologist brings every menu bar item back.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct PermissionsSection: View {
    @ObservedObject var model: SettingsModel
    @State private var confirmingReset = false

    var body: some View {
        Section {
            if model.accessibilityTrusted {
                SettingsRow(
                    title: "Accessibility",
                    subtitle: "Lists the apps in your menu bar. Mixologist never records the screen."
                ) {
                    SettingsTabIcon(systemImage: "accessibility", tint: .blue, size: SettingsMetrics.rowIcon)
                } trailing: {
                    SettingsStatusBadge(title: "Granted", systemImage: "checkmark.circle.fill", tint: .green)
                }
            } else if model.accessibilityLost {
                SettingsNotice(
                    title: "Accessibility access was lost",
                    message:
                        "macOS no longer recognizes this copy of Mixologist, usually after an update or a rebuild. Reset the permission, then turn Mixologist on again."
                ) {
                    resetButton("Reset Permission…")
                }
            } else {
                SettingsNotice(
                    title: "Accessibility access needed",
                    message:
                        "Turn on Mixologist in Privacy & Security › Accessibility. It’s picked up automatically."
                ) {
                    Button("Grant Access…") { model.grantAccessibility() }
                }
            }

            if !model.accessibilityTrusted {
                SettingsRow(
                    title: "Already turned on?",
                    subtitle: "The entry may belong to an older build. Reset it, or relaunch.",
                    subtitleLineLimit: 3
                ) {
                    // Keeps the text in line with the notice above it.
                    Color.clear.frame(width: SettingsMetrics.rowIcon, height: 1)
                } trailing: {
                    if !model.accessibilityLost { resetButton("Reset…") }
                    Button("Relaunch") { model.relaunch() }
                }
            }

            SettingsRow(
                title: "Menu bar visibility service",
                subtitle: model.apiAvailable
                    ? "Provided by macOS’s MenuBarAgent."
                    : (model.apiUnavailableReason ?? "Unavailable on this version of macOS.")
            ) {
                SettingsTabIcon(systemImage: "eye.slash", tint: .purple, size: SettingsMetrics.rowIcon)
            } trailing: {
                if model.apiAvailable {
                    SettingsStatusBadge(title: "Available", systemImage: "checkmark.circle.fill", tint: .green)
                } else {
                    SettingsStatusBadge(title: "Unavailable", systemImage: "xmark.octagon.fill", tint: .red)
                }
            }
        } header: {
            Text("Permissions")
        }
        .confirmationDialog(
            "Reset Accessibility permission?", isPresented: $confirmingReset, titleVisibility: .visible
        ) {
            Button("Reset Permission") { model.resetAccessibility() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "Mixologist’s entry is removed from System Settings and macOS asks again. Turn Mixologist on when prompted."
            )
        }
    }

    private func resetButton(_ title: String) -> some View {
        Button(title) { confirmingReset = true }
            .disabled(model.resettingAccessibility)
    }
}

// MARK: - Menu Bar Items

private struct MenuBarItemsPane: View {
    @ObservedObject var model: SettingsModel
    @State private var confirmingHideAll = false
    @State private var confirmingShowAll = false

    var body: some View {
        Form {
            if !model.accessibilityTrusted {
                Section {
                    SettingsNotice(
                        title: "Mixologist can’t see your menu bar yet",
                        message: "Grant Accessibility access to list the apps that own menu bar items."
                    ) {
                        Button("Grant Access…") { model.grantAccessibility() }
                    }
                }
            }

            Section {
                if model.apps.isEmpty {
                    Text(
                        model.accessibilityTrusted
                            ? "No third-party menu bar items found. Open an app that adds one, then rescan. If apps you expect are missing, relaunch Mixologist."
                            : "Apps appear here once Accessibility access is granted."
                    )
                    .foregroundStyle(.secondary)
                } else {
                    ForEach(model.apps) { app in
                        Toggle(isOn: visibility(of: app)) {
                            HStack(spacing: 10) {
                                AppIconView(path: app.path)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(app.name).lineLimit(1)
                                    Text(app.detail)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                            }
                        }
                        .toggleStyle(.switch)
                        .help(app.isHidden ? "Hidden. Turn on to show its menu bar items." : "Visible")
                    }
                }
            } header: {
                HStack {
                    Text("Applications")
                    Spacer()
                    if model.scanning {
                        ProgressView().controlSize(.small)
                    }
                    Button("Rescan") { model.rescan() }
                        .disabled(model.scanning)
                }
            } footer: {
                Text(
                    "Turn an app off to hide all of its menu bar items. Apple’s own items, like Clock, Wi-Fi and Control Center, always stay visible."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent {
                    Button("Hide All…") { confirmingHideAll = true }
                        .disabled(model.apps.allSatisfy(\.isHidden))
                } label: {
                    Text("Hide every third-party app")
                    Text("⌃⌥⌘M reveals them for 15 seconds.")
                }
                LabeledContent {
                    Button("Show All…") { confirmingShowAll = true }
                        .disabled(model.hiddenCount == 0)
                } label: {
                    Text("Show every app")
                    Text("Stops hiding. Mixologist keeps running.")
                }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(
            "Hide all third-party menu bar items?", isPresented: $confirmingHideAll,
            titleVisibility: .visible
        ) {
            Button("Hide All") { model.hideAll() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Apple’s items and this window stay available. Press ⌃⌥⌘M to bring them back for a moment.")
        }
        .confirmationDialog(
            "Show every menu bar item?", isPresented: $confirmingShowAll, titleVisibility: .visible
        ) {
            Button("Show All") { model.showAll() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every app is marked visible again.")
        }
    }

    private func visibility(of app: MenuBarApp) -> Binding<Bool> {
        Binding(
            get: { !app.isHidden },
            set: { model.setVisible($0, for: app) })
    }
}

// MARK: - About

private struct AboutPane: View {
    @ObservedObject var model: SettingsModel

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "Version \(short) (\(build))"
    }

    var body: some View {
        Form {
            Section {
                VStack(spacing: 8) {
                    SettingsTabIcon(systemImage: "menubar.rectangle", tint: .accentColor, size: 64)
                    Text("Mixologist").font(.title2.weight(.semibold))
                    Text(version)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text("A free, open-source menu bar organizer built on macOS’s own visibility restriction.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }

            Section("Privacy") {
                SettingsRow(title: "No screen recording", subtitle: "Items are hidden by macOS, not by capturing pixels.") {
                    SettingsTabIcon(systemImage: "video.slash", tint: .green, size: SettingsMetrics.rowIcon)
                } trailing: {
                    EmptyView()
                }
                SettingsRow(title: "No network access", subtitle: "No analytics, accounts or update checks.") {
                    SettingsTabIcon(systemImage: "network.slash", tint: .green, size: SettingsMetrics.rowIcon)
                } trailing: {
                    EmptyView()
                }
                SettingsRow(title: "Stores one list", subtitle: "Only the bundle identifiers you chose to hide.") {
                    SettingsTabIcon(systemImage: "list.bullet", tint: .green, size: SettingsMetrics.rowIcon)
                } trailing: {
                    EmptyView()
                }
            }

            Section {
                // Not `LabeledContent`: it would name both buttons after the row title.
                SettingsRow(
                    title: "Quit Mixologist",
                    subtitle: "Every menu bar item comes back when Mixologist quits."
                ) {
                    Button("Relaunch") { model.relaunch() }
                    Button("Quit") { NSApp.terminate(nil) }
                }
            }
        }
        .formStyle(.grouped)
    }
}
