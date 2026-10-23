# Mixologist architecture

Mixologist is a small AppKit application. It has no third-party dependencies,
no network code, and no Screen Recording usage.

## Source layout

| File | Responsibility |
| --- | --- |
| `Sources/main.m` | Entry point; dispatch to the GUI or to `--diagnose`, `--scan`, `--hide`, `--self-test` |
| `Sources/MXAppDelegate.{h,m}` | Status item, menu, global hotkey, app lifecycle |
| `Sources/MXMenuBarScanner.{h,m}` | Accessibility scan of every running app's menu bar extras |
| `Sources/MXVisibilityPlan.{h,m}` | Pure allow-list computation (unit-testable) |
| `Sources/MXVisibilityController.{h,m}` | Scan scheduling, reveal lease, assertion lifecycle, workspace observers |
| `Sources/MXPrivateAPI.{h,m}` | Defensive `dlopen` wrapper around `MenuBarClientCore` |
| `Sources/MXSettingsStore.{h,m}` | `NSUserDefaults` persistence |
| `Sources/MXSettingsWindowController.{h,m}` | Programmatic AppKit settings window |
| `Sources/MXHotKey.{h,m}` | Carbon system-wide hotkey |

## Visibility model

macOS's restriction is a **whitelist**. While active, every third-party item not
in the allow list is hidden. Therefore Mixologist computes:

```
allowed bundles = (scanned third-party bundles ∪ all running bundle IDs)
                  − hidden bundles
                  + Mixologist's own bundle
                  + Apple system bundles

allowed system items = the nine MBSystemItemIdentifier raw values, 0...8
```

Including every running bundle — not just the ones with a currently known status
item — prevents a newly launched app from being hidden before the next scan sees
its item. `MXVisibilityPlan` is deliberately pure so this behaviour is covered by
`--self-test`.

### System items

`MBAssessmentModeConfiguration.allowedSystemItems` takes an array of
`NSNumber` raw values, not identifier strings. The private enum has nine cases:

| Raw | Case | Item |
| --- | --- | --- |
| 0 | `battery` | Battery |
| 1 | `bluetooth` | Bluetooth |
| 2 | `clock` | Clock |
| 3 | `displays` | Display |
| 4 | `keyboard` | Keyboard brightness |
| 5 | `volume` | Sound |
| 6 | `wifi` | Wi-Fi |
| 7 | `primaryBentoBox` | Control Center |
| 8 | `screenMirroring` | Screen Mirroring |

Passing all nine preserves Apple's items and does **not** force on items the user
has disabled in System Settings. Passing strings is a trap: the initializer
coerces each element with `integerValue`, so every string becomes `0` (battery)
and Clock, Wi-Fi, and other modules disappear.

When nothing is marked hidden, Mixologist releases the restriction. When
`Reveal` is active, it also releases the restriction and remembers that it should
be re-applied when the reveal ends.

## Scan lifecycle

1. `MXVisibilityController.start` installs `NSWorkspace` launch/terminate/hide/
   unhide/screen-wake observers and a 20-second safety poll.
2. `refreshScanWithCompletion:` runs `MXMenuBarScanner` on a serial background
   queue, coalescing concurrent requests.
3. The scanner walks `AXExtrasMenuBar` recursively, up to six levels, collecting
   `AXMenuBarItem` elements with `AXMenuExtra` subroles. Control Center modules
   are nested inside `AXGroup`/`AXHostingView`, hence the recursion. The main
   `AXMenuBar` is not scanned: it contains application menus, not status items.
4. Results are published on the main queue, notifications are posted, and the
   visibility plan is reconciled only when its signature changed (or when a
   caller forces a re-apply).
5. A hidden app that launches is already excluded from the allow list, so it is
   hidden immediately. A visible app that launches is added by the next scan.

## Assertion lifecycle

`MXPrivateAPI` loads:

```
/System/Library/PrivateFrameworks/MenuBarClientCore.framework/MenuBarClientCore
```

and looks up `MBAssessmentModeConfiguration` and
`MBAssessmentModeAssertion` with `NSClassFromString`. It holds the assertion
strongly. `invalidate` is called:

- before installing a new allow list,
- when the last hidden app is unhidden,
- during a reveal,
- on `applicationWillTerminate`.

If the process dies, the XPC connection to MenuBarAgent is invalidated by the
system, so the restriction is released by macOS. This is the crash-safety
property that prevents a permanent blank menu bar. It was verified with
`SIGKILL`: every item reappeared within a few seconds, with no cleanup code
running in Mixologist.

An allow-list entry only works for items the menu bar server can attribute to a
bundle identifier. A status item created by a process that LaunchServices cannot
resolve to a bundle (for example an app started directly by a management agent)
cannot be matched by any string; it is hidden along with the selection. This is a
property of the private API, not of the scanner. The same reason explains why an
ad-hoc-signed build's own status item may disappear while hiding is active, which
is why the hotkey and settings window are independent control paths.

## UI

`MXSettingsWindowController` builds the window programmatically to avoid nibs
and asset catalogs. Each row is an `NSStackView` with a checkbox, app name,
bundle identifier, item count, and item titles. Toggling a checkbox immediately
updates the stored hidden set and re-applies the plan.

The status item is a convenience, not the only control path. The global hotkey
`⌃⌥⌘M` and the settings window remain usable even if Mixologist's own status item
is hidden by the restriction, which can happen when the app is launched directly
or the menu bar server cannot attribute its item to a bundle.

## Deliberate omissions

- No ScreenCaptureKit, CGWindowList image capture, or menu bar screenshots.
- No per-item ordering UI yet. The MenuBarAgent position schema is documented in
  `REVERSE_ENGINEERING.md`; writing it needs file access to another app group
  container and should be added as an explicit, permissioned feature.
- No Control Center compatibility mode. It is documented but not implemented.
- No profiles, triggers, Bartender Bar, or licensing.

## Testing

```sh
make test        # pure visibility-plan and reveal-state tests
make diagnose    # permissions, private API, live scan
make scan        # JSON scan output
make run
```

A destructive test on a disposable account can exercise the real restriction:

```sh
build/Mixologist.app/Contents/MacOS/Mixologist --hide com.example.app --seconds 10
```

The CLI prints the allow list and releases the restriction when the timer ends.
Two developer-only overrides help diagnose future macOS changes:
`--allow <comma-separated bundle IDs>` replaces the computed bundle allow list,
and `--system-items <comma-separated raw values>` replaces the nine system-item
values. Both are intended for `--hide` experiments, not for normal use.
