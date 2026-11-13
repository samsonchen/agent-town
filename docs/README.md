# agent-town docs

agent-town shows Claude Code's work as a small office seen from above. The top-down view was inspired by Gather Town. The user is the CEO. Each Claude Code session is a Chief of Staff. Each subagent is a staff member whose job title matches the work it was given.

The project has two parts:

- **town-link**: a Claude Code plugin (a mod) that listens to Claude Code events and sends them to the app.
- **The app**: a macOS menu bar app, and a Windows tray app, that draw the office and play sounds.

## Documents

| Document | What it covers |
|---|---|
| [office.md](office.md) | A tour of the office: who sits where, what each one does, the sounds and the settings |
| [known-issues.md](known-issues.md) | Known issues and limitations, and which Claude surfaces it works in |
| [privacy.md](privacy.md) | What town-link reads and sends, and what each of its hooks does |
| [development.md](development.md) | Developing: the repository, running from source, checks, trying a change, versions and releasing |
| [spec.md](spec.md) | What the user sees and hears, the decisions made so far, and the settings |
| [architecture.md](architecture.md) | The components, how events flow, and how the mod and the app are built |
| [protocol.md](protocol.md) | The mod-to-app protocol. Platform independent. |
| [roles.md](roles.md) | The staff role catalog and the Chief of Staff's task types (hats) |
| [distribution.md](distribution.md) | How users install the app and the plugin without building from source |
| [releasing.md](releasing.md) | How to build, sign, notarize and publish the macOS app |
| [roadmap.md](roadmap.md) | Build phases, items to verify before coding, and open questions |
| [verification.md](verification.md) | Phase 0 answers: what the Claude Code mod API provides, checked against the types and a live session |
| [windows/](windows/README.md) | The Windows app: its spec, architecture, roadmap, releasing and checks, kept apart from the macOS documents |

## Status

Phase 0 (verification) and Phase 1 are done: the catalogs, the protocol schema and fixtures, the debug receiver, and the town-link plugin in `plugin/`, which has been run in a live session against the debug receiver. Phase 0 results are in [verification.md](verification.md). Phase 2, the macOS app with the office and one project, is done. Phase 3 (staff) is mostly done, Phase 4 (the whole office) is in progress, and Phases 5 (polish) and 6 (release) are partly done: the app is signed, notarized and installs with Homebrew. See [roadmap.md](roadmap.md).
