# Product spec

## Goal

Show the progress of Claude Code work in a visual way that is useful and fun. The user should be able to glance at a second screen and know:

- which projects have work running,
- who is working on what,
- when Claude needs the user's approval,
- when a long task is finished.

## Cast

| Character | Who it represents | How the role is decided |
|---|---|---|
| CEO | The user | Fixed. One CEO for the whole building. |
| Chief of Staff | One Claude Code session (the main agent) | Fixed. One per session. |
| Staff member | One subagent or agent-team teammate | Chosen by a model (Haiku) from the role catalog in [roles.md](roles.md). Accuracy is not critical. |

## The building

- The view is a building with stacked floors, drawn in a 2.5D (isometric) pixel-art style. The reference for the feel is Gather Town; no Gather Town assets are used.
- **One floor per project.** All sessions in the same project share that floor.
- **Several sessions in one project** put several Chiefs of Staff on the same floor. Each one has its own desk and its own staff.
- **The CEO's office is on its own floor at the top** (the executive floor).
- **An elevator** connects the floors. Characters ride it to move between floors.
- All floors are visible at once. There are no tabs. When the floors do not fit in the window, the view scrolls vertically.
- The user sets the window size and the floor size (number of desks per floor). When a floor has more staff than desks, the extra staff use hot desks or the meeting room.
- Each floor shows a sign with the project name.

Proposal to confirm: keep the executive floor pinned at the top of the window while scrolling, so trips to the CEO are always visible.

## Scenes

Each scene below is triggered by a Claude Code event. The event mapping is in [architecture.md](architecture.md).

| # | Trigger | What happens |
|---|---|---|
| 1 | Session starts | A Chief of Staff arrives on the project's floor (the floor is created if it is new) and sits at a desk. |
| 2 | User submits a prompt | The CEO leaves the office, takes the elevator to the floor, hands a ticket to that session's Chief of Staff, and returns. |
| 3 | Main agent works with no subagents active | The Chief of Staff works at the desk and wears a hat showing the task type (see "Hats"). |
| 4 | A subagent starts | A new staff member steps out of the elevator and walks to a free desk. The Chief of Staff hands them a smaller ticket. A name tag shows the role. Until the role is decided, the staff member appears in a neutral outfit. |
| 5 | Someone uses a tool | A short activity animation for that character (see "Activities"). |
| 6 | A tool call needs the user's approval | The character whose call is waiting takes the elevator to the CEO's office and waits there with a raised hand. The approval sound plays. When the call is approved or refused, the character returns to work. |
| 7 | A subagent finishes | The staff member brings a report to the Chief of Staff, then leaves by the elevator. A failed subagent shows a distinct "failed" report. |
| 8 | The main task finishes | The Chief of Staff takes the report to the CEO's office, hands it over, and returns. The completion sound plays if the sound rule below allows it. |
| 9 | The user interrupts the task | The Chief of Staff stops working. No report trip, no sound. |
| 10 | Session ends | The Chief of Staff and any remaining staff leave the floor. An empty floor stays for a configurable time, then is removed. |

### Model badge

Each Chief of Staff and staff member can show a small badge with the model it is running on, such as Haiku, Sonnet, Opus, or Fable. The CEO has no badge.

- The badge shows the model family name. A model ID the app does not recognize is shown as a short form of the raw ID.
- The badge shows the model that actually answered the character's latest request. If the user switches models with `/model`, or a subagent runs on a different model from its parent, the badge follows.
- Until the first request is answered, the badge shows the requested model, if known.
- The Haiku calls claude-town itself makes for role and task-type classification are not shown.
- An app setting shows or hides all badges. Default: hidden.

### Activities

| Tool | Animation |
|---|---|
| Read, Grep, Glob | Reading papers or browsing a bookshelf |
| Edit, Write, NotebookEdit | Typing |
| Bash | Working at a terminal |
| WebSearch, WebFetch | Looking at a globe or a window |
| MCP tools | Using the phone |
| Anything else | Typing |

### Hats

When a session's Chief of Staff has no active subagents, they wear a hat with a short text label showing the task type, such as "Debug" or 「除錯」. The task type is chosen by Haiku from the task type list in [roles.md](roles.md) when the prompt is submitted. While staff are working, the Chief of Staff does not wear a hat.

## Timing rules

- Animations always play at full length, even when Claude finishes first. Example: if a handoff takes 3 seconds and Claude finishes the task in 1 second, the handoff still runs for 3 seconds, then the report trip follows.
- Story events (tickets, reports, approval trips, arrivals and departures) are queued per character and play in order.
- Activity events are not queued. A character shows only the latest activity, so fast tool calls do not build a backlog.

## Sounds

| Sound | When it plays | Rule |
|---|---|---|
| Completion | Scene 8 | Plays only when the end-to-end time of the task is longer than a threshold. The threshold is set by the user. **Minimum 5 seconds.** Default 30 seconds. End-to-end time is measured from prompt submission to the end of the main agent's turn (Claude Code's own duration for the turn), not animation time. Never plays for an interrupted task. |
| Approval needed | Scene 6 | A different sound from completion. Its own on/off setting. Not gated by duration. |

The user can pick the sound file for each, set the volume, or mute all sounds.

## Privacy

The ticket and the report can show text. A setting controls what is shown:

- **Full**: the ticket shows the start of the prompt.
- **Task type only** (for screen sharing and presentations): the ticket shows only the task type label.

The default is to be decided (see [roadmap.md](roadmap.md)).

## Languages

- English and Traditional Chinese (Taiwan) at launch.
- All labels (roles, task types, hats, UI) come from translation tables. Adding a language means adding a column, not changing code.
- Font: 俐方體11號 (Cubic 11, OFL), for both Latin and CJK text.
- Prompt text on tickets is shown as the user typed it.

## Enable and disable

| Level | How |
|---|---|
| Pause visuals and sound | Toggle in the app's menu bar |
| Stop sending events from Claude Code | `/town off` and `/town on` in Claude Code. Saved across sessions. |
| Remove entirely | Disable or uninstall the plugin in `/plugin` |

## Settings (app)

- Language: system, English, 繁體中文
- Window size; floor size (desks per floor)
- Completion sound: on/off, threshold in seconds (minimum 5), sound file
- Approval sound: on/off, sound file
- Master volume, mute
- Ticket text: full, or task type only
- Model badges: show or hide
- How long an empty floor stays before removal
- Pause (same as the menu bar toggle)
- Launch at login

## Where it works

- Claude Code CLI in a terminal, and the Code tab of the Claude Desktop app. Both load mods (Claude Code v2.1.287 or later in the terminal).
- Not supported: Desktop app WSL sessions (plugins are not loaded there) and cloud sessions (they cannot reach the app on the user's Mac).
- `claude -p` runs also load mods. Whether they appear in the building is a setting to decide (see [roadmap.md](roadmap.md)).

## Out of scope for the first version

- Windows and Linux apps. The protocol is designed so they can be added later.
- Approving or refusing a tool call from inside the app. The app only shows that approval is needed.
- Clicking a character to see details.
