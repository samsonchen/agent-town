# Expected building state for each fixture

Each file here belongs to the fixture with the same name in `protocol/fixtures/`. It lists the building state after every event that changes it, so any app that reads the protocol (the macOS app now, a Windows app later) can replay the fixture and compare.

The macOS app checks these in `app/macos/Tests/TownCoreTests/ExpectedStateTests.swift`. After a deliberate change to how events are applied, write them again and review the diff:

```bash
cd app/macos
UPDATE_EXPECTED=1 swift test --filter fixturesMatchTheirExpectedState
```

## Format

A JSON array. Each entry is:

| Field | Meaning |
|---|---|
| `after` | The index (from 0) of the event in the fixture's `events` array |
| `type` | That event's type |
| `state` | The whole building state after applying it |

Apply events in file order, with each event's `ts` as its arrival time. An event that changes nothing in the state below has no entry.

`state` has:

- `blocks`: project blocks in the order they appeared. Each has `projectId`, `name`, and `sessions` in arrival order.
- Each session: `sessionId`, `compacting`, and when known `model`, `activity` (the Chief of Staff's current activity kind) and `hat` (the open ticket's task type, shown only while no staff member is working). Then:
  - `ticket`, the open ticket, if any: `ticketId`, `origin`, `issuer` (`ceo` or `dispatcher`), `text`, `returnedCount`, and when known `taskType`, `title`, `returnReason`, `messageKind`, `fromAgentId`.
  - `staff`, sorted by `agentId`: `agentId`, `subagentType`, `background`, `done`, and when known `parentAgentId`, `role`, `model`, `activity`.
  - `operators`, sorted by `taskId`: `taskId`, `kind`, and when known `agentId`, `role`, `startedTicketId`.
  - `approvals`, sorted by `approvalId`: `approvalId`, `tool`, and when known `agentId`.
  - `context`, when any field is known: `tokens`, `window`, `percent`, `effort`, `lastTurnTokens`.
- `schedules`, sorted by `scheduleId`: `scheduleId`, `sessionId`, `projectId`, `text`, `recurring`, and when known `nextRunTs`.

A field that is unknown is left out, not `null`. Keys are sorted, so files diff cleanly. The state holds only what every app must agree on: no positions, animations, sounds or timers.
