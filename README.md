# Agent-Town for Claude Code

Watch your Claude Code agents at work: a Claude Code plugin and a macOS menu bar app (now on Windows too) that show your sessions, subagents, background tasks and approvals as a small 3D office. (Not related to other projects named agent-town.)

[繁體中文說明](README.zh-TW.md)

agent-town shows Claude Code's work as a small office on macOS and Windows, seen from above, with 3D characters. The top-down view was inspired by Gather Town. You are the CEO. Each Claude Code session is a Chief of Staff with a staff of its own, and you can watch them take your tickets, call staff, run background jobs, wait for your approval and phone the report back.

## 1. What agent-town is

### Why it exists

Some tasks in Claude Code take a long time. You type a prompt, Claude Code starts reading files, running commands and calling subagents, and then you wait. I wanted to know two things:

- What is Claude Code doing right now?
- Is it done yet?

The first idea was small: play a sound when a long task finishes. That covers "is it done yet".

While working on the sound, I noticed that Claude Code already says a lot about what it is doing: which tool it is calling, which subagent it started, which background task is running, when it is waiting for approval, when it compacts its notes. A sound uses only the last of these. If every one of those events can be heard, it can also be seen, so the sound grew into an office.

### What it is made of

- **town-link**: a Claude Code plugin that watches what Claude Code does and sends short event messages to the app on your own computer, over a local connection. It never changes what Claude Code does.
- **The agent-town app**: on macOS, a menu bar app that draws the office with RealityKit and plays the sounds; on Windows, a tray app built with Godot that draws the same office.

Nothing leaves your Mac except a few short requests per task: town-link asks Haiku, on your own Claude plan or API key, for a task title, the kind of task, and staff roles. Prompts are shown on tickets as you typed them.

### What it is not

- It is not a dashboard for measuring productivity. It shows what is happening, not how well.
- It does not control Claude Code. You still work in the terminal or the Claude desktop app; agent-town only watches.
- It is not finished. See [Known issues and limitations](#4-known-issues-and-limitations) and the [roadmap](docs/roadmap.md). If something in the office looks wrong, or you would like a scene that is not there yet, please open an issue on GitHub.

![agent-town at work: the executive office with the CEO, the Inspector and the Dispatcher, and a project block with two Chiefs of Staff, the staff desks, the server room and the resource bench](docs/images/agent-town.gif)

## 2. Installing

You need both parts: the plugin in Claude Code, and the app on your Mac or Windows PC.

### The town-link plugin

town-link is built as a Claude Code mod (a plugin with a hooks module), so it needs a Claude Code version that runs mods: v2.1.287 or later. In a Claude Code session:

```
/plugin marketplace add samsonchen/agent-town-claude-code
```

```
/plugin install town-link@agent-town-claude-code
```

Or from a terminal:

```bash
claude plugin marketplace add samsonchen/agent-town-claude-code
```

```bash
claude plugin install town-link@agent-town-claude-code
```

Then restart Claude Code. In a session, `/town` shows the installed town-link version and whether the plugin is connected to the app, and `/town on` or `/town off` turns sending on or off for all sessions.

Updates are not automatic for this marketplace. To update:

```bash
claude plugin marketplace update agent-town-claude-code
```

```bash
claude plugin update town-link@agent-town-claude-code
```

**In the Claude Desktop app:** the Code tab, the terminal and the VS Code extension on one Mac share plugins installed for your user, so installing once in any of them is enough. To install from the Code tab itself, click **+** next to the prompt box, then **Add plugins**, add the marketplace `samsonchen/agent-town-claude-code`, and install town-link. This only makes sense for Code tab sessions that run on your Mac (see [Claude Desktop and Cowork](#5-claude-desktop-and-cowork)).

Like every plugin with a hooks module, town-link runs with your user's permissions. To see every event it handles and every call it makes before you install it, run `claude plugin validate plugin` in a clone of this repo.

### The app on macOS

Requires macOS 15 or later. With [Homebrew](https://brew.sh):

```bash
brew tap samsonchen/agent-town-claude-code https://github.com/samsonchen/agent-town-claude-code
```

```bash
brew install --cask samsonchen/agent-town-claude-code/agent-town
```

Or download `AgentTown-<version>.dmg` from [Releases](https://github.com/samsonchen/agent-town-claude-code/releases), open it, and drag AgentTown into Applications.

The app is signed with a Developer ID and notarized by Apple, so it opens like any other app.

The app appears in the menu bar as a small building, with no Dock icon. Open it before you start work: town-link sends events only while the app is running. To have it start with your Mac, turn on Settings → Open at login.

To update: `brew upgrade --cask agent-town`, or download the new `.dmg`.

The plugin and the app have their own version numbers and are updated separately. `/town` shows the plugin's version, and About shows the app's. The numbers don't need to match: what matters is the protocol between them, which both versions check. If they ever can't work together, `/town` says so.

The app checks GitHub once a day for a newer app and a newer town-link (Settings → Updates; it sends nothing about you). When one is out, a dot appears on the menu bar icon, the menu says which, and the Updates window shows the commands for how you installed it. A Claude Code session keeps the town-link it started with, so restart your sessions after updating the plugin.

### The app on Windows

Requires Windows 11 (x64). Windows 10 is allowed by the installer, but the app has not been tested on it. Download `agent-town-setup-<version>.exe` from the newest **agent-town for Windows** release on [Releases](https://github.com/samsonchen/agent-town-claude-code/releases) (tags `windows-v<version>`) and run it. It installs for your user only, with no administrator prompt, and adds agent-town to the Start menu.

The installer is not code-signed yet, so Windows shows "Windows protected your PC" the first time: click **More info**, then **Run anyway**.

The app lives in the tray (the notification area), with no taskbar button; closing the office window hides it. Windows 11 first puts a new tray icon among the hidden icons (the **^** arrow); drag it out to keep it in view. To have it start when you sign in, turn on Settings → Open at login.

To update, run the newer installer: it replaces the installed app and keeps your settings. Settings → Updates checks for a newer Windows release once a day, as on the Mac. To remove it: Settings → Apps → Installed apps → agent-town → Uninstall.

Claude Code must run natively on Windows (the terminal, the Desktop app's Code tab, or VS Code). Sessions inside WSL can't reach the app.

## 3. The office

The window shows one office building, seen from above. At the top is the executive office; under it, one office block for each project you have open in Claude Code.

### The executive office

A strip across the top, with three people at their desks:

- **The CEO** is you. Each prompt you type becomes a ticket, and the CEO phones it through to the Chief of Staff of that session. Reports come back to the CEO by phone. When Claude Code waits for your approval, the CEO's phone rings until you answer. You can walk the CEO around with the arrow keys or by clicking a spot on the floor (H, or a click on the CEO's desk, goes back to the desk); click a character and the CEO walks over, and that character says how its work is going.
- **The Dispatcher** handles scheduled work, such as `/loop` and other scheduled prompts. Each active schedule is a card on the board beside the Dispatcher's desk, in the color of its project's block. When a schedule fires, the Dispatcher radios the ticket to the Chief of Staff, and the report comes back to the Dispatcher.
- **The Inspector** stands at reception. When a hook (such as a check that the tests pass) refuses to let Claude Code finish and sends it back to work, the Chief of Staff's report goes to the Inspector instead of the CEO. The Inspector shows the hook's reason, a "Returned" stamp shows over the Chief of Staff, and the work goes on.

### The project blocks

- **One block per project.** A block appears when a Claude Code session opens in that project, before any prompt, and leaves when its last session ends. Blocks stack under the executive office, and the window grows to fit them. To keep the window small, turn on Settings → Hide idle project blocks: a block then shows only while its project has work, and hides a few seconds (5 by default, adjustable) after the work is done. A hidden block's context bars stay on screen, named by project, under the executive office, so you can still see which sessions are open.
- **On a laptop screen.** Turn on Settings → Compact view (it applies after a restart) to draw the office at half size, with smaller text. You can also make the window as small as 320 × 240: when the office doesn't fit, the view scrolls by itself to where characters are walking. Your own scrolling, or walking the CEO, pauses that for 10 seconds.
- **The sign** shows the project's name and a short title for the running task. A bar under the block shows the session's context use.
- **Desks**: one Chief of Staff desk with a telephone, and five staff desks. A second session in the same project brings a second Chief of Staff.
- **The resource bench** is where staff wait between jobs. The Chief of Staff pages them over the bench speaker.
- **The server room** has racks where operators run background tasks.

### The people in a block

- **The Chief of Staff** is one Claude Code session. They take the ticket, put on a hat for the kind of task, and dispatch the work. When the work is done, they phone the report back to whoever issued the ticket.
- **Staff** do the work. For the main agent's own work, the Chief of Staff calls a staff member whose role fits the files being changed (a TypeScript engineer for `.ts` files, and so on); each subagent is a staff member too. They come from the bench, work at a desk, and report back when done.
- **Operators**, in safety orange, run background tasks in the server room, and bring the result back to the Chief of Staff.
- **Compaction**: when Claude Code compacts the conversation, the Chief of Staff tidies a stack of notes on the desk.

### Sound and settings

- You hear a sound when a ticket arrives, when work is done, and when Claude Code needs your approval, even with the window hidden.
- The menu bar menu has About, Show agent-town, Stay on top, Sound, Settings… and Quit. Stay on top keeps the office window above other apps' windows, even when another app is in front. Your choices are kept across restarts, and the window opens where you left it.
- Settings has the language (English or Traditional Chinese, following macOS or Windows by default), Open at login, Opacity (10% to 100%) for the office window, Compact view, Hide idle project blocks (with how many seconds to wait), Show tips, the sounds, and update checks.
- Settings → Sounds has a volume for agent-town's sounds, and for each sound (dispatch, completion, approval) an on/off switch, the sound (a system sound of macOS or Windows, or a file of your own) and a Play button. Under completion, set a minimum task length in seconds so that only longer tasks play it.

## 4. Known issues and limitations

- **Where your organization manages Claude Code, some scenes may not show.** On a Team or Enterprise login, Claude Code passes some events over the plugins you install yourself, and town-link is one of them. You can see this in `/plugin` → Errors. On a personal account these scenes work.
  - Automatic compaction: when Claude Code compacts the conversation on its own because the context is full, the office shows nothing. Typing `/compact` yourself always shows the scene.
  - Returned work: the Inspector's scene may not appear when a hook sends Claude Code back to work. The work itself goes on as usual.
  - The approval sound in auto mode: agent-town normally stays quiet when auto mode's classifier answers an ask. Under an organization it knows your permission mode only from your settings when a session starts, so if you switch to auto mode with Shift+Tab, a slow ask may still play the approval sound.
- **Work done while the app is closed is not shown later.** town-link sends events only while the app is running and drops them otherwise. A Claude Code session that is already running shows up within a few seconds of the app starting, from that point on.
- **Commands you run with `!` don't show in the office.** Claude Code runs them in your shell without the model, and tells plugins nothing about them. If Claude goes on working after one, that work shows as usual, with the Chief of Staff's note reading "Continuing".
- **A session that stops responding leaves the office about two minutes later.** When a Claude Code session ends normally, its Chief of Staff leaves right away. When it stops responding (for example, the terminal was killed), its Chief of Staff stays until the app has heard nothing for two minutes.
- **Labels can cover someone near the top of a small window.** Name tags and notes slide down to stay inside the window, so in a short window they may sit over the character's head. Make the window taller or scroll. A character scrolled out of view above the window has no tag shown.
- **Tags can overlap in compact view.** The text is 75% of its normal size on an office at half size, so tags of characters side by side (two Chiefs of Staff, for example) can overlap, mostly in a narrow window.
- **Task titles and staff roles use your Claude plan.** Each new task makes a few short Haiku requests on your own plan or API key to pick a title, the kind of task and staff roles. If a request fails, the sign shows no task title and the hat and roles fall back to defaults.
- **One project block shows up to five sessions.** The back row has five desk spots, shared by the Chiefs of Staff and by staff who carry in a desk when the front desks are full. A Chief of Staff who arrives when all five are taken stands on the first desk's spot, over the Chief already there.
- **macOS 15 or Windows 11.** The macOS app needs macOS 15 or later; the Windows app needs Windows 11 (x64; Windows 10 is allowed but untested) and native Windows Claude Code sessions (not WSL).

## 5. Claude Desktop and Cowork

agent-town works wherever a Claude Code session runs on the same Mac as the app, because town-link sends its events to the app over a local connection.

| Where you use Claude | Works? | Why |
|---|---|---|
| Claude Code in a terminal | Yes | |
| Claude Desktop, Code tab, local session | Yes | Plugin modules run there (Claude Code v2.1.286 or later), and the session runs on your Mac. |
| VS Code extension, JetBrains terminal | Yes | They run Claude Code on your Mac. |
| Claude Desktop, Code tab, cloud session | No | The session runs on Anthropic's servers, which can't reach the app on your Mac, and plugins installed on your Mac aren't loaded there. |
| Claude Desktop, Code tab, SSH or WSL session | No | The session runs on another machine (SSH), or doesn't load plugins (WSL). |
| Claude Code on the web (claude.ai/code) | No | Cloud sessions, as above. |
| Cowork | Not supported | Cowork takes its plugins from your claude.ai account, not from Claude Code, and runs its commands in a separate Linux virtual machine. Its docs don't say that plugin modules like town-link run there, and I have not tested it. |
| Chats in the Claude app | No | Chats are not Claude Code sessions. |

These come from Claude Code's documentation as of November 2026. agent-town itself has been tested in the terminal only.

## Documentation

Start with [docs/README.md](docs/README.md). It links to:

- [Spec](docs/spec.md): what you see and hear
- [Architecture](docs/architecture.md): how the plugin and the app are built
- [Protocol](docs/protocol.md): the messages between the plugin and the app
- [Roles](docs/roles.md): job titles, departments and task types
- [Distribution](docs/distribution.md): how it is installed
- [Releasing](docs/releasing.md): how to build, sign and publish the macOS app
- [Roadmap](docs/roadmap.md): build phases and open questions
- [Verification](docs/verification.md): what the Claude Code mod API provides

## For developers

Run the app from source (macOS 15 or later, Xcode installed):

```bash
cd app/macos
swift run AgentTown                       # listens for town-link
swift run AgentTown --demo ../../protocol/fixtures/01-basic-ticket.json   # replays a recorded stream
```

Try the plugin without installing it, with the stand-in receiver that prints each event:

```bash
python3 tools/debug-receiver.py          # keep it running
claude --plugin-dir plugin               # in another terminal
```

To try a change before releasing it, build and run the app from your checkout. Nothing is signed, installed or published, and the run keeps its own settings:

```bash
app/macos/scripts/run-local.sh                 # a demo with two projects, no sounds
app/macos/scripts/run-local.sh --live          # real Claude Code sessions (quits the installed app, reopens it after)
app/macos/scripts/run-local.sh --fake-update --updates   # the update notices, with a made-up new version
```

`--help` lists the other options (another fixture, `--check-now`, `--settings`, `--sound`, `--zh`).

Build the app as a `.app` and `.dmg` (`app/macos/build/release/`), and publish a release: see [releasing.md](docs/releasing.md).

```bash
app/macos/scripts/release.sh --unsigned   # a local test build, not signed
app/macos/scripts/release.sh --publish    # signed and notarized: publish the release and push the Homebrew cask
```

Checks: `claude plugin validate plugin` and `claude plugin test plugin` for the plugin; `swift build` and `swift test` in `app/macos` for the app.

## License

Apache 2.0. See [LICENSE](LICENSE). The 3D models are Kenney assets under CC0. See [assets/LICENSES.md](assets/LICENSES.md).
