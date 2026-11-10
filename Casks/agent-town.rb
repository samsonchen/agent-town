cask "agent-town" do
  version "0.0.0"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"

  url "https://github.com/samsonchen/agent-town/releases/download/v#{version}/AgentTown-#{version}.dmg"
  name "agent-town"
  desc "Shows Claude Code's work as a small office"
  homepage "https://github.com/samsonchen/agent-town"

  livecheck do
    url :url
    strategy :github_releases
  end

  depends_on macos: :sequoia

  app "AgentTown.app"

  uninstall quit: "ai.careactive.agenttown"

  zap trash: [
    "~/Library/Application Support/agent-town",
    "~/Library/Preferences/ai.careactive.agenttown.plist",
  ]

  caveats <<~EOS
    agent-town is not signed yet, so macOS blocks it the first time it opens.
    Open System Settings → Privacy & Security, find the message about AgentTown,
    and click Open Anyway. This is needed once.

    agent-town also needs the town-link plugin in Claude Code:
      claude plugin marketplace add samsonchen/agent-town
      claude plugin install town-link@agent-town
  EOS
end
