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

## The office

- The view is an office seen from above. The floor plan is flat and 2D: blocks of tiled carpet on a cream path, with no walls or doors. The characters and furniture are low-poly 3D (an orthographic camera tilted a little from straight down; characters lean toward the camera so they show their fronts). Characters and furniture come from Kenney's CC0 packs (Mini Characters, Furniture Kit); see [roles.md](roles.md) and [distribution.md](distribution.md). The top-down view was inspired by Gather Town; no Gather Town assets are used.
- **One block per project.** All sessions in the same project share that block. Project blocks are stacked in one column under the executive block, with a path between them, in the order their projects opened.
- **Every open project is on screen** (the default). A project's block appears as soon as its first session opens, before any prompt, with the Chief of Staff at the desk, and stays until its last session ends. Nobody walks in or out; the view simply changes. With no session open, the office is the executive block alone.
- **Hide idle project blocks** (a setting, off by default). With it on, a project's block is on screen only while it has work: it appears when work begins (a prompt, a scheduled ticket, a background task, a subagent, an approval, a compaction) and hides once everything in it has settled (the report call made, staff and operators back on the bench) for the number of seconds set beside the setting (1 to 3600, default 5). The window shrinks and grows with it. While hidden, the block keeps its sessions, desks and bench, and things in it still happen off screen (a second Chief of Staff arriving, staff going back), so it comes back as it would have looked. No block hides while the user has walked the CEO away from the desk; the CEO goes home when all work is done, and idle blocks hide after that. Turning the setting off brings every hidden block back. A hidden block's context bars stay on screen, so idle sessions can still be seen: one bar per session, named by its project ("agent-town · Context 23% …", with the desk when the project has several sessions), listed under the executive office in the order the projects opened, whether or not other project blocks are shown. The project blocks move down to make room, and the window grows to fit.
- **The window grows with the office.** When a block is added or removed, the window's height changes to fit the office at its current width, with the top edge kept in place. It never grows past the screen; a taller office scrolls. A size the user drags to holds until the next block is added or removed.
- **The window opens where it was.** Its position and width are kept when the app restarts, on the same display, if that display is still connected; otherwise macOS places it. The height still follows the office.
- **Several sessions in one project** put several Chiefs of Staff in the same block. Each one has its own desk, telephone and staff.
- **Six desks per project block.** The back row has one Chief of Staff desk with a telephone; the front row has five staff desks. The rest of the back row is open floor. A second session's Chief of Staff walks in from the path carrying a desk with a telephone, sets it down in the back row, and carries it out again when the session ends, even if the session ends before the desk is set down. Until that desk is gone, nobody else takes its place. When all five staff desks are taken, the next staff member paged is a newcomer who walks in carrying a desk for the back row; after reporting, they pick the desk up and leave along the path instead of joining the bench. Carried desks look smaller while carried, held above the head. With the back row full too, extra staff work standing at the hot desks by the bench. The back row has five desk spots, shared by Chiefs of Staff and staff carrying desks in, so a block shows up to five sessions. A Chief of Staff who arrives when all five are taken stands on the first desk's spot (a known limit; see the README).
- **The executive block** is a strip across the top, above the first project block: as wide as a project block and a third as deep, so the window stays small. The CEO, the Inspector and the Dispatcher stand in one row along its back, each behind a desk, with the block's sign on its front edge:
  - the CEO's desk, with a telephone. The CEO stays at the desk unless the user walks the CEO around (see "Walking the CEO" below);
  - the reception desk, with a telephone, where the Inspector stands;
  - the Dispatcher's desk, with a radio, and a board on the back wall beside it that shows one card for each active schedule, in the color of its project's block. The board holds six cards (two rows of three); more schedules are counted but get no card. A line on the floor under the board names the projects with schedules, with a count for a project that has more than one, such as "agent-town ×2 · care-portal".
- **Telephones** carry tickets and reports. The CEO phones a Chief of Staff with a ticket, and a Chief of Staff phones the CEO with the report. During a call both people hold the handset, the other phone rings first, and a dashed line joins the two. When the CEO is away from the desk, the CEO's calls use a mobile phone instead.
- **Each project block has a server room** in one corner, with consoles and server racks. Operators work there, apart from the staff desks.
- **Each project block has a resource bench** (待命室): a lounge where staff and operators wait between jobs. See "Resource bench" below.
- The whole office is visible at once. There are no tabs. When it does not fit in the window, the view pans with the scroll wheel or trackpad, and it follows the CEO when the user walks the CEO around.
- The user sets the window size and the bench size (number of characters waiting on each bench).
- Each block shows a sign with the project name. While a typed prompt is being worked on, the sign adds a short title naming the task, written by Haiku from the prompt, for example "agent-town · Fix missing sound" (two tasks at most, by desk). A title is asked to be at most 20 characters, or 10 Chinese characters (a CJK character counts as two). When the titles are wider than that, the whole sign (name and titles) scrolls sideways in a window 20 characters wide. Before the project name is known, the sign shows the project ID, a 16-character hash; with a task running it shows the task title instead.

## Scenes

Each scene below is triggered by a Claude Code event. The event mapping is in [architecture.md](architecture.md).

| # | Trigger | What happens |
|---|---|---|
| 1 | Session starts | The session's Chief of Staff is at the block's Chief of Staff desk, with no walk-in (the block is created if it is new). If that desk is taken by another session, the new Chief of Staff walks in carrying a desk (see "Six desks per project block"). Whether the block is on screen follows the rule above. |
| 2 | User submits a prompt | The CEO phones that session's Chief of Staff. The Chief of Staff's phone rings and is answered, and the ticket passes from the CEO to the Chief of Staff over the call. A short dispatch sound plays as the phone rings. |
| 3 | Main agent uses its first tool on a ticket | The Chief of Staff does not do the work itself: it pages a desk worker from the resource bench, as in scene 4, and the main agent's own tool calls (activities, approvals) show on that worker. The role comes from the files being changed (a `.ts` file brings a TypeScript engineer, `.swift` a Swift engineer, `.md` a technical writer), else from a file being read or the task type, else a generalist. Each role on a ticket is its own person: when the work moves to another role (a file of another kind is changed, or web research starts), the Chief of Staff pages someone new for it, and the earlier worker stays at the desk, idle, until the ticket ends. When the work comes back to a role, that person picks it up again with no new page. Reading a file does not move the work. A first guess is corrected on the same character only while they are still on the way (about 3 seconds). At most five desk workers per ticket; past that, the one idle longest reports and goes back first. When the ticket ends (the turn is over, including when Claude stops to ask the user something), every desk worker brings a report to the Chief of Staff and goes back to the bench. They stay at their desks through an approval wait. While staff work, the Chief of Staff waits at the desk instead of typing. A turn with no tool calls (an answer only) stays with the Chief of Staff, who wears a hat showing the task type (see "Hats"). |
| 4 | A subagent starts | The Chief of Staff pages a waiting character over the bench speaker, from the desk (see "Resource bench"). The character takes a smaller ticket and walks to a free desk and starts work. The name tag shows the role. If no role is decided yet when the character leaves the bench, they keep a neutral outfit until it is. |
| 5 | Someone uses a tool | A short activity animation for that character (see "Activities"). |
| 6 | A tool call needs the user's approval | The character whose call is waiting holds the phone pose under a "Needs approval" tag, and the CEO's phone rings until the call is approved or refused. The approval sound plays, except in auto mode, where a classifier rather than the user answers most asks. Then the character returns to work. |
| 7 | A subagent finishes | The staff member brings a report to the Chief of Staff, then walks back to the resource bench and waits there, still in their role outfit. A failed subagent shows a distinct "failed" report. |
| 8 | The main task finishes | The desk workers bring their reports to the Chief of Staff (scene 7), then the Chief of Staff phones the report to the CEO. The completion sound plays as the CEO's phone starts to ring, so the call is on screen when it is heard, if the sound rule below allows it. |
| 9 | The user interrupts the task | The Chief of Staff stops working. No report call, no sound. |
| 10 | Session ends | The Chief of Staff is gone from the desk, with no walk-out; a Chief who carried a desk in carries it out along the path. Any remaining staff and operators go back to the resource bench (a newcomer who carried a desk in leaves with it). The session's cards are removed from the Dispatcher's board. A block with no sessions left is removed, and the other blocks close up. |
| 11 | A background task starts | The character that started the task (the Chief of Staff, or a staff member) pages a waiting operator over the bench speaker. The operator walks into the server room and starts work at a console. The name tag shows the background role. If no role is decided yet when the operator leaves the bench, they keep a neutral outfit until it is. |
| 12 | A background task finishes | The operator brings the result to the character that started the task (the Chief of Staff, or a staff member still at work) and walks back to the resource bench. If Claude Code then starts a new turn to handle the result, the Chief of Staff works on it as a follow-up ticket. No call comes from the CEO for it. When that turn ends, the report goes to the issuer of the ticket that started the operator (scene 8). A failed task shows a distinct "failed" result. A task that is stopped (killed) leaves with no result. |
| 13 | A schedule is created or deleted | A card is pinned to the Dispatcher's board, or taken down, and the other cards move left to close the gap. |
| 14 | A schedule fires | The Dispatcher radios the card's ticket to that session's Chief of Staff, the same way the CEO phones in scene 2. When the turn ends, the Chief of Staff phones the report to the Dispatcher, not to the CEO. |
| 15 | A hook sends the main agent back to work | The Inspector at reception stops the report before it reaches the CEO: the Chief of Staff phones the report in, and the Inspector takes the call at the reception phone. After the call, the Inspector shows the hook's reason (when the plugin can read it; otherwise "Returned") and a "Returned" (「退回」) stamp shows over the Chief of Staff, both for a few seconds. The Chief of Staff keeps working on the same ticket, with its note still showing. The ticket ends when a later report gets past the Inspector and is phoned to the issuer as usual. |
| 16 | One agent sends a message to another | The sender walks to the receiver's desk, a speech bubble shows over both for a moment, and the sender walks back. This applies to staff and agent-team teammates messaging each other, to the Chief of Staff messaging a staff member, and to a staff member messaging the Chief of Staff. The bubble shows no message text. When a staff member's message or final report starts a new turn of the main agent, the Chief of Staff's note says who it is from, such as "Report from planner" (「planner 的回報」) or "Message from planner", using the short description the main agent gave the subagent (when it is short), or its role. A message from an agent town-link doesn't know reads "Message from a colleague". A message to a finished subagent resumes it: it is called from the bench again as a new job. |
| 17 | The conversation is compacted (`/compact`, or the automatic compaction) | A stack of notes appears on the Chief of Staff's desk, and the Chief of Staff goes through it, writing, under a "Tidying notes…" (「整理筆記中…」) line. When it ends, most sheets fly off and a few stay, in proportion to what was kept, and the line shows the size before and after, such as "Notes tidied: 152k → 20k tokens". Then the stack goes. A skipped or failed compaction just clears the stack. No sound. A subagent's own compaction shows nothing. |

Scene 15 happens when a Stop hook, such as a check that tests pass or a rule that a to-do list must be finished, refuses to let the main agent end its turn. To the user, the task is still running. The Inspector makes that visible. For a subagent held back by its own Stop hook, the Chief of Staff hands the staff member's report back at the desk instead.

### Walking the CEO

The user can walk the CEO around the office with the arrow keys or the mouse, for fun and to look at blocks that do not fit in the window.

- The CEO walks around furniture and stays on the office floor. Diagonal keys can be held together. The view pans to keep the CEO in sight.
- **Clicking the floor** walks the CEO to that spot, around the furniture. The click is mapped through the tilted camera onto the floor plane. A spot off the office floor is pulled in to its nearest edge; a spot inside furniture (or on its top, which lands on the floor behind it) becomes the nearest free spot beside it.
- **Clicking the CEO's desk** (the desk, the spot behind it and the rug around it) walks the CEO back to the desk, the same as H.
- A tip at the bottom of the window says "Move the CEO with the arrow keys ← ↑ ↓ → or click where to go" (「用方向鍵 ← ↑ ↓ → 或點擊地面移動執行長」). While the CEO is away from the desk, it says "Press H or click the CEO's desk to send the CEO back" (「按 H 或點執行長的桌子，讓執行長回到座位」). Each tip has a close button. Closing either tip turns off "Show tips" in Settings, which hides both tips until it is turned on again.
- **Clicking a character** walks the CEO over to that character, around the furniture, to a free spot beside them (across their desk if that is the only way). The CEO turns to them, and they talk (see below). Clicking the name tags just above a character counts too. Clicking the CEO does nothing.
- **Back to the desk when the work is done.** When the last task anywhere ends (no open ticket, working staff, background task or approval wait in any block), the CEO stops talking to whoever it was with and walks back to the desk, once the report calls are over. New work, a click or the arrow keys call this off. A CEO the user moves afterwards stays where it is put.
- H walks the CEO back to the desk, around the furniture. An arrow key during any of these walks takes control back; a new click changes where the CEO is going. Clicks do nothing while an arrow key is held.
- When the last project block is removed and only the executive office is left, the CEO walks back to the desk by itself. If the CEO was in a block that went away, the view moves to the executive office and the CEO walks in from the nearest edge of it. If a block is removed while other blocks remain, the CEO can walk back onto the floor from where it was.
- Away from the desk, the CEO holds a mobile phone. Calls with the Chiefs of Staff, and the ringing for approvals, go to the mobile, and the CEO can keep walking during a call. While the CEO is on the desk phone, the CEO stays at the desk until the call ends.
- **Talking to a character.** When the CEO stands next to a character (within about a meter, across a desk counts), that character's tags change to a short statement about its work, in its own words. For example, a Chief of Staff says what ticket it is on, for how long, the task type, how many staff and operators are helping, and what it is doing right now. A staff member gives its role, its job and how long it has been at it. An operator says what it is running in the background. A character on the bench says it is waiting, and its last role. Characters waiting for approval say which tool needs it. The Dispatcher talks about the schedules, and the Inspector about returned tickets. Only one character talks: the one the user clicked while the CEO is next to them, else the nearest.

### Context bar

Under each project block, a bar shows each session's context window: how full it is, then the tokens used over the window's size with the percent, then the tokens the last turn added, for example "131k / 200K (66%) · last turn 12.3k" (「上一輪 12.3k」 in Traditional Chinese). The window's size is a whole number (200K, 256K, 1M). The last turn counts only new tokens (new input, cache writes and output), not the conversation re-read from the cache at each step. The bar is green, turns amber past 60% and red past 80%. A block with more than one session has one bar per session, each starting with its desk ("Desk 1"). The figures come from the main conversation only; a subagent's own context is not shown. Before the first response, the bar shows the window's size alone; the last turn shows once a turn has ended.

### Resource bench

The resource bench is a lounge in each project block. Every session in the block shares it. The characters there are not working. They move around and do idle things: chat, drink coffee, read a magazine, stretch, look at their phone, play darts. These idle animations are different from the work activities, so a glance tells waiting apart from working.

**Who is on the bench**

- A new block starts with a mixed bench: a few characters in common outfit colors (engineering, operator orange) and a few in neutral gray. The bench size setting sets how many.
- Characters who finish a job come back to the bench in their role outfit, with a faint name tag. Over time, a project's bench shows the kinds of roles that project uses.
- When the bench has more characters than its size, the ones who have waited longest walk out along the path.

**Calling from the bench (scenes 4 and 11)**

The bench has a speaker on a side table beside the sofa. The caller does not walk to the bench.

1. The Chief of Staff picks up the desk phone and pages the bench: a call line runs from them to the speaker, which shows "Paging: TypeScript Engineer" (「廣播：TypeScript 工程師」). A staff member who pages has no phone and just talks. If role classification has not finished yet, the page waits up to 3 seconds.
2. The page calls one character, picked in this order:
   1. a waiting character who last had the same role;
   2. a waiting character from the same department (same outfit);
   3. a neutral character, who changes into the role outfit;
   4. anyone waiting, who changes outfit.
3. If the bench is empty, a new character walks in from the path and goes straight to work.
4. Subagents or tasks that start within about 1 second of each other are called in one page. The Chief of Staff calls several characters at once.
5. The called characters stand up and walk straight to free desks (staff) or to the server room (operators), each carrying a smaller ticket. The caller hangs up. When the five staff desks are taken, a newcomer walks in from the path with a desk instead (see "Six desks per project block").

An operator can be called back from the bench as staff, and the other way around. They change outfit on the way.

### Model badge

Each Chief of Staff and staff member can show a small badge with the model it is running on, such as Haiku, Sonnet, Opus, or Fable. The CEO has no badge.

- The badge shows the model family name, looked up in `catalog/models.json`. A model ID that matches no entry is shown in short form, for example `foo-2-5` for `claude-foo-2-5-20260101` (rules in [architecture.md](architecture.md)).
- The badge shows the model that actually answered the character's latest request. If the user switches models with `/model`, or a subagent runs on a different model from its parent, the badge follows.
- Until the first request is answered, the badge shows the requested model. For a subagent with no requested model, this is the parent's current model: the Chief of Staff's, or the parent staff member's for a nested subagent.
- The Haiku calls agent-town itself makes for role and task-type classification are not shown.
- An app setting shows or hides all badges. Default: hidden.

### Activities

| Tool | Animation |
|---|---|
| Read, Grep, Glob | Reading papers or browsing a bookshelf |
| Edit, Write, NotebookEdit | Typing |
| Bash | Working at a terminal |
| Background task (operator) | Working at a console in the server room, with a looping animation for the role (see [roles.md](roles.md)) until the task ends |
| WebSearch, WebFetch | Looking at a globe or a window |
| MCP tools | Using the phone |
| Anything else | Typing |

In the app today, the Chief of Staff and staff at a desk type at the computer for every tool (hands tapping, switching hands), and staff at a hot desk with no computer write. Operators work the racks. The per-tool animations above are still to come.

### Hats

When a session's Chief of Staff has no active subagents, they wear a hat with a short text label showing the task type, such as "Debug" or 「除錯」. The task type is chosen by Haiku from the task type list in [roles.md](roles.md) when the prompt is submitted. While staff are working, the Chief of Staff does not wear a hat.

## Timing rules

- Animations always play at full length, even when Claude finishes first. Example: if a handoff takes 3 seconds and Claude finishes the task in 1 second, the handoff still runs for 3 seconds, then the report trip follows.
- Story events (ticket and report calls, approvals, arrivals and departures) are queued per character and play in order.
- Activity events are not queued. A character shows only the latest activity, so fast tool calls do not build a backlog.

## Sounds

| Sound | When it plays | Rule |
|---|---|---|
| Completion | Scene 8 | Plays when a task finishes, however long it took (default). The user can set a threshold in seconds so that only tasks at least that long play it; the default threshold is 0. End-to-end time is measured from prompt submission to the end of the main agent's turn (Claude Code's own duration for the turn), not animation time. For a follow-up ticket from a background task, it is measured from the start of that task. For a returned ticket (scene 15), it covers all of the work until the report is accepted. For a scheduled ticket, it is measured from the time the schedule fired. Never plays for an interrupted task. |
| Approval needed | Scene 6 | A different sound from completion. Its own on/off setting. Not gated by duration. |
| Dispatch | Scene 2 and 14 | A short computer sound as the CEO's (or the Dispatcher's) call with a ticket rings. Its own on/off setting. |

### Sound settings

In Settings, a Sounds section:

- **Volume**: one slider for all three sounds, 0% to 100% (default 100%), showing its value as a percentage. It changes only agent-town's sounds, not the system volume.
- **One row per sound** (dispatch, completion, approval), each with:
  - an on/off switch (default on);
  - the sound: a list of the system's own sounds, with the default first and marked as the default, then **Choose a file…** for a sound file of the user's own; once chosen, that file's name shows in the list;
  - a **Play** button that plays the chosen sound once, at the current volume, even when the sound's switch or the menu's Sound item is off.
- **Completion threshold**: how many seconds a task must take before the completion sound plays, 0 to 3600 (default 0: every task). It sits in the completion row.
- The **Sound** item in the menu mutes or unmutes all three at once, whatever their switches say. The approval sound stays silent in auto mode, whatever its switch says.
- If the chosen sound cannot be played (its file was moved or deleted, or a system sound is missing), the default sound plays instead; if that is missing too, nothing plays.
- The choices are kept across restarts, with the other settings.

Which system sounds each app lists, its defaults, and the file types it accepts:

- **macOS**: the sounds in `/System/Library/Sounds` (Basso, Blow, Bottle, Frog, Funk, Glass, Hero, Morse, Ping, Pop, Purr, Sosumi, Submarine, Tink). Defaults: Glass for completion, Ping for approval, Pop for dispatch. Own files: any file macOS plays (such as AIFF, WAV, MP3, M4A, CAF).
- **Windows**: see [windows/spec.md](windows/spec.md).

## Privacy

The ticket and the report can show text. A setting controls what is shown:

- **Full**: the ticket shows the start of the prompt.
- **Task type only** (for screen sharing and presentations): the ticket shows only the task type label.

The default is to be decided (see [roadmap.md](roadmap.md)).

## Languages

- English and Traditional Chinese (Taiwan) at launch.
- The app follows the macOS language setting (System Settings → General → Language & Region, including a language set for this app alone). It uses the first of the user's preferred languages it has; if none, English. Simplified Chinese is not provided and falls back to English.
- All labels (roles, task types, hats, UI) come from translation tables. Adding a language means adding a column, not changing code.
- Font: 俐方體11號 (Cubic 11, OFL), for both Latin and CJK text.
- Prompt text on tickets is shown as the user typed it.

## Enable and disable

| Level | How |
|---|---|
| Hide the office, or turn sound off | "Show agent-town" and "Sound" in the app's menu bar; each works alone (sound can play with the window hidden) |
| Stop sending events from Claude Code | `/town off` and `/town on` in Claude Code. Saved across sessions. |
| Remove entirely | Disable or uninstall the plugin in `/plugin` |

## Menu bar

The app runs in the menu bar, with no Dock icon. Its menu:

- **agent-town X is available…** and **town-link X is available…** at the top, only while there is an update (see "Updates" below). Each opens the Updates window.
- **About agent-town** opens a window with the version and build number, the author (Samson Chen), the license (Apache 2.0) with a link, the repository link, and the third-party components with links to each one and its license (Kenney Mini Characters and Kenney Furniture Kit, CC0 1.0).
- **Show agent-town** (checked while the office window is open). Closing the window unchecks it; the app keeps running.
- **Stay on top** (off by default). Keeps the office window above other apps' windows (floating level), even when another app is in front.
- **Sound** (checked while sounds play). Works whether the window is shown or hidden.
- **Settings…**
- **Quit agent-town**

These choices, and the settings below, are kept when the app or the Mac restarts.

## Settings (app)

- Language (built): system (the default, following macOS), English, 繁體中文. A different choice applies after a restart; a "Restart now" button shows only when the choice differs from the language the app is running in.
- Office: **Hide idle project blocks** (off by default) with **Hide after** N seconds (1 to 3600, default 5; see "The office"), and **Show tips** (on by default: the closable tips in the window, such as moving the CEO with the arrow keys; closing a tip turns this off, turning it on brings the tips back). Show tips was in the menu bar menu until macOS app 1.0.5.
- Window size; bench size (characters waiting per block)
- Sounds: the volume; for dispatch, completion and approval, an on/off switch, the sound and a Play button; the completion threshold. See "Sound settings" above. (Muting all sounds is the menu's Sound item.)
- Ticket text: full, or task type only
- Model badges: show or hide
- Open at login (built): a login item macOS manages, also listed in System Settings → General → Login Items. Available in the installed `.app` only, not when run with `swift run`.
- Updates (built): **Check for updates automatically** (on by default), **Check now**, and when the last check ran. See "Updates" below.
- Opacity (built): a slider from 10% to 100% (default 100%, opaque) that shows its value as a percentage. It sets the office window's opacity, live while dragging; the Settings and About windows stay opaque. The minimum is 10% so the window never vanishes (Show agent-town hides it), and a stored value outside 10%–100% is brought back into that range.

## Updates

The app tells the user when a newer agent-town or a newer town-link is available. It does not install anything itself: Homebrew, the `.dmg` (or the Windows installer) and Claude Code's plugin commands do the upgrade.

**What is checked.** Once shortly after launch and then once a day, while **Check for updates automatically** (Settings → Updates, on by default) is on; **Check now** checks at any time. Two public GitHub addresses are read, with nothing about the user sent:

- The app: the releases of `samsonchen/agent-town` (`https://api.github.com/repos/samsonchen/agent-town/releases`). Drafts and pre-releases are skipped. The macOS app takes the highest version among tags `v<version>`; the Windows app the highest among tags `windows-v<version>`. Each matches tags, never GitHub's "Latest" flag (the macOS release keeps it; Windows releases are published with `--latest=false`).
- town-link: `plugin/.claude-plugin/plugin.json` on `main` (`https://raw.githubusercontent.com/samsonchen/agent-town/main/plugin/.claude-plugin/plugin.json`), which is what `claude plugin update` installs.

Versions are compared number by number (`1.0.10` is newer than `1.0.9`). A failed check changes nothing and is tried again at the next check.

**town-link's version.** Each session sends its town-link version in `session.open` (`pluginVersion`, since town-link 1.0.3; see [protocol.md](protocol.md)). A session that sends none runs town-link 1.0.2 or older. The town-link notice is shown while at least one open session runs an older town-link than the one on `main`, and goes away once none does. A Claude Code session keeps the town-link it started with, so an updated plugin reaches a session only after that session restarts. Whether the app and town-link work together still depends only on the protocol version (a 426 and a toast, as before); the plugin version only drives this notice.

**Where the user sees it.**

- A dot on the menu bar icon (on Windows, on the tray icon) while either update is available.
- A line at the top of the menu, "agent-town X is available…" or "town-link X is available…", which opens the Updates window.
- No system notifications (macOS or Windows): the icon and the menu are enough, by the user's choice (2026-11-12).

**The Updates window** shows, for each of the two:

- agent-town: the version running and the newest version, the release notes (from the GitHub release), a "View release" link, and the steps for how it was installed:
  - Installed with Homebrew (the cask's folder `Caskroom/agent-town` exists under `/opt/homebrew` or `/usr/local`): `brew update && brew upgrade --cask samsonchen/agent-town/agent-town`, with a Copy button.
  - Otherwise (from the `.dmg`): a Download button for the release's `.dmg`, and "Quit agent-town, open the downloaded file and drag agent-town to Applications, replacing the old copy."
  - Windows: a Download button for the installer; running it replaces the installed app.
- town-link: the newest version and the open sessions that run an older one (project name and version, or "1.0.2 or older"), then the commands, each with a Copy button:
  ```
  claude plugin marketplace update agent-town
  claude plugin update town-link@agent-town
  ```
  and "Then restart those Claude Code sessions: a session keeps the town-link it started with."
- When the last check ran, and Check now.

When nothing is newer, the window says each is up to date.

## Where it works

- Claude Code CLI in a terminal, and the Code tab of the Claude Desktop app. Both load mods (Claude Code v2.1.287 or later in the terminal).
- Also the VS Code extension and the JetBrains terminal, which run Claude Code on the user's Mac.
- Not supported: Desktop app WSL sessions (plugins are not loaded there), SSH sessions (they run on another machine), cloud sessions and Claude Code on the web (they cannot reach the app on the user's Mac), and Cowork (it takes plugins from the claude.ai account and runs commands in a Linux VM; plugin modules are not documented to run there).
- `claude -p` runs also load mods. Whether they appear in the building is a setting to decide (see [roadmap.md](roadmap.md)).

## Out of scope for the first version

- Windows and Linux apps. The protocol is designed so they can be added later. A Windows app is now planned on its own: see [windows/](windows/README.md).
- Approving or refusing a tool call from inside the app. The app only shows that approval is needed.
