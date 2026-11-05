# Phase 0 verification

These answers come from the mod API types that Claude Code 2.1.318 writes (`claude-code.d.ts`) and from the mod authoring reference. Items marked **Runtime** still need a check with the recorder mod (`dev/recorder/`) in a real session.

| # | Question (short) | Answer | What the mod does |
|---|---|---|---|
| 1 | `$.http.fetch` to `127.0.0.1` | Yes in the types. Fetch reaches "whatever the host reaches, unless the organization's web-fetch policy refuses it". `HttpInit.socketPath` can also send over a Unix socket. **Runtime:** check against managed policy and sandbox. | POST to the loopback port. A Unix socket is the fallback. |
| 2 | `turn.complete` fields | Yes: `durationMs` (wall clock), `isAborted`, `agentId?`, `turnId`, `reason` (`answer`, `aborted`, `refusal`, `error`), `usage?.model`. `refusal` is a model refusal, not a Stop hook. | As planned. |
| 3 | `agent.spawn` returns `agentId` in time | Yes. `await next(e)` resolves once the subagent has started, with `{ model, agentId?, teammateId? }`. The input has `name`, `subagentType`, `background`, `parentAgentId`, `model`, `parentModel`, `workflow?`. | Send `staff.hire` after `await next(e)`, with the resolved `model`. |
| 4 | `agentId` on subagent `tool.call` | Yes, absent on the main loop. Workflow agents and engine forks (compaction, memory) carry IDs never seen in `agent.spawn`. | Ignore `agentId`s not seen in `agent.spawn`. |
| 5 | Knowing an `ask` was answered | Partly. An `ask` is settled by the dialog, the auto-mode classifier, or a headless host. `ToolCheckInput.approver` is `host` or `person`. The `tool.call` result tells allowed (a result) from refused (`deny` or `isError`). | Send `approval.wait` only for an `ask` with `approver === 'person'`. Send `approval.end` when that `tool.call`'s `next` settles. |
| 6 | `$.model.classify` | 2 or more labels, no stated upper limit. `options.model` takes an alias. Returns the label or `undefined`, and rejects on failure. Billed to the user's credentials. **Runtime:** delay with about 130 labels. | Pass `{ model: 'haiku' }`. Catch and fall back. |
| 7 | `$.session.repo()` | `{ root, remote, internal, name } \| null`. `name` is null for ordinary repositories. | Identity from `remote`, else `root`. Display name parsed from `remote`, else the basename of `root`. |
| 8 | Desktop Code tab | Partly. Plugin folders apply to sessions the desktop app starts. `$.process` is CLI only. **Runtime:** check with a marketplace install. | Do not use `$.process`. |
| 9 | Background subagent after the main turn ends | Its own `turn.start`, `tool.call`, `turn.complete` (with `agentId`) keep arriving. Its finish wakes main through `prompt.submit` with `origin.kind: 'task-notification'`. | Staff stay on the floor until their `turn.complete`. |
| 10 | `claude plugin marketplace add` from the shell | Yes for a folder. **Runtime:** a GitHub `owner/repo` source. | As planned. |
| 11 | `turn.step` | A generator hook: `const r = yield* next(e); return r`. `r.usage?.model` is the model that answered. 10 s budget. `turn.complete.usage?.model` gives the last answering model of a turn. | Use `turn.complete.usage?.model` for badges. It is simpler, and no generator hook is needed. |
| 12 | Classify calls in `turn.step` | No. Classify is its own operation (`model.classify`). `turn.step` is only a turn's model request. **Runtime:** confirm. | No filtering needed. Still ignore unknown `agentId`s. |
| 13 | Turns without a typed prompt | `prompt.submit` fires for them, with `origin.kind`: `composer` (typed), `task-notification`, `scheduled-trigger`, `peer`, `auto-continuation`, `unclassified`, and others. `turnId` is set when it is delivered into a running turn. | Ticket origin from `origin.kind`. Open a new ticket only when `turnId` is absent. |
| 14 | Background task end event | No dedicated event. The end arrives as the `task-notification` prompt (text format not typed). `classic.Stop` and `classic.SubagentStop` carry `background_tasks` and `session_crons` on every stop. **Runtime:** record the notification text. | Parse the notification. Diff `background_tasks` at each Stop as a backup. |
| 15 | Stop-hook block | Yes: hook `classic.Stop`. `(await next(e)).block` is set when a hook blocked the end. Blind spot: a block from a managed hook, or from a module ordered before ours, is not seen. **Runtime:** order of `turn.complete` and Stop, and whether `turn.complete` fires per attempt. | Send `ticket.return` when `block` is set. |
| 16 | Workflow agents | Yes: `agent.spawn` has `workflow: { runId, agentIndex }`, and `tool_use_id` is the Workflow call. The Workflow result has `taskId`, `runId`, `workflowName`. | Link workflow staff to the coordinator by `runId`. |
| 17 | Schedule tools | `CronCreate { cron, prompt, recurring?, durable? }` → `{ id, humanSchedule, recurring, nextFireAt? }`. `CronDelete { id }`. `ScheduleWakeup { delaySeconds?, prompt?, stop?, … }` → `{ scheduledFor, stopped?, … }`, with no ID. | `scheduleId` = Cron `id`, or the `ScheduleWakeup` `tool_use_id`. |
| 18 | Agent messages | Yes, through `session.send` (`{ to, text, origin, agentId }`, the sender) and `session.receive` (with the receiver's `agentId`). The `SendMessage` result is untyped. | Use `session.send` and `session.receive`, not `tool.call`. |
| 19 | RealityKit | Not covered by these types. **Runtime:** Swift prototype — load the converted USDZ, cut clips by time, swap the texture per instance, use `OrthographicCameraComponent` in a macOS `RealityView`. | Phase 2 spike. |

## Other facts

- Background task IDs: `Bash` → `result.backgroundTaskId`; `Monitor` → `result.taskId`; `Workflow` → `result.taskId` and `runId`. A background `Agent` is staff, keyed by its `agentId`.
- `$.fs.read` takes any absolute path, up to 4 MiB. `~` is not expanded: build paths from `await $.env.get('HOME')`. `$.fs.write` replaces a file; there is no append.
- `$.store` is one JSON file per plugin, shared by all sessions on the machine.
