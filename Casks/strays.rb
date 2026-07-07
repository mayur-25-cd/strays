# Homebrew cask for Strays.
#
# Distribute via a tap repo named "mayur-25-cd/homebrew-tap": copy this file to
# that repo's Casks/ directory, then users install with:
#   brew install --cask mayur-25-cd/tap/strays
#
# On each release, bump `version` and replace `sha256` with the value printed by
# scripts/notarize.sh (or `shasum -a 256 dist/Strays.dmg`).
cask "strays" do
  version "1.0.0"
  sha256 "893fe0f2932056664d4a3a452963ac84e0e672fb3fb65707e3fb227991b06f86"

  url "https://github.com/mayur-25-cd/strays/releases/download/v#{version}/Strays.dmg",
      verified: "github.com/mayur-25-cd/strays/"
  name "Strays"
  desc "See and reclaim the ports and AI sessions your Mac is running"
  homepage "https://github.com/mayur-25-cd/strays"

  depends_on macos: ">= :sonoma"

  app "Strays.app"

  zap trash: [
    "~/Library/Preferences/dev.strays.Strays.plist",
    "~/Library/Caches/dev.strays.Strays",
  ]
end
