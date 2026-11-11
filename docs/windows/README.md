# agent-town for Windows: docs

The Windows version of the agent-town app, planned and in progress. It draws the same office as the macOS app, from the same protocol and the same town-link plugin. These documents cover only what is specific to Windows. Everything they do not mention follows the main documents in [`docs/`](../README.md): the office, the scenes and the timing rules in [spec.md](../spec.md), the event mapping in [architecture.md](../architecture.md), and the protocol in [protocol.md](../protocol.md).

## Documents

| Document | What it covers |
|---|---|
| [spec.md](spec.md) | What the first version includes, and how it differs from the macOS app |
| [architecture.md](architecture.md) | The Godot app: its modules and how it uses the shared files |
| [roadmap.md](roadmap.md) | Phases W0 to W2 |
| [verification.md](verification.md) | What was checked on Windows, and what is still to check |

## Status

W0 (verify before building) is nearly done. town-link works on Windows, and the Godot checks passed, and the native add-on that keeps the window off the taskbar works. What is left: town-link in interactive sessions, and running the ARM64 build on an ARM machine. See [roadmap.md](roadmap.md).
