cask "adbdock" do
  version "1.0"
  sha256 "903ff2389ce7b7a8ac907986325e8365dd3256e676ce4fe3805744533815e877"

  url "https://github.com/tripathiamritansh/adbdock/releases/download/v#{version}/AdbDock-#{version}-arm64-unsigned.dmg"
  name "ADB Dock"
  desc "Android wireless debugging in the menu bar"
  homepage "https://github.com/tripathiamritansh/adbdock"

  depends_on arch: :arm64
  depends_on cask: "android-platform-tools"
  depends_on macos: :ventura

  app "AdbDock.app"

  uninstall launchctl: "com.example.adbdock",
            quit:      "com.example.adbdock"

  zap trash: "~/Library/Application Support/AdbDock"

  caveats <<~EOS
    This release is ad-hoc signed and is not notarized. macOS may require
    app-specific approval in System Settings > Privacy & Security before launch.
    See https://github.com/tripathiamritansh/adbdock/blob/main/docs/INSTALL.txt

    After an upgrade or reinstall, re-enable Start at login if you use it.
  EOS
end
