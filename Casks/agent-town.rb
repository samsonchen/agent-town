cask "agent-town" do
  version "1.0.13"
  sha256 "45720797110dc555dd89e45b7f6061b7d7e082209b21aca2ccc71282b170c4df"

  url "https://github.com/samsonchen/agent-town-claude-code/releases/download/v#{version}/AgentTown-#{version}.dmg"
  name "agent-town"
  desc "Shows Claude Code's work as a small office"
  homepage "https://github.com/samsonchen/agent-town-claude-code"

  livecheck do
    url :url
    strategy :github_releases
    regex(/^v(\d+(?:\.\d+)+)$/i)
  end

  depends_on macos: :sequoia

  app "AgentTown.app"

  uninstall quit: "ai.careactive.agenttown-claude-code"

  zap trash: [
    "~/Library/Application Support/agent-town-claude-code",
    "~/Library/Preferences/ai.careactive.agenttown-claude-code.plist",
  ]

  caveats <<~EOS
    agent-town also needs the town-link plugin in Claude Code:
      claude plugin marketplace add samsonchen/agent-town-claude-code
      claude plugin install town-link@agent-town-claude-code
  EOS
end
