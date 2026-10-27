cask "mixologist" do
  version :latest
  sha256 :no_check

  # `make release` uploads the DMG under this name to every release.
  url "https://github.com/arthur-fontaine/mixologist/releases/latest/download/Mixologist.dmg"
  name "Mixologist"
  desc "Menu bar organizer that hides items without Screen Recording"
  homepage "https://github.com/arthur-fontaine/mixologist"

  depends_on arch: :arm64
  depends_on macos: :tahoe

  app "Mixologist.app"

  # Not notarized: Gatekeeper refuses to launch it while quarantined.
  postflight_steps do
    run "/usr/bin/xattr", args: ["-dr", "com.apple.quarantine", "{{appdir}}/Mixologist.app"]
  end

  # Quitting releases the menu bar restriction, so hidden items come back.
  uninstall quit: "dev.mixologist.Mixologist"

  zap login_item: "Mixologist",
      trash:      [
        "~/.config/mixologist",
        "~/Library/Preferences/dev.mixologist.Mixologist.plist",
      ]
end
