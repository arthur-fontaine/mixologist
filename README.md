# Mixologist

A free, open-source menu bar organizer for macOS 26/27. It hides menu bar items
using macOS's own menu bar visibility restriction — **no Screen Recording
permission, no subscription, no paywall.**

Mixologist is an independent clean-room project. It is not affiliated with
Bartender or Surtees Studios.

## Why this exists

Bartender 7 is currently the best-known way to hide menu bar items on macOS 27.
This project reverse-engineered the mechanism (see
[`docs/REVERSE_ENGINEERING.md`](docs/REVERSE_ENGINEERING.md)) and implements the
core behaviour in a small, auditable codebase:

- macOS 26 introduced `MenuBarAgent`, which owns a visibility-restriction service.
- A private client API, `MenuBarClientCore.MBAssessmentModeAssertion`, can install
  an allow list with the `assessmentMode` origin.
- Everything not on the allow list disappears from the status area.
- Releasing the assertion restores every item.
- Screen Recording is only needed for pixels, not for hiding. Mixologist never
  captures the screen.

## Features

- Hide third-party menu bar items per application.
- Hide Apple's own items too: Clock, Wi-Fi, Battery, Control Center, Spotlight, …
- A Bartender-style **dot** in the menu bar: click it to reveal hidden items for
  15 seconds, click again to hide them, right-click for the menu.
- Global shortcut `⌃⌥⌘M` toggles the reveal.
- Settings window with live discovery of running apps and their items.
- No screen capture, no network, no analytics, no accounts.
- Quitting (or crashing) releases the restriction and restores the menu bar.

## Requirements

- macOS 26 or later (developed and tested on macOS 27.0, build `26A428`).
- Accessibility permission, used to discover and name menu bar items.
- Xcode (for `clang`, `swiftc` and the macOS 26+ SDK) to build. No Xcode project
  is required.

## Build and run

```sh
make            # builds build/Mixologist.app
make run        # builds and opens it
make diagnose   # prints permissions, API availability, and a live scan
make test       # runs the pure allow-list tests
```

To install:

```sh
make install    # copies to /Applications/Mixologist.app
```

### Code signing

`make` signs with the first `Apple Development` identity in your keychain and
falls back to ad-hoc signing when there is none. Override it with:

```sh
CODESIGN_IDENTITY="Apple Development: Your Name (TEAMID)" make
```

A real identity matters for Accessibility: macOS ties an ad-hoc build's grant to
that exact binary, so every rebuild loses it while System Settings still shows
the switch as on. If that happens, use **Reset Permission** in Mixologist's
settings and grant it again.

Run Mixologist from `/Applications` (`make run` installs it there first). From
any other folder MenuBarAgent attributes its status item to the executable path
instead of the bundle identifier, so the allow list cannot keep the dot visible
and it hides along with everything else. Settings offers **Move to
Applications** when this happens; the `⌃⌥⌘M` shortcut works either way.

The app is not sandboxed. It does not need Full Disk Access for the core hiding
feature.

## Configuration

Settings live in `~/.config/mixologist/settings.json`, so they can be versioned
with your dotfiles or edited by hand. Mixologist writes the file whenever you
change something in Settings and applies edits to it as soon as you save; any
part it can't use is reported under Settings → General → Configuration. While
the file isn't valid JSON, Mixologist leaves it alone and keeps its last good
values.

```json
{
  "hidingMethod": "restriction",
  "hiddenApps": ["com.1password.1password", "notion.id"],
  "hiddenAppleItems": ["clock", "wifi"]
}
```

| Key | Values |
| --- | --- |
| `hidingMethod` | `"restriction"` (default) or `"permission"`; see [Hiding methods](#hiding-methods) |
| `hiddenApps` | Bundle identifiers whose menu bar items are hidden |
| `hiddenAppleItems` | Any of `battery`, `bluetooth`, `clock`, `display`, `keyboardBrightness`, `sound`, `wifi`, `screenMirroring`, `controlCenter` |

A missing key takes its default. The first launch of this version moves settings
stored by older versions into the file.

## Usage

1. Launch Mixologist.
2. Grant Accessibility when prompted (System Settings → Privacy & Security →
   Accessibility). Mixologist notices the change by itself; if it doesn't,
   use **Reset Permission** or **Relaunch** in Settings → General.
3. In Settings → Menu Bar Items, turn an app off to hide its menu bar items.
4. Use **Reveal for 15 s** or `⌃⌥⌘M` to show everything temporarily.
5. **Show All** permanently restores everything.
6. Quit Mixologist to release the restriction.

Apple's modules (Clock, Wi-Fi, Battery, Control Center, Display, …) are hidden
individually by leaving their `MBSystemItemIdentifier` raw value (`0...8`) out of
the private API's system-item list. Applications without a bundle identifier — and status items that
macOS cannot attribute to an allow-listed bundle, including some apps launched
directly by an agent — cannot be selectively allow-listed and will be hidden
while a restriction is active. This is a limitation of the system allow-list API,
not a choice Mixologist makes.

## How it works (short version)

```
Accessibility scan ──► allow-list plan ──► MenuBarClientCore assertion
       │                      │                       │
  app + item names      visible bundles         MenuBarAgent hides
  system item IDs       + system items          everything else
```

The full evidence trail — shipped Bartender docs, private class introspection,
live plist schemas, and controlled visibility experiments — is in
[`docs/REVERSE_ENGINEERING.md`](docs/REVERSE_ENGINEERING.md). Architecture and
extension points are in [`docs/TECHNICAL.md`](docs/TECHNICAL.md).

## Limitations

- **Private API.** `MenuBarClientCore` is not public. Apple can change or remove it
  in any macOS update. This app is therefore not App Store material.
- **Now Playing, Focus and similar modules.** While anything is hidden, macOS
  also hides the Control Center modules you added to the menu bar beyond the nine
  basic ones (Now Playing, Focus, …). The restriction API cannot name them, so no
  allow list keeps them; they come back whenever you reveal.
- **Per-app granularity.** The system restriction works per bundle identifier.
  Hiding one item from an app that exposes several items hides all of them.
- **Unattributed items.** Some status items cannot be attributed to a bundle
  identifier by the menu bar server, for example an app launched directly by a
  management agent or run from outside `/Applications`. Those items cannot be
  allow-listed and are hidden whenever a restriction is active. That includes
  Mixologist's own dot when it runs from a build folder.
- **macOS 26/27 only.** Older systems do not have MenuBarAgent.
- **No ordering/profiles yet.** Bartender's position database and compatibility
  mode are documented for future work, but not implemented.
- **Other menu bar managers.** Running Mixologist alongside Bartender, Ice, Thaw,
  or similar installs a second restriction. An item stays visible if either one
  allows it, so they undo each other's hiding. Use one at a time.
- **Crowded menu bars.** While revealing, a full menu bar (especially next to a
  notch) can push the dot out of sight; ⌘-drag it further right, or wait for
  the 15-second reveal to end.

## Safety

The restriction is owned by the running process. If Mixologist quits or crashes,
macOS invalidates the XPC assertion and restores the menu bar. This was verified
with a graceful quit and with `SIGKILL`; both restored every item. The app also
releases the restriction in `applicationWillTerminate`. The global shortcut and
settings window do not depend on Mixologist's status item being visible.

## Privacy

Mixologist reads menu bar metadata through the Accessibility API and stores only a
list of hidden bundle identifiers in `NSUserDefaults`. It makes no network
requests and contains no analytics or update framework.

## License

MIT. See [`LICENSE`](LICENSE).
