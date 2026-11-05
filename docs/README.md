# claude-town docs

claude-town shows Claude Code's work as a small office building. The user is the CEO. Each Claude Code session is a Chief of Staff. Each subagent is a staff member whose job title matches the work it was given.

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

## Status

Planning. No code yet. These documents are the input for implementation with Claude Code.
