cask "agent-town" do
  version "0.2.8"
  sha256 "f58cf6037c8130a312ec13665a2bc9bb49faebefdee60f968e0fbb5b16b7ca90"

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
    agent-town also needs the town-link plugin in Claude Code:
      claude plugin marketplace add samsonchen/agent-town
      claude plugin install town-link@agent-town
  EOS
end
