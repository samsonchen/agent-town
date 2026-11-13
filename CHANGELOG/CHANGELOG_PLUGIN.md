# town-link: changelog

What changed in each version of town-link, the Claude Code plugin. There are no releases: a version reaches users when `version` in `plugin/.claude-plugin/plugin.json` is raised on `main`, and they run `claude plugin update town-link@agent-town-claude-code`. `git log -- plugin` lists its commits. The macOS and Windows apps have their own changelogs and version numbers. Whether a town-link and an app work together depends only on the protocol version.

## 1.0.5 (2026-11-13)

- An icon for the plugin, and macOS and Windows named in its description.

## 1.0.4 (2026-11-13)

- The marketplace is now `agent-town-claude-code`: install with `town-link@agent-town-claude-code`.
- town-link looks for the app's endpoint file in `~/Library/Application Support/agent-town-claude-code` on macOS and `%APPDATA%\agent-town-claude-code` on Windows. It needs macOS app 1.0.10 or Windows app 1.0.3 or later.

## 1.0.3 (2026-11-12)

- Sends its version in `session.open`, so the app can say when a newer town-link is out.

## 1.0.2 (2026-11-11)

- Works on Windows: finds the Windows app's endpoint file, treats `C:\x` and `c:/x` as the same project, and knows Windows build, test and install commands (`msbuild`, `dotnet`, `winget`, `choco`, `Invoke-WebRequest`).
- `/town` says connected as soon as the app is reachable, early in a session too.

## 1.0.1 (2026-11-11)

- `/town` shows the installed town-link version.

## 1.0.0 (2026-11-11)

- Version 1.0.0, alongside the macOS app. No change in behavior.

## 0.2.5 to 0.3.1 (2026-11-11)

- 0.2.9: fixed resumed agents leaving staff stuck at their desks; messages between agents come through readable.
- 0.2.5: fixed the message `/town on` and `/town off` print.
- 0.2.6 to 0.3.1 changed only the version, to follow the macOS app.

## 0.2.4 (2026-11-11)

- A turn that starts without a prompt, such as after a `!` command, is sent.

## 0.2.3 (2026-11-11)

- Sends the reason a Stop hook gives, for the Inspector at reception.

## 0.2.2 (2026-11-11)

- Where an organization manages Claude Code, town-link no longer uses the classic hooks it would block, and reads the permission mode from settings at session start and from each subagent's start.

## 0.2.1 (2026-11-11)

- Reads the permission mode where an organization manages Claude Code.

## 0.2.0 (2026-11-10)

- Task titles, the kind of task (the Chief of Staff's hat) and staff roles, from short Haiku requests.
- Context use for the context bar, the `/compact` scene (also when another plugin answers the compaction), and the CEO returning when work is done.
- Safe to reload in a running session.

## 0.1.0 (2026-11-09)

The first version: town-link and the `agent-town` marketplace. It sends sessions, prompts, tool calls, subagents, background tasks and approvals to the app over loopback, and `/town` shows whether it is connected.
