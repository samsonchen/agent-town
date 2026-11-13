cask "agent-town" do
  version "1.0.12"
  sha256 "a6529b3c9701f469749dacc1bbc3fd7fe8489e7f03eaff9e54c458dfd4c98e80"

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
