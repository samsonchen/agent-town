# agent-town

agent-town shows Claude Code's work as a small 3D office building on macOS.

- **You are the CEO.** Each prompt you type becomes a ticket on the Chief of Staff's desk.
- **Each Claude Code session is a Chief of Staff.** They take the ticket, put on a hat for the kind of task, and get to work.
- **Subagents are staff.** The Chief of Staff calls them from the resource bench, and each one gets a job title that matches the work it was given.
- **Background tasks are operators** in the machine room. Scheduled work comes from the Dispatcher, and the Inspector at reception sends unfinished work back.
- **Each project gets its own floor.** Sounds tell you when work is done or needs your approval.

It has two parts:

- **town-link**: a Claude Code plugin that observes Claude Code events and sends them to the app over a local connection. It never changes what Claude Code does.
- **The app**: a macOS app that draws the building with RealityKit and plays the sounds.

## Status

The town-link plugin works and has been tested in a live session (Phases 0 and 1). The macOS app is next (Phase 2), so there is nothing to see yet.

To try the plugin with the stand-in receiver, which prints each event:

```bash
python3 tools/debug-receiver.py          # keep it running
claude --plugin-dir plugin               # in another terminal
```

In a session, `/town` shows whether the plugin is connected, and `/town on` or `/town off` turns sending on or off for all sessions. Role and task-type classification uses a short Haiku call on your own Claude plan or API key.

## Documentation

Start with [docs/README.md](docs/README.md). It links to:

- [Spec](docs/spec.md): what you see and hear
- [Architecture](docs/architecture.md): how the plugin and the app are built
- [Protocol](docs/protocol.md): the messages between the plugin and the app
- [Roles](docs/roles.md): job titles, departments and task types
- [Distribution](docs/distribution.md): how it will be installed
- [Roadmap](docs/roadmap.md): build phases and open questions
- [Verification](docs/verification.md): what the Claude Code mod API provides

## Install (planned)

```
/plugin marketplace add samsonchen/agent-town
/plugin install town-link@agent-town
```

The macOS app will come from GitHub Releases or Homebrew. See [distribution.md](docs/distribution.md).

## License

Apache 2.0. See [LICENSE](LICENSE). The 3D models are Kenney assets under CC0. See [assets/LICENSES.md](assets/LICENSES.md).
