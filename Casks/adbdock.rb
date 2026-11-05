cask "adbdock" do
  arch arm: "arm64", intel: "x86_64"

  version "1.1.1"
  sha256 arm:   "c536a7952f8376594d969e8dfacfa2743ae016e5dac75186f7ec3d28d185f31c",
         intel: "be5c0d1e931dbfda82c79fee7dae613016ee4ad75b6034e02524c9c85583c1a6"

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
