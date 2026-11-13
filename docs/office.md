# The office

What you see and hear in agent-town, and the settings. For every scene in detail, see [spec.md](spec.md).

The window shows one office building, seen from above. At the top is the executive office; under it, one office block for each project you have open in Claude Code.

## The executive office

A strip across the top, with three people at their desks:

- **The CEO** is you. Each prompt you type becomes a ticket, and the CEO phones it through to the Chief of Staff of that session. Reports come back to the CEO by phone. When Claude Code waits for your approval, the CEO's phone rings until you answer. You can walk the CEO around with the arrow keys or by clicking a spot on the floor (H, or a click on the CEO's desk, goes back to the desk); click a character and the CEO walks over, and that character says how its work is going.
- **The Dispatcher** handles scheduled work, such as `/loop` and other scheduled prompts. Each active schedule is a card on the board beside the Dispatcher's desk, in the color of its project's block. When a schedule fires, the Dispatcher radios the ticket to the Chief of Staff, and the report comes back to the Dispatcher.
- **The Inspector** stands at reception. When a hook (such as a check that the tests pass) refuses to let Claude Code finish and sends it back to work, the Chief of Staff's report goes to the Inspector instead of the CEO. The Inspector shows the hook's reason, a "Returned" stamp shows over the Chief of Staff, and the work goes on.

## The project blocks

- **One block per project.** A block appears when a Claude Code session opens in that project, before any prompt, and leaves when its last session ends. Blocks stack under the executive office, and the window grows to fit them. To keep the window small, turn on Settings → Hide idle project blocks: a block then shows only while its project has work, and hides a few seconds (5 by default, adjustable) after the work is done. A hidden block's context bars stay on screen, named by project, under the executive office, so you can still see which sessions are open.
- **On a laptop screen.** Turn on Settings → Compact view (it applies after a restart) to draw the office at half size, with smaller text. You can also make the window as small as 320 × 240: when the office doesn't fit, the view scrolls by itself to where characters are walking. Your own scrolling, or walking the CEO, pauses that for 10 seconds.
- **The sign** shows the project's name and a short title for the running task. A bar under the block shows the session's context use.
- **Desks**: one Chief of Staff desk with a telephone, and five staff desks. A second session in the same project brings a second Chief of Staff.
- **The resource bench** is where staff wait between jobs. The Chief of Staff pages them over the bench speaker.
- **The server room** has racks where operators run background tasks.

## The people in a block

- **The Chief of Staff** is one Claude Code session. They take the ticket, put on a hat for the kind of task, and dispatch the work. When the work is done, they phone the report back to whoever issued the ticket.
- **Staff** do the work. For the main agent's own work, the Chief of Staff calls a staff member whose role fits the files being changed (a TypeScript engineer for `.ts` files, and so on); each subagent is a staff member too. They come from the bench, work at a desk, and report back when done.
- **Operators**, in safety orange, run background tasks in the server room, and bring the result back to the Chief of Staff.
- **Compaction**: when Claude Code compacts the conversation, the Chief of Staff tidies a stack of notes on the desk.

## Sound and settings

- You hear a sound when a ticket arrives, when work is done, and when Claude Code needs your approval, even with the window hidden.
- The menu bar menu has About, Show agent-town, Stay on top, Sound, Settings… and Quit. Stay on top keeps the office window above other apps' windows, even when another app is in front. The About, Updates and Settings windows float one level above it, so they are never hidden behind it. Your choices are kept across restarts, and the window opens where you left it.
- Settings has the language (English or Traditional Chinese, following macOS or Windows by default), Open at login, Opacity (10% to 100%) for the office window, Compact view, Hide the window when no Claude Code session is open (the office goes away when you have no session and comes back with the next one), Hide idle project blocks (with how many seconds to wait), Show tips, the sounds, and update checks.
- Settings → Sounds has a volume for agent-town's sounds, and for each sound (dispatch, completion, approval) an on/off switch, the sound (a system sound of macOS or Windows, or a file of your own) and a Play button. Under completion, set a minimum task length in seconds so that only longer tasks play it.
