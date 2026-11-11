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
| 9 | When a background subagent is still running after the main turn ends, what events arrive? | Scene 7 and 8 order | Keep staff working in the block after the report call |
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

## Phase 2: the office and one project (done)

- [x] App shell, loopback server, endpoint file, building state, choreographer
- [x] Gather-style office: flat blocks on a path, no walls or doors, 3D characters and furniture at half the first size
- [x] Executive block and one block per project, stacked in one column with the window growing to fit; a project's block shows from its session's start and goes when its last session ends
- [x] Telephones: the CEO phones the ticket to the Chief of Staff, who phones the report back (the Dispatcher uses a radio)
- [x] CEO, Chief of Staff, ticket and report call scenes (1, 2, 8, 9, 10)
- [x] Completion sound with the duration gate (system sound for now)
- [x] State tests driven by `protocol/fixtures/` (`swift test` in `app/macos`)
- [x] Offscreen snapshots for checking scenes: `AgentTown --demo <fixture> --snapshot out.png --at 10`
- [x] Menu bar app with no Dock icon: About, Show agent-town, Sound, Show tips, Settings…, Quit; choices kept across restarts
- [x] Settings window: language (with Restart now) and open at login. Threshold, sounds, ticket text and badges move to Phase 5
- [x] An `.app` bundle and `.dmg` from `app/macos/scripts/release.sh` (unsigned for now; see [releasing.md](releasing.md))
- [x] The window opens where it was when the app last quit

## Phase 3: staff (mostly done)

- [x] Resource bench: a mixed bench in each new block, paging the bench over its speaker from the desk (one page for hires within a second, waiting up to 3 seconds for roles, the picking order), return to the bench with a faint name tag, the longest-waiting leave when the bench is full (scenes 4, 7)
- [x] Staff roles and department outfit colors, staff desks (hot desks past five), report back to whoever started the job, "Failed" reports (scenes 4, 7)
- [x] Agent-to-agent messages: the sender walks over and both show a speech bubble (scene 16)
- [x] Activities for the Chief of Staff and staff (scene 5)
- [x] Approval: the waiting character shows "Needs approval", a line runs to the CEO, and the CEO's phone rings until it is answered; approval sound (scene 6)
- [x] Operators in safety orange at the server room racks; results back to the Chief of Staff; killed tasks leave with no result (scenes 11, 12)
- [x] Walkways: characters walk along the walkways and between desks, not through them
- [ ] Props in hand (laptop, clipboard, stopwatch …) and a looping animation per background role
- [ ] More idle life on the bench (coffee, magazine, darts); sitting on the sofa
- [ ] Workflow subagents report to the workflow coordinator (Phase 0 item 16)
- [ ] Name tags that move apart when characters stand close together
- [x] Blocks on screen: every open project's block, from its session's start until its last session ends; no walk-in or walk-out
- [x] Typing at desks, writing at hot desks; no approval sound in auto mode
- [x] Walking the CEO with the arrow keys, H to go back to the desk, a closable tip, the view following the CEO, a mobile phone away from the desk, and status statements from the character the CEO stands next to
- [x] Clicking a character walks the CEO there; the CEO walks back to the desk once all work is done
- [x] Desk workers: the Chief of Staff calls a staff member by role (from the files being changed) to do the main agent's own work, one person per role (the others wait at their desks until the ticket ends), and waits for the reports before phoning the CEO (scene 3)
- [x] Compaction scene (scene 17)
- [x] Context bar under each block: fill, used / window, percent, the last turn's new tokens
- [x] Task titles from Haiku on the block sign, scrolling when wider than 20 columns
- [x] Dispatch sound as a ticket's call rings
- [x] Six desks per block (one Chief of Staff desk, five staff desks); a second session's Chief, and staff past five, carry a desk in and out of the back row

## Phase 4: the whole office (in progress)

- [x] Executive block: the Dispatcher's board and scheduled tickets (scenes 13, 14); the Inspector at reception (scene 15)
- [ ] Many project blocks: zoom (blocks are one column now; a taller office scrolls)
- [ ] Several sessions in one block: check the walk-in desk scene and the limit of four (two sessions work)
- [ ] Window and bench size settings

## Phase 5: polish

- Hats (scene 3)
- Model badges, with the show/hide setting (default hidden)
- [x] English and Traditional Chinese string tables, following the macOS language (Simplified Chinese falls back to English)
- Cubic 11 font
- Ticket text setting, completion threshold and sound settings, model badge setting
- [x] Launch at login (Settings → Open at login)
- [x] Menu bar menu

## Phase 6: release

- Signing and notarization in GitHub Actions
- DMG on Releases, Homebrew cask, Sparkle
- [x] `marketplace.json`; README with install steps
- The list of events the mod handles, in the README or a doc
- `CONTRIBUTING.md`, `assets/LICENSES.md`

## Open questions

| Question | Options |
|---|---|
| Default for ticket text | Full prompt text, or task type only |
| Should `claude -p` and Agent SDK runs appear in the building? | Yes, no, or a setting (default off) |
| Sound files | Pick from CC0 libraries, or commission original ones |
| Default bench size, and whether the bench is per block (current spec) or one shared bench | Per block keeps calls fast; a shared bench means walks across the office |
| Long-lived operators (dev servers) | Stay in the server room until killed or the session ends (current spec), or move to a smaller "on duty" spot after a few minutes |
