# agent-town docs

agent-town shows Claude Code's work as a small office building. The user is the CEO. Each Claude Code session is a Chief of Staff. Each subagent is a staff member whose job title matches the work it was given.

The project has two parts:

- **The mod**: a Claude Code plugin that listens to Claude Code events and sends them to the app.
- **The app**: a macOS app that draws the building and plays sounds.

## Documents

| Document | What it covers |
|---|---|
| [spec.md](spec.md) | What the user sees and hears, the decisions made so far, and the settings |
| [architecture.md](architecture.md) | The components, how events flow, and how the mod and the app are built |
| [protocol.md](protocol.md) | The mod-to-app protocol. Platform independent. |
| [roles.md](roles.md) | The staff role catalog and the Chief of Staff's task types (hats) |
| [distribution.md](distribution.md) | How users install the app and the plugin without building from source |
| [roadmap.md](roadmap.md) | Build phases, items to verify before coding, and open questions |
| [verification.md](verification.md) | Phase 0 answers: what the Claude Code mod API provides, checked against the types and a live session |

## Status

Phase 0 (verification) and Phase 1 are done: the catalogs, the protocol schema and fixtures, the debug receiver, and the town-link plugin in `plugin/`, which has been run in a live session against the debug receiver. Phase 0 results are in [verification.md](verification.md). Phase 2, the macOS app, is next.
