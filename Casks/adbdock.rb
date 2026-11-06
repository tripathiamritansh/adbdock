cask "adbdock" do
  arch arm: "arm64", intel: "x86_64"

  version "1.1.2"
  sha256 arm:   "485cfc5bdb842d95c03680411fe983c38fe497afe7efb3ba9ae2cab334b30e0f",
         intel: "c6ea7aca3361cdcd732674b17ef70dcbc6d1f250b11cd3ea9c69a034f70beed6"

  url "https://github.com/tripathiamritansh/adbdock/releases/download/v#{version}/AdbDock-#{version}-#{arch}-unsigned.dmg"
  name "ADB Dock"
  desc "Android wireless debugging in the menu bar"
  homepage "https://github.com/tripathiamritansh/adbdock"

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
