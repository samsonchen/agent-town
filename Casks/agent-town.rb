cask "agent-town" do
  version "1.0.4"
  sha256 "3c6295bb799978068b3cf31837b7681762c89a0ca77277287ff7c14ed1b066eb"

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
