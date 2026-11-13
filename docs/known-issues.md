# Known issues and where it works

## Known issues and limitations

- **Where your organization manages Claude Code, some scenes may not show.** On a Team or Enterprise login, Claude Code passes some events over the plugins you install yourself, and town-link is one of them. You can see this in `/plugin` → Errors. On a personal account these scenes work.
  - Automatic compaction: when Claude Code compacts the conversation on its own because the context is full, the office shows nothing. Typing `/compact` yourself always shows the scene.
  - Returned work: the Inspector's scene may not appear when a hook sends Claude Code back to work. The work itself goes on as usual.
  - The approval sound in auto mode: agent-town normally stays quiet when auto mode's classifier answers an ask. Under an organization it knows your permission mode only from your settings when a session starts, so if you switch to auto mode with Shift+Tab, a slow ask may still play the approval sound.
- **Work done while the app is closed is not shown later.** town-link sends events only while the app is running and drops them otherwise. A Claude Code session that is already running shows up within a few seconds of the app starting, from that point on.
- **Commands you run with `!` don't show in the office.** Claude Code runs them in your shell without the model, and tells plugins nothing about them. If Claude goes on working after one, that work shows as usual, with the Chief of Staff's note reading "Continuing".
- **A session that stops responding leaves the office about two minutes later.** When a Claude Code session ends normally, its Chief of Staff leaves right away. When it stops responding (for example, the terminal was killed), its Chief of Staff stays until the app has heard nothing for two minutes.
- **Labels can cover someone near the top of a small window.** Name tags and notes slide down to stay inside the window, so in a short window they may sit over the character's head. Make the window taller or scroll. A character scrolled out of view above the window has no tag shown.
- **Tags can overlap in compact view.** The text is 75% of its normal size on an office at half size, so tags of characters side by side (two Chiefs of Staff, for example) can overlap, mostly in a narrow window.
- **Task titles and staff roles use your Claude plan.** Each new task makes a few short Haiku requests on your own plan or API key to pick a title, the kind of task and staff roles. If a request fails, the sign shows no task title and the hat and roles fall back to defaults.
- **One project block shows up to five sessions.** The back row has five desk spots, shared by the Chiefs of Staff and by staff who carry in a desk when the front desks are full. A Chief of Staff who arrives when all five are taken stands on the first desk's spot, over the Chief already there.
- **macOS 15 or Windows 11.** The macOS app needs macOS 15 or later; the Windows app needs Windows 11 (x64; Windows 10 is allowed but untested) and native Windows Claude Code sessions (not WSL).

## Where it works: Claude Desktop, Cowork and others

agent-town works wherever a Claude Code session runs on the same computer as the app, because town-link sends its events to the app over a local connection. The table speaks of a Mac; on Windows the same holds for native Windows sessions (not WSL).

| Where you use Claude | Works? | Why |
|---|---|---|
| Claude Code in a terminal | Yes | |
| Claude Desktop, Code tab, local session | Yes | Plugin modules run there (Claude Code v2.1.286 or later), and the session runs on your Mac. |
| VS Code extension, JetBrains terminal | Yes | They run Claude Code on your Mac. |
| Claude Desktop, Code tab, cloud session | No | The session runs on Anthropic's servers, which can't reach the app on your Mac, and plugins installed on your Mac aren't loaded there. |
| Claude Desktop, Code tab, SSH or WSL session | No | The session runs on another machine (SSH), or doesn't load plugins (WSL). |
| Claude Code on the web (claude.ai/code) | No | Cloud sessions, as above. |
| Cowork | Not supported | Cowork takes its plugins from your claude.ai account, not from Claude Code, and runs its commands in a separate Linux virtual machine. Its docs don't say that plugin modules like town-link run there, and I have not tested it. |
| Chats in the Claude app | No | Chats are not Claude Code sessions. |

These come from Claude Code's documentation as of November 2026. agent-town itself has been tested in the terminal only.
