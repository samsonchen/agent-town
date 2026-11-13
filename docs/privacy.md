# What town-link reads and sends

town-link only watches. Every hook passes Claude Code's event on unchanged and never decides anything for it: it doesn't allow, deny or rewrite a tool call, a prompt or a permission ask. Its errors are caught inside the plugin, so a failure in town-link can't stop your session.

## What it sends, and where

**To the agent-town app, on your own computer.** town-link sends short event messages (a session opened, a prompt became a ticket, a tool started, a subagent finished, the context is 40% full, and so on) to the app over a loopback connection (`127.0.0.1`). It finds the app through the endpoint file the app writes, which holds the port and a random token; only a request with that token is accepted. Nothing goes over the network. The messages and the endpoint file are described in [protocol.md](protocol.md).

What the events carry:

- The project's name (the repository's or the folder's name, never the full path) and a hash of the project's identity, so sessions in one project share a block.
- The start of each prompt, shown on the ticket as you typed it.
- Tool names and short descriptions of what a tool, a subagent or a background task is doing (for example a file's name, or a subagent's description).
- The model, the effort and how full the context window is.
- town-link's own version, for the app's update notice.

**To Haiku, on your own Claude plan or API key.** For each new task, town-link makes a few short requests to Claude's Haiku model through Claude Code (`$.model.complete` and `$.model.classify`), never to any other service:

- a short title for the task: the first 600 characters of the prompt;
- the kind of task (the Chief of Staff's hat): the same text;
- a staff role for each subagent: its type, name, description and the first 400 characters of its prompt;
- a role for each background task: its description.

The answers are only labels for the office. If a request fails, the office falls back to defaults.

**Nothing else.** town-link makes no other network requests. While the app isn't running, town-link drops the events instead of keeping them.

## What its hooks do

| Hook | What town-link does with it |
|---|---|
| `session.start`, `session.end` | Opens and closes the session's Chief of Staff; registers `/town` |
| `prompt.submit`, `turn.start`, `turn.complete`, `turn.step` | Turns prompts into tickets; notes the effort and each turn's token use |
| `tool.call` | Shows the tool's activity, and notices background tasks and schedules |
| `tool.check` | Reads Claude Code's verdict on a permission check to know when you are being asked, and returns that verdict unchanged |
| `agent.spawn` | Pages a staff member for each subagent |
| `session.send`, `session.receive` | Notices messages between agents and finished background tasks |
| `session.compact`, `command.run` (`/compact`) | Shows the compaction scene |
| `session.measure` | Reads how full the context window is |
| `classic.PreToolUse`, `classic.Stop` | Reads the permission mode, and a hook's reason when it sends Claude Code back to work |
| `command.run` (`/town`) | Shows town-link's status, or turns sending on or off |

To see every event town-link handles and every call it makes, run `claude plugin validate plugin` in a clone of this repository.

## The app

The app receives the events and draws them. It sends nothing anywhere, except its update check: once a day (Settings → Updates, on by default), it reads the list of releases and town-link's version from GitHub's public addresses, with nothing about you in the request.
