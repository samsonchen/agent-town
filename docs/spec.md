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
| Operator | One background task (a background shell command, a monitor, a workflow run) | From the background roles in [roles.md](roles.md): by rule where possible, otherwise by Haiku. |
| Dispatcher | The schedules of every session (`/loop`, cron-style tasks, scheduled wakeups) | Fixed. One for the whole building. |
| Inspector | Hooks that stop the main agent from finishing and send it back to work | Fixed. One for the whole building. |

Every piece of work starts with a ticket, and every ticket has an issuer. The report goes back to the issuer. The CEO issues tickets for prompts. The Dispatcher issues tickets for schedules. An operator's result brings follow-up work to the Chief of Staff, but the report from that work goes to whoever issued the ticket that started the operator.

## The building

- The view is a building with stacked floors, drawn in a 2.5D (isometric) pixel-art style. The reference for the feel is Gather Town; no Gather Town assets are used.
- **One floor per project.** All sessions in the same project share that floor.
- **Several sessions in one project** put several Chiefs of Staff on the same floor. Each one has its own desk and its own staff.
- **The executive floor** is its own floor at the top. It has three rooms:
  - the CEO's office;
  - the Dispatcher's room, with a board that shows one card for each active schedule, labeled with the project name;
  - the reception desk in front of the CEO's office, where the Inspector sits.
- **Each project floor has a machine room** in one corner, with consoles and server racks. Operators work there, apart from the staff desks.
- **Each project floor has a resource bench** (待命室): a lounge where staff and operators wait between jobs. See "Resource bench" below.
- **An elevator** connects the floors. Characters ride it to move between floors.
- All floors are visible at once. There are no tabs. When the floors do not fit in the window, the view scrolls vertically.
- The user sets the window size, the floor size (number of desks per floor), and the bench size (number of characters waiting on each bench). When a floor has more staff than desks, the extra staff use hot desks or the meeting room.
- Each floor shows a sign with the project name.

Proposal to confirm: keep the executive floor pinned at the top of the window while scrolling, so trips to the CEO are always visible.

## Scenes

Each scene below is triggered by a Claude Code event. The event mapping is in [architecture.md](architecture.md).

| # | Trigger | What happens |
|---|---|---|
| 1 | Session starts | A Chief of Staff arrives on the project's floor (the floor is created if it is new) and sits at a desk. |
| 2 | User submits a prompt | The CEO leaves the office, takes the elevator to the floor, hands a ticket to that session's Chief of Staff, and returns. |
| 3 | Main agent works with no subagents active | The Chief of Staff works at the desk and wears a hat showing the task type (see "Hats"). |
| 4 | A subagent starts | The Chief of Staff walks to the resource bench and calls a waiting character (see "Resource bench"). The Chief of Staff hands them a smaller ticket there. The character walks to a free desk and starts work. The name tag shows the role. If no role is decided yet when the character leaves the bench, they keep a neutral outfit until it is. |
| 5 | Someone uses a tool | A short activity animation for that character (see "Activities"). |
| 6 | A tool call needs the user's approval | The character whose call is waiting takes the elevator to the CEO's office and waits there with a raised hand. The approval sound plays. When the call is approved or refused, the character returns to work. |
| 7 | A subagent finishes | The staff member brings a report to the Chief of Staff, then walks back to the resource bench and waits there, still in their role outfit. A failed subagent shows a distinct "failed" report. |
| 8 | The main task finishes | The Chief of Staff takes the report to the CEO's office, hands it over, and returns. The completion sound plays if the sound rule below allows it. |
| 9 | The user interrupts the task | The Chief of Staff stops working. No report trip, no sound. |
| 10 | Session ends | The Chief of Staff leaves the floor by the elevator. Any remaining staff and operators go back to the resource bench. The session's cards are removed from the Dispatcher's board. An empty floor stays for a configurable time, then is removed. |
| 11 | A background task starts | The character that started the task (the Chief of Staff, or a staff member) walks to the resource bench and calls a waiting operator. The operator walks into the machine room and starts work at a console. The name tag shows the background role. If no role is decided yet when the operator leaves the bench, they keep a neutral outfit until it is. |
| 12 | A background task finishes | The operator brings the result to the Chief of Staff and walks back to the resource bench. If Claude Code then starts a new turn to handle the result, the Chief of Staff works on it as a follow-up ticket. No one makes a trip from the CEO's office for it. When that turn ends, the report goes to the issuer of the ticket that started the operator (scene 8). A failed task shows a distinct "failed" result. A task that is stopped (killed) leaves with no result. |
| 13 | A schedule is created or deleted | A card is pinned to or removed from the Dispatcher's board. |
| 14 | A schedule fires | The Dispatcher takes the card's ticket down the elevator to the floor and hands it to that session's Chief of Staff, the same way the CEO does in scene 2. When the turn ends, the Chief of Staff takes the report to the Dispatcher's room, not to the CEO. |
| 15 | A hook sends the main agent back to work | The Chief of Staff is on the way to hand in the report. At the reception desk, the Inspector stamps it "Returned" (「退回」) and hands it back. The Chief of Staff returns to the desk and keeps working on the same ticket. The ticket ends when a later report gets past the Inspector. |
| 16 | One agent sends a message to another | The sender walks to the receiver's desk, a speech bubble shows over both for a moment, and the sender walks back. This applies to staff and agent-team teammates messaging each other, to the Chief of Staff messaging a staff member, and to a staff member messaging the Chief of Staff. The bubble shows no message text. |

Scene 15 happens when a Stop hook, such as a check that tests pass or a rule that a to-do list must be finished, refuses to let the main agent end its turn. To the user, the task is still running. The Inspector makes that visible. For a subagent held back by its own Stop hook, the Chief of Staff hands the staff member's report back at the desk instead.

### Resource bench

The resource bench is a lounge on each project floor. Every session on the floor shares it. The characters there are not working. They move around and do idle things: chat, drink coffee, read a magazine, stretch, look at their phone, play darts. These idle animations are different from the work activities, so a glance tells waiting apart from working.

**Who is on the bench**

- A new floor starts with a mixed bench: a few characters in common outfits (engineering hoodie, operator vest) and a few in a neutral outfit. The bench size setting sets how many.
- Characters who finish a job come back to the bench in their role outfit, with a faint name tag. Over time, a project's bench shows the kinds of roles that project uses.
- When the bench has more characters than its size, the ones who have waited longest leave by the elevator.

**Calling from the bench (scenes 4 and 11)**

1. The Chief of Staff walks to the bench. If role classification has not finished yet, they wait at the bench for up to 3 seconds.
2. The Chief of Staff calls one character, picked in this order:
   1. a waiting character who last had the same role;
   2. a waiting character from the same department (same outfit);
   3. a neutral character, who changes into the role outfit;
   4. anyone waiting, who changes outfit.
3. If the bench is empty, a new character steps out of the elevator and comes to the bench to be called.
4. Subagents or tasks that start within about 1 second of each other are called in one trip. The Chief of Staff calls several characters at once.
5. The called characters walk to free desks (staff) or to the machine room (operators).

An operator can be called back from the bench as staff, and the other way around. They change outfit on the way.

### Model badge

Each Chief of Staff and staff member can show a small badge with the model it is running on, such as Haiku, Sonnet, Opus, or Fable. The CEO has no badge.

- The badge shows the model family name, looked up in `catalog/models.json`. A model ID that matches no entry is shown in short form, for example `foo-2-5` for `claude-foo-2-5-20260101` (rules in [architecture.md](architecture.md)).
- The badge shows the model that actually answered the character's latest request. If the user switches models with `/model`, or a subagent runs on a different model from its parent, the badge follows.
- Until the first request is answered, the badge shows the requested model. For a subagent with no requested model, this is the parent's current model: the Chief of Staff's, or the parent staff member's for a nested subagent.
- The Haiku calls claude-town itself makes for role and task-type classification are not shown.
- An app setting shows or hides all badges. Default: hidden.

### Activities

| Tool | Animation |
|---|---|
| Read, Grep, Glob | Reading papers or browsing a bookshelf |
| Edit, Write, NotebookEdit | Typing |
| Bash | Working at a terminal |
| Background task (operator) | Working at a console in the machine room, with a looping animation for the role (see [roles.md](roles.md)) until the task ends |
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
| Completion | Scene 8 | Plays only when the end-to-end time of the task is longer than a threshold. The threshold is set by the user. **Minimum 5 seconds.** Default 30 seconds. End-to-end time is measured from prompt submission to the end of the main agent's turn (Claude Code's own duration for the turn), not animation time. For a follow-up ticket from a background task, it is measured from the start of that task. For a returned ticket (scene 15), it covers all of the work until the report is accepted. For a scheduled ticket, it is measured from the time the schedule fired. Never plays for an interrupted task. |
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
- Window size; floor size (desks per floor); bench size (characters waiting per floor)
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
