# Reverse engineering Bartender 7 (macOS 27)

This document records how Bartender 7 hides menu bar items on macOS 27 without
Screen Recording, and how Mixologist reproduces the essential mechanism. It is a
clean-room, behaviour-focused analysis: no Bartender code, assets, or binaries are
included in this repository.

## Target under analysis

| Item | Value |
| --- | --- |
| Product | Bartender 7.1.0 |
| Bundle | `com.surteesstudios.Bartender` |
| Official download | `https://downloads.macbartender.com/Bartender7/updates/7-1-0/Bartender%207.zip` |
| SHA-256 | `22ed651f6d57bbe34fc19a76f46856775759aeda361301828c64e9cb7218aa69` |
| Signature | Developer ID Application: Bartender App LLC (`24J875RH8J`), notarized |
| Host OS used | macOS 27.0 (build `26A428`), arm64 |
| SDK in the app | macOS 27.2 (`macosx27.2`) |

The download was verified against Homebrew's cask checksum before analysis.
Bartender was not installed; the signed bundle was unpacked into a temporary
directory and inspected statically. System-level probes used the same macOS
build.

## Executive summary

On macOS 26/27 Apple moved menu bar items into a new system component called
**MenuBarAgent**. MenuBarAgent owns a **visibility restriction** service. A
client can ask it to keep only a supplied allow list visible. The restriction has
an origin, and one origin is `assessmentMode` — the mechanism Bartender uses as
its default "Standard" hiding method.

Bartender hides items by activating an assessment-mode restriction whose allow
list contains the items that should stay visible. It does **not** capture the
menu bar with ScreenCaptureKit to hide items, so no Screen Recording permission
is needed. Screen Recording is only used by Bartender for optional item images
and image-change triggers.

Physical ordering is a separate mechanism: MenuBarAgent persists preferred item
positions in
`~/Library/Group Containers/com.apple.MenuBar/Library/Preferences/com.apple.MenuBar.plist`
under `TrailingItemPreferredPositions`. Bartender's compatibility hiding method
is a third mechanism: it writes `isAllowed` flags in Control Center's
`trackedApplications` approvals.

## Evidence 1: documentation shipped inside the app

The signed app bundle contains three unusually explicit engineering documents:

- `Contents/Resources/ARCHITECTURE.md`
- `Contents/Resources/INTEGRATION.md`
- `Contents/Resources/MACOS_26_VERIFICATION_CHECKLIST.md`

They describe the GoldenGate architecture and, among other things:

> "On macOS 27 and later, movement always uses MenuBarAgent plist positions"

> "Advanced → Hiding Method saves `GoldenGateHidingMode` for the next launch:
> **Standard** (default): `GoldenGateMoveType.assessmentMode`. **Compatibility**:
> `GoldenGateMoveType.controlCentre`"

> "Compatibility edits existing Control Center approval entries through
> `MenuBarItemVisibilityController`, preserving entry shapes."

> "Test Screen Recording denied and granted: item control should still work;
> images and image-change triggers should recover after permission is restored."

The last sentence is the strongest confirmation that item control is independent
of Screen Recording.

## Evidence 2: symbols and strings

`strings` over the Mach-O main binary contains these identifiers:

```text
MBAssessmentModeAssertion
MBAssessmentModeConfiguration
MBAssessmentMode classes unavailable; cannot activate
dlopen(MenuBarClientCore) failed
activateWithConfiguration:completionHandler:
initWithAllowedSystemItems:allowedBundleIdentifiers:
TrailingItemPreferredPositions
Library/Group Containers/group.com.apple.controlcenter/Library/Preferences/group.com.apple.controlcenter.plist
com.apple.MenuBar.plist
```

The main binary does not link `MenuBarClientCore` at load time; it `dlopen`s:

```text
/System/Library/PrivateFrameworks/MenuBarClientCore.framework/MenuBarClientCore
```

and looks up the two classes by name. This is visible from the literal
`dlopen(MenuBarClientCore) failed` string and from the absence of a normal
`LC_LOAD_DYLIB` entry for the framework.

Apple's `/System/Library/CoreServices/MenuBarAgent.app/Contents/MacOS/MenuBarAgent`
contains the server side:

```text
com.apple.MenuBarAgent.visibility-restriction
MBVisibilityRestrictionServiceDefinition
VisibilityRestrictionOrigin.assessmentMode
VisibilityRestrictionOrigin.campoDrag
VisibilityRestrictionOrigin.userSessionTransition
didActivateVisibilityRestriction
didInvalidateVisibilityRestriction
VisibilityRestrictionServer received connection from pid:
```

MenuBarAgent's `Info.plist` declares a BSService domain with a
`com.apple.MenuBarAgent.visibility-restriction` service. Its entitlements are
Apple-private (`com.apple.private.skylight.menubaragent`,
`com.apple.private.menubar.system-banners`, etc.).

## Evidence 3: runtime introspection of the private classes

A small Objective-C program loads `MenuBarClientCore` with `dlopen` and walks the
Objective-C runtime. On macOS 27 the relevant classes are ordinary `NSObject`
subclasses:

```text
MBAssessmentModeAssertion
  - init
  - invalidate
  - activateWithCompletionHandler:
  - activate:completion:
  - activateWithConfiguration:completionHandler:     types: v32@0:8@16@?24

MBAssessmentModeConfiguration
  - init
  - initWithAllowedSystemItems:allowedBundleIdentifiers:   types: @32@0:8@16@24
  - allowedSystemItems        (readonly NSArray)
  - allowedBundleIdentifiers  (readonly NSArray)
```

No private entitlement is required: an unsigned local probe could activate the
assertion. The app only needs the framework to be loadable and the classes to be
present.

Other Swift classes in the same framework:

```text
MenuBarClientCore.VisibilityRestrictionAssertion
MenuBarClientCore.VisibilityRestrictionMonitorSession
MenuBarClientCore.TrackedApplicationsPreferences
MenuBarClientCore.TrackedRemoteLiveActivityApplicationPreferences
MenuBarClientCore.MBSystemItemIdentifier
MenuBarClientCore.VisibilityRestrictionAllowList
MenuBarClientCore.VisibilityRestrictionOrigin
```

`VisibilityRestrictionOrigin` has the cases `assessmentMode`, `campoDrag`, and
`userSessionTransition`. `VisibilityRestrictionAllowList` is constructed from
system item identifiers and bundle identifiers.

The system-item enum has nine cases, confirmed from the Swift field descriptor
(`battery`, `bluetooth`, `clock`, `displays`, `keyboard`, `volume`, `wifi`,
`primaryBentoBox`, `screenMirroring`) and from the raw-value switch. Note the
plural `displays`. The ObjC initializer bridges the Swift `[MBSystemItemIdentifier]`
as `NSArray<NSNumber *>`; string elements are coerced with `integerValue` and
therefore all become `0`. The allow list struct itself has exactly two fields,
`systemItems` and `bundleIdentifiers`; there is no wildcard for unattributed
items.

## Evidence 4: the live MenuBarAgent position database

On the test machine the file is user-readable:

```text
~/Library/Group Containers/com.apple.MenuBar/Library/Preferences/com.apple.MenuBar.plist
```

Schema observed on macOS 27:

```xml
<key>TrailingItemPreferredPositions</key>
<dict>
    <key>module:Clock</key>                          <integer>0</integer>
    <key>module:WiFi</key>                           <integer>1362</integer>
    <key>module:AudioVideoModule</key>               <integer>696</integer>
    <key>status:com.example.app::Item-0</key>        <integer>1662</integer>
    <key>status:com.example.app::&lt;UUID&gt;</key>  <integer>1762</integer>
</dict>
```

Keys are either `module:<ControlCenterModule>` or
`status:<bundle-id>::<item-id>`. Values are x positions. Bartender's
`MoveHelperMenuBarAgent` writes this dictionary to reorder items. This is
independent from hiding.

## Evidence 5: Control Center approvals

`~/Library/Group Containers/group.com.apple.controlcenter/Library/Preferences/group.com.apple.controlcenter.plist`
contains a `trackedApplications` value that is itself a binary plist. Decoding it
yields an array with entries shaped like:

```text
{ bundle: { _0: "com.example.app" } }
{
  location: { bundle: { _0: "com.example.app" } },
  menuItemLocations: [ { bundle: { _0: "com.example.app" } } ],
  isAllowed: true
}
```

Unsigned/ad-hoc test apps use a location of the form:

```text
{ location: { bundle: { _0: "com.example.app" } },
  menuItemLocations: [
    { adhocBinary: { _0: { relative: "file:///path/to/App.app/Contents/MacOS/App" } } }
  ],
  isAllowed: true }
```

Bartender's Compatibility mode edits `isAllowed` while preserving the entry
shape and journals the original values in
`~/Library/Application Support/Bartender 7/Compatibility Backups/`.

## Runtime experiments

A probe created three `NSStatusItem`s in a bundled test app and used
`CGWindowListCopyWindowInfo`, the Accessibility API, and display screenshots to
observe the menu bar.

1. **Baseline** — all status items visible, including system items and third-party
   items.
2. **Empty allow list** — `MBAssessmentModeConfiguration` with
   `allowedSystemItems = []` and `allowedBundleIdentifiers = []` was activated.
   The entire status area disappeared, including Clock, Wi-Fi, Battery, Control
   Center, and third-party items. Application menus (File, Edit, …) remained.
3. **Release** — calling `invalidate` restored every item immediately.
4. **System allow list** — `allowedSystemItems` expects an array of `NSNumber`
   raw values, not identifier strings. The nine cases and their values are:

   ```text
   0 battery          3 displays            6 wifi
   1 bluetooth        4 keyboard            7 screenMirroring
   2 clock            5 volume              8 primaryBentoBox
   ```

   Passing all nine keeps Apple's items visible without forcing on modules the
   user disabled in System Settings. Passing strings is misleading: the
   initializer coerces every element with `integerValue`, so a string such as
   `com.apple.menuextra.controlcenter` becomes `0` (battery) and Clock, Wi-Fi,
   Control Center, and the other modules disappear. An earlier revision of this
   document reported that the string identifier worked; that observation was an
   artefact of the probe's own conversion and is superseded by the raw-value
   behaviour above.
5. **Bundle allow list** — passing bundle identifiers of Control Center–tracked,
   Developer ID–signed apps (Raycast, 1Password, Claude, BetterDisplay) kept those
   apps' items visible while other third-party items were hidden. The probe apps
   were registered in `trackedApplications` automatically after first launch.
6. **Ad-hoc probe** — an ad-hoc/linker-signed probe's bundle was not visibly
   allow-listed in the same run. This is recorded as **uncertain**: the external
   display disconnected during that test and the session later locked, so the
   observation was not clean. Mixologist treats the ability to allow an ad-hoc
   app as unproven and provides a hotkey/window fallback.
7. **Unattributed items** — an app that is allow-listed by bundle identifier can
   still be hidden if the menu bar server cannot attribute its status item to
   that bundle. This was observed with Fleet Desktop 1.62.1
   (`com.fleetdm.desktop`), which Orbit launches directly from
   `/opt/orbit/bin/desktop/macos/stable/`. Adding the bundle identifier, the
   team-prefixed identifier, the executable name, and the bundle path to the
   allow list did not preserve its item, while Claude
   (`com.anthropic.claudefordesktop`) and SentinelOne
   (`com.sentinelone.SentinelAgent`) were preserved. The allow list has no
   wildcard or "unknown items" switch; `VisibilityRestrictionAllowList` contains
   only `systemItems` and `bundleIdentifiers`.

8. **Selective system items** — with no other restriction active, leaving
   only `2` (clock) out of the nine raw values hid the Clock and nothing else,
   although `com.apple.MenuBarAgent`, `com.apple.controlcenter` and
   `com.apple.systemuiserver` were all in the bundle allow list. An empty
   system-item list with every bundle allowed hid all Apple modules but kept
   Spotlight (`com.apple.campo`) and VPN (`com.apple.systemuiserver`); those two
   disappear only when their bundles are left out.
9. **Two restrictions** — while one process held a restriction that allowed the
   Clock, a second process's restriction without it did not hide the Clock, and
   items hidden by the first reappeared under the second's broader allow list.
   An item is visible when any active restriction allows it.

10. **Control Center modules beyond the nine** — Now Playing
    (`module:NowPlaying`) and Focus (`module:FocusModes`) disappear under any
    restriction and no allow list brings them back: not the nine system items,
    not raw values 9–12, and not any bundle identifier tried
    (`com.apple.controlcenter.nowplaying`, `com.apple.menuextra.focusmode`,
    `com.apple.MediaRemoteUIService`, and others). MenuBarAgent converts the
    client's items by name (`MBSystemItemIdentifier.stringValue` matched against
    its own 11-case `MenuBarSystemItemIdentifier`), and its extra cases,
    `addNewBentoBoxButton` and `bentoBox`, have no client counterpart. These
    modules are `bentoBox` items, so assessment mode cannot allow them. The
    screen-recording stop button stays visible because `com.apple.screencaptureui`
    is a running, allow-listed bundle.
11. **Raw values 7 and 8** — `MBSystemItemIdentifier.stringValue` returns
    `screenMirroring` for 7 and `primaryBentoBox` for 8, and leaving out 8 (not 7)
    hides Control Center. Earlier revisions of this document had them swapped.

12. **Allow in the Menu Bar approvals** — flipping an app's `isAllowed` in
    `group.com.apple.controlcenter`'s `trackedApplications` hides and restores
    its status item live, leaving Control Center modules alone, but only when
    written through cfprefsd's container source
    (`_CFPreferencesSetValueWithContainer`). Writing the same key with the
    plist's path as the domain updated the file on disk while the item stayed on
    screen. A log capture of a System Settings toggle showed the write landing in
    `CFPDContainerSource`, MenuBarAgent reacting about 0.7 s later by waking the
    app's process to rebuild its item, and no distributed notification. That one
    toggle also pruned 17 stale entries from the list.

MenuBarAgent logs the restriction lifecycle:

```text
[com.apple.menubar:visibilityRestriction] VisibilityRestrictionServer received connection from pid: ...
[com.apple.menubar:visibilityRestriction] didActivateVisibilityRestriction with id: <private>
```

and, when items are created:

```text
[com.apple.menubar:statusItems] Creating status item <uuid>, isAllowed: true
```

`isAllowed` here refers to Control Center's approval state, not the assessment
allow list.

## What Bartender does with the mechanism

Bartender's GoldenGate layer adds several things on top of the raw restriction:

- A retained **allow-list plan** that is reconciled when apps launch, quit, or
  change items.
- **Leases** for temporary reveals so overlapping show/click operations do not
  undo each other.
- A **visibility cover window** (`GoldenGateAssessmentVisibilityCoverWindow`) used
  while the restriction is being applied, presumably to hide transient animation
  or flashes.
- **Profile and order** persistence on top of MenuBarAgent positions.
- **Compatibility mode** as a fallback that edits Control Center approvals.
- Optional image capture through ScreenCaptureKit for the Bartender Bar and
  trigger images.

Mixologist implements the first two ideas in a much smaller form: one assertion,
a reconciled allow list, and a reveal lease. It deliberately does not copy the
cover window, image pipeline, profiles, or compatibility writer.

## Why no Screen Recording is needed

Hiding is performed by MenuBarAgent, not by drawing over the menu bar. The only
permissions involved are:

- **Accessibility** — to discover and name menu bar items (AX), and optionally to
  press them.
- **File access** — only if a future compatibility mode writes Control Center or
  MenuBarAgent preferences.

ScreenCaptureKit is used by Bartender for pixels, not for visibility. A clone can
show text labels and app icons without ever asking for Screen Recording.

## Reproducing the analysis

The probe sources are intentionally not part of the product target. To repeat the
key experiment on a disposable account:

```sh
# 1. Load the private framework and inspect the classes.
clang -fno-objc-arc -framework Foundation -o introspect introspect.m
./introspect

# 2. Activate an empty restriction for 10 seconds.
./assess "" "" 10

# 3. Activate with only Wi-Fi (6) and Control Center (7) allowed.
#    The first argument is a comma-separated list of MBSystemItemIdentifier
#    raw values, not identifier strings.
./assess "6,7" "" 10
```

`assess` creates an `MBAssessmentModeConfiguration`, an
`MBAssessmentModeAssertion`, calls
`activateWithConfiguration:completionHandler:`, spins the run loop, then calls
`invalidate`. Its first argument is parsed into `NSNumber` values before being
handed to the initializer.

## Residual unknowns

- Whether an ad-hoc-signed app can be allow-listed by bundle identifier. The
  clean test was interrupted; Mixologist does not depend on it. Directly launched
  processes may have their status item hidden even when their bundle identifier
  is on the allow list, so the hotkey and settings window are the reliable
  control paths.
- Exact macOS 26 behaviour. Bartender's own checklist says macOS 26 acceptance
  had not been performed on the macOS 27 development machine. Mixologist is
  tested on macOS 27 only.
- Whether Apple will keep `MBAssessmentModeAssertion` across future macOS
  releases. It is private API and can disappear or change.
- Whether multiple concurrent restrictions from different menu bar managers (or
  two copies of Mixologist) intersect or replace each other. Union-like behaviour
  was observed in testing. Running two managers at once is unsupported.
