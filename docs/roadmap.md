# Roadmap

## Phase 0: verify before building

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
| 11 | Format of `result.usage.model` in `turn.step`, and whether it is present for every request | Model badges | `$.session.model()` for the Chief of Staff, the `agent.spawn` model (or its parent's) for staff |

Record the answers in `docs/verification.md`.

## Phase 1: protocol and mod

- `catalog/roles.json`, `catalog/task-types.json` from [roles.md](roles.md)
- `protocol/schema/` and a few recorded streams in `protocol/fixtures/`
- The mod: event mapping, outbox, endpoint file, `/town`, classification
- Mod tests with `claude plugin test`
- A debug receiver: a small script or a bare app window that prints incoming events. Used to look at real event timing.

## Phase 2: one floor

- App shell, loopback server, endpoint file, building state, choreographer
- Executive floor and one project floor
- CEO, Chief of Staff, ticket and report scenes (2, 8, 9)
- Completion sound with the duration gate
- State tests driven by `protocol/fixtures/`

## Phase 3: staff

- Staff hire, roles, desks, report back, failure (scenes 4, 7)
- Activities (scene 5)
- Approval trip and approval sound (scene 6)

## Phase 4: the building

- Several floors, elevator, vertical scrolling
- Several sessions on one floor
- Stale-session cleanup, empty-floor removal
- Window and floor size settings

## Phase 5: polish

- Hats (scene 3)
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
