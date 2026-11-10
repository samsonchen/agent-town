cask "agent-town" do
  version "0.2.3"
  sha256 "0de8eaa7500d9c7c046475df07a6d5b5a6c33e3020bb76e493ec776bdd716d73"

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
