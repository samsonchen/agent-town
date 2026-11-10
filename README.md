# agent-town

agent-town shows Claude Code's work as a small office on macOS, seen from above like a Gather Town map, with 3D characters.

- **You are the CEO.** Each prompt you type becomes a ticket that the CEO phones through to the Chief of Staff.
- **Each Claude Code session is a Chief of Staff.** They take the ticket, put on a hat for the kind of task, and get to work.
- **The Chief of Staff dispatches, staff do the work.** For the main agent's own work, the Chief of Staff calls a staff member whose role fits the files being changed (a TypeScript engineer for `.ts`, and so on); each subagent is a staff member too. They report back to the Chief of Staff when done.
- **Background tasks are operators** in the machine room. Scheduled work comes from the Dispatcher, and the Inspector at reception sends unfinished work back.
- **Each project gets its own office block.** Its sign shows the project and a short title for the running task, and a bar under it shows the session's context use. The Chief of Staff phones the report back when the work is done, and sounds tell you when a ticket arrives, when work is done, or when it needs your approval.
- **English and Traditional Chinese**, following the macOS language setting.

It has two parts:

- **town-link**: a Claude Code plugin that observes Claude Code events and sends them to the app over a local connection. It never changes what Claude Code does.
- **The app**: a macOS app that draws the office with RealityKit and plays the sounds.

## Status

The town-link plugin works (Phases 0 and 1). The macOS app shows the executive block and a block per project, with tickets and reports by phone, staff and desk workers called from the bench, operators, approvals, compaction, the context bar and task titles (Phases 2 and 3, mostly done). See [roadmap.md](docs/roadmap.md) for what is left.

To run the app (macOS 15 or later, Xcode installed):

```bash
cd app/macos
swift run AgentTown                       # listens for town-link
swift run AgentTown --demo ../../protocol/fixtures/01-basic-ticket.json   # replays a recorded stream
```

To try the plugin with the stand-in receiver instead, which prints each event:

```bash
python3 tools/debug-receiver.py          # keep it running
claude --plugin-dir plugin               # in another terminal
```

In a session, `/town` shows whether the plugin is connected, and `/town on` or `/town off` turns sending on or off for all sessions. Role and task-type classification uses a short Haiku call on your own Claude plan or API key.

## Known issues

Things you may notice while using agent-town, and what to expect:

- **Automatic compaction may not show.** When Claude Code compacts the conversation on its own because the context is full, the Chief of Staff tidies their notes only if no other plugin writes the summary. With the `cc-plugin-sec-default` plugin installed, the automatic compaction happens but the office shows nothing. Typing `/compact` yourself always shows the scene.
- **Work done while the app is closed is not shown later.** town-link sends events only while the app is running and drops them otherwise. Open the app first; a Claude Code session that is already running shows up within a few seconds of the app starting, from that point on.
- **A session leaves the office about two minutes after it stops.** When a Claude Code session ends or stops responding, its Chief of Staff stays until the app has heard nothing for two minutes.
- **Labels can cover someone near the top of a small window.** Name tags and notes slide down to stay inside the window, so in a short window they may sit over the character's head. Make the window taller or scroll to see them clearly.
- **Task titles and staff roles use your Claude plan.** Each new task makes a short Haiku request on your own plan or API key to pick a title and a role. If that request fails, the sign shows no task title and the hat and roles fall back to defaults.
- **No installer yet.** The app runs from source with Swift (see above); a signed `.app` download is planned.

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
