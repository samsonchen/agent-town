# Roadmap

## Phase 0: verify before building (done)

These points come from the mods documentation and the type declarations, but were not fully confirmed. Check each one against the `claude-code.d.ts` that Claude Code writes for the installed version, or with a small test mod, before writing the real code.

| # | Question | Why it matters | Fallback if the answer is no |
|---|---|---|---|
| 1 | Can `$.http.fetch` reach `http://127.0.0.1`? Is it blocked by the built-in guard or managed settings? | The whole transport depends on it | The mod runs a small sender CLI with `$.process.run`, or writes events to a file the app watches |
| 2 | `turn.complete` fields: `durationMs`, `isAborted`, `agentId` | Sound gate and scene 9 | Measure duration from `turn.start` to `turn.complete` with `$.clock.now()` |
| 3 | `agent.spawn`: does `await next(e)` return `agentId` in time to send `staff.hire`? | Linking a hire to its later events | Use `tool_use_id` as the staff key until the `agentId` is known |
| 4 | `tool.call`: is `agentId` present for subagent calls? | Showing activity on the right character | Use `tool.check`, which has `agentId` |
| 5 | How to tell that an `ask` was answered (allowed or refused) | `approval.end` | Treat the next event from that agent as the end of the wait |
| 6 | `$.model.classify`: how to choose Haiku, how many labels it accepts, its cost and delay | Role and hat classification | `$.model.complete` with a Haiku prompt that returns one ID; or the two-step department-then-role split |
| 7 | Shape of `$.session.repo()` | Project identity | `$.session.root()` |
| 8 | Do mods load the same way in the Desktop app's Code tab? | Supported surfaces | Document the CLI as the supported surface |
| 9 | When a background subagent is still running after the main turn ends, what events arrive? | Scene 7 and 8 order | Keep staff working on the floor after the report trip |
| 10 | `claude plugin marketplace add` from the shell | One-click install from the app | Show the `/plugin` commands to copy |
| 11 | Is `turn.step` a generator hook (`yield* next(e)`)? Format of `result.usage.model`, and is it present for every request? | Model badges; correct pass-through | `$.session.model()` for the Chief of Staff, the `agent.spawn` model (or its parent's) for staff |
| 12 | Do `$.model.classify` calls go through `turn.step`? If so, can the mod tell them apart from the session's own requests? | Keeping agent-town's Haiku calls off the badges | Take the Chief of Staff's model only from `$.session.model()` on `prompt.submit` and `turn.complete`; use `turn.step` for staff only |
| 13 | When a main-agent turn starts without `prompt.submit`, which event marks the start, and can the mod read its input (a task notification or a scheduled prompt)? | Turn origin for follow-up and scheduled tickets | Infer the origin from timing: a task that just ended means `task`; a schedule due within a few seconds means `schedule`; otherwise `unknown` |
| 14 | Is there an event when a background task ends, with its ID and exit status? | `task.done` without waiting for the next turn | Read the end from the task notification at the start of the next main turn; poll a task list on the heartbeat, if the mod API offers one |
| 15 | Can the mod see a Stop hook block the end of the main turn? Does `turn.complete` fire once per stop attempt or once per real end? | Scene 15 and correct `ticket.done` timing | Send `ticket.done` at each `turn.complete`. A continuation then shows as a new ticket with `origin: unknown`, and there is no Inspector scene. |
| 16 | Do agents started by a `Workflow` run appear as `agent.spawn`, and can they be linked to the run? | Workflow staff reporting to the coordinator | Show them as ordinary staff of the Chief of Staff |
| 17 | Which tools create and delete schedules in the installed version (`CronCreate`, `CronDelete`, `ScheduleWakeup`), and what do their inputs and results contain? | Dispatcher board | Show a scheduled ticket when it fires, without a card on the board |
| 18 | Are agent-to-agent messages (`SendMessage`, agent-team messages) visible as `tool.call` with the sender's `agentId`, and does the input name the receiver in a form the mod can match to an `agent.spawn`? | Scene 16 | Show a speech bubble over the sender only |
| 19 | Can RealityKit on macOS load the converted USDZ, play the skeletal animation, cut it into clips by time, and swap a character's texture at run time? Is an orthographic camera available in `RealityView`? | The whole scene | SceneKit with the same USDZ files; or pre-render clips to 2D sprite sheets in Blender and use SpriteKit |

Answers: [verification.md](verification.md). Most items are answered by the API types. The rest need the recorder mod in a real session.

## Phase 1: protocol and mod (done)

- `catalog/roles.json`, `catalog/task-types.json` from [roles.md](roles.md); `catalog/models.json`
- `protocol/schema/` and a few recorded streams in `protocol/fixtures/`
- The mod: event mapping, outbox, endpoint file, `/town`, classification
- Mod tests with `claude plugin test`
- A debug receiver: a small script or a bare app window that prints incoming events. Used to look at real event timing.

## Phase 2: one floor (mostly done)

- [x] App shell, loopback server, endpoint file, building state, choreographer
- [x] Executive floor and project floors (stacked apart as an exploded view, with an elevator shaft)
- [x] CEO, Chief of Staff, ticket and report scenes (1, 2, 8, 9, 10)
- [x] Completion sound with the duration gate (system sound for now)
- [x] State tests driven by `protocol/fixtures/` (`swift test` in `app/macos`)
- [x] Offscreen snapshots for checking scenes: `AgentTown --demo <fixture> --snapshot out.png --at 10`
- [ ] Settings window (threshold, sounds, ticket text, badges, language); Cubic 11 font
- [ ] An `.app` bundle (the package runs as a bare executable for now)

## Phase 3: staff

- Resource bench: idle animations, calling from the bench, return to the bench (scenes 4, 7)
- Staff roles, desks, report back, failure (scenes 4, 7)
- Agent-to-agent messages (scene 16)
- Activities (scene 5)
- Approval trip and approval sound (scene 6)
- Operators: background tasks, machine room, follow-up tickets, background roles by rule (scenes 11, 12)

## Phase 4: the building

- Several floors, elevator, vertical scrolling
- Several sessions on one floor
- Stale-session cleanup, empty-floor removal
- Window and floor size settings
- Executive floor rooms: Dispatcher's room and board, scheduled tickets (scenes 13, 14); reception desk and Inspector (scene 15)

## Phase 5: polish

- Hats (scene 3)
- Model badges, with the show/hide setting (default hidden)
- English and Traditional Chinese, Cubic 11 font
- Ticket text setting, all other settings, launch at login
- Menu bar toggle

## Phase 6: release

- Signing and notarization in GitHub Actions
- DMG on Releases, Homebrew cask, Sparkle
- `marketplace.json`, README with install steps and the list of events the mod handles
- `CONTRIBUTING.md`, `assets/LICENSES.md`

## Open questions

| Question | Options |
|---|---|
| Default for ticket text | Full prompt text, or task type only |
| Should `claude -p` and Agent SDK runs appear in the building? | Yes, no, or a setting (default off) |
| Pin the executive floor at the top while scrolling? | Pinned, or scrolls with the rest |
| How long an empty floor stays | A fixed default (for example 10 minutes), or until the app restarts |
| Sound files | Pick from CC0 libraries, or commission original ones |
| Default bench size, and whether the bench is per floor (current spec) or one shared bench on a lower floor | Per floor keeps calls fast; a shared bench means elevator trips |
| Where the report for a scheduled ticket goes | The Dispatcher's room (current spec), or the CEO's office like every other report |
| Long-lived operators (dev servers) | Stay in the machine room until killed or the session ends (current spec), or move to a smaller "on duty" spot after a few minutes |
