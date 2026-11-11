extends TestSupport
## The building state. The fixture test is the one both apps share; the others are ports of
## app/macos/Tests/TownCoreTests/BuildingTests.swift.

const FIXTURES: Array[String] = ["01-basic-ticket", "02-staff-and-approval", "03-background-task-followup",
	"04-schedule-and-inspector", "05-two-projects-messages"]


## protocol/fixtures/expected/: the state after each event that changes it, as the macOS app has it.
func test_fixtures_match_their_expected_state() -> void:
	var dir := DirAccess.open(TestSupport.repo_root().path_join("protocol/fixtures"))
	var names := Array(dir.get_files()).filter(func(f: String) -> bool: return f.ends_with(".json"))
	names.sort()
	check(names.size() >= FIXTURES.size(), "found %d fixtures" % names.size())
	for n: String in names:
		var events := TestSupport.fixture(n.get_basename())
		check(not events.is_empty(), "%s has events" % n)
		var want: Variant = JSON.parse_string(FileAccess.get_file_as_string(
			TestSupport.repo_root().path_join("protocol/fixtures/expected/" + n)))
		check_eq(_expected_states(events), want, n)


## Replays events the way Snapshot.swift's expectedStates does: an entry after each event that
## changes the snapshot.
func _expected_states(events: Array[TownEvent]) -> Array:
	var b := Building.new()
	var out: Array = []
	var last: Variant = null
	for i in events.size():
		b.apply(events[i])
		var state := b.snapshot()
		if last != null and TestSupport.first_difference(state, last, "") == "":
			continue
		last = state
		out.append({"after": i, "type": events[i].type, "state": state})
	return out


func _replay(name: String, threshold: float = 0.0) -> Array:
	var b := Building.new()
	b.sound.threshold_seconds = threshold
	var all: Array[Dictionary] = []
	for e: TownEvent in TestSupport.fixture(name):
		if e.type != "session.close":
			all.append_array(b.apply(e))
	return [b, all]


static func _kinds(changes: Array[Dictionary], kind: String) -> Array[Dictionary]:
	return changes.filter(func(c: Dictionary) -> bool: return c["kind"] == kind)


func test_basic_ticket() -> void:
	var r := _replay("01-basic-ticket", 5.0)
	var changes: Array[Dictionary] = r[1]
	var done := _kinds(changes, "ticketDone")
	check(done.size() == 1, "one ticketDone")
	if done.size() == 1:
		check(done[0]["issuer"] == Building.CEO, "reported to the CEO")
	check(not _kinds(changes, "hat").is_empty(), "a hat")


func test_task_follow_up_reports_to_the_parent_issuer() -> void:
	var changes: Array[Dictionary] = _replay("03-background-task-followup")[1]
	var done := _kinds(changes, "ticketDone")
	check(not done.is_empty(), "tickets finish")
	for d: Dictionary in done:
		check(d["issuer"] == Building.CEO, "%s reports to the CEO" % d["ticketId"])


func test_scheduled_ticket_reports_to_the_dispatcher() -> void:
	var changes: Array[Dictionary] = _replay("04-schedule-and-inspector")[1]
	check(_kinds(changes, "ticketDone").any(func(d: Dictionary) -> bool: return d["issuer"] == Building.DISPATCHER),
		"a scheduled ticket reports to the Dispatcher")
	check(not _kinds(changes, "ticketReturned").is_empty(), "a return")


func test_completion_sound_rule() -> void:
	var s := Building.SoundSettings.new()
	check(s.threshold_seconds == 0.0, "default threshold 0")
	check(s.plays_completion(0, false), "plays for 0 ms")
	check(s.plays_completion(1200, false), "plays for 1.2 s")
	check(not s.plays_completion(60000, true), "not when aborted")
	s.threshold_seconds = 5
	check(not s.plays_completion(4999, false), "not under the threshold")
	check(s.plays_completion(5000, false), "at the threshold")
	s.threshold_seconds = -3
	check(s.threshold_seconds == 0.0, "negative threshold becomes 0")
	s.completion_on = false
	check(not s.plays_completion(60000, false), "not when off")


func test_return_after_done_reopens_the_ticket() -> void:
	var b := Building.new()
	b.apply(TestSupport.ev("ticket.submit", 1, {"ticketId": "t1", "text": "x", "origin": "user"}))
	b.apply(TestSupport.ev("ticket.done", 2, {"ticketId": "t1", "durationMs": 10, "aborted": false}))
	var c := b.apply(TestSupport.ev("ticket.return", 3, {"ticketId": "t1"}))
	check_eq(c, [{"kind": "ticketReturned", "projectId": "p", "sessionId": "s", "ticketId": "t1"}], "changes")
	check(_chief(b).ticket != null and _chief(b).ticket.returned_count == 1, "reopened, returned once")


func test_return_keeps_the_hooks_reason() -> void:
	var b := Building.new()
	b.apply(TestSupport.ev("ticket.submit", 1, {"ticketId": "t1", "text": "x", "origin": "user"}, 1000))
	b.apply(TestSupport.ev("ticket.return", 2, {"ticketId": "t1", "reason": "Tests are failing"}, 2000))
	check(_chief(b).ticket.return_reason == "Tests are failing", "reason kept")
	check(_chief(b).ticket.returned_count == 1, "returned once")


func test_stale_sessions_leave() -> void:
	var b := Building.new()
	b.apply(TestSupport.ev("ticket.submit", 1, {"ticketId": "t1", "text": "x", "origin": "user"}, 1000))
	check(b.expire_stale(60_000).is_empty(), "not stale after a minute")
	check_eq(b.expire_stale(200_000), [{"kind": "chiefLeft", "projectId": "p", "sessionId": "s"},
		{"kind": "blockRemoved", "projectId": "p"}], "stale after two minutes")


func test_stale_uses_arrival_time_not_sender_clock() -> void:
	var b := Building.new()
	b.apply(TestSupport.ev("heartbeat", 1, {}, 1000), 10_000_000)
	check(b.expire_stale(10_060_000).is_empty(), "arrival time counts")


func test_sequencer_reorders() -> void:
	var q := Sequencer.new(500)
	var seqs := func(events: Array[TownEvent]) -> Array: return events.map(func(e: TownEvent) -> int: return e.seq)
	check_eq(seqs.call(q.push(TestSupport.ev("heartbeat", 1), 0)), [1], "first")
	check_eq(seqs.call(q.push(TestSupport.ev("heartbeat", 3), 10)), [], "3 waits for 2")
	check_eq(seqs.call(q.push(TestSupport.ev("heartbeat", 2), 20)), [2, 3], "2 releases 3")
	check_eq(seqs.call(q.push(TestSupport.ev("heartbeat", 5), 30)), [], "5 waits for 4")
	check_eq(seqs.call(q.flush(100)), [], "still waiting")
	check_eq(seqs.call(q.flush(600)), [5], "released after the window; 4 never came")


func test_block_goes_when_its_last_session_closes() -> void:
	var b := Building.new()
	var open := func(s: String, n: int) -> TownEvent:
		return TownEvent.make("session.open", s, n, n, "p", {"projectName": "demo"})
	b.apply(open.call("a", 1))
	b.apply(open.call("b", 2))
	check_eq(b.block_order, ["p"], "one block")
	var first := b.apply(TownEvent.make("session.close", "a", 3, 3, "p"))
	check(_kinds(first, "blockRemoved").is_empty(), "block stays while a session is left")
	var last := b.apply(TownEvent.make("session.close", "b", 4, 4, "p"))
	check(not _kinds(last, "blockRemoved").is_empty(), "block goes with the last session")
	check(b.block_order.is_empty(), "no blocks")


func test_auto_mode_approval_is_marked() -> void:
	var b := Building.new()
	b.apply(TestSupport.ev("ticket.submit", 1, {"ticketId": "t1", "text": "x", "origin": "user"}))
	check_eq(b.apply(TestSupport.ev("approval.wait", 2, {"approvalId": "u1", "tool": "Bash", "autoMode": true})),
		[{"kind": "approvalWait", "projectId": "p", "sessionId": "s", "approvalId": "u1", "agentId": null, "autoMode": true}], "quiet")
	check_eq(b.apply(TestSupport.ev("approval.wait", 3, {"approvalId": "u2", "tool": "Bash"})),
		[{"kind": "approvalWait", "projectId": "p", "sessionId": "s", "approvalId": "u2", "agentId": null, "autoMode": false}], "loud")


func test_session_open_brings_its_block() -> void:
	var b := Building.new()
	var c := b.apply(TestSupport.ev("session.open", 1, {"projectName": "demo"}))
	check_eq(c, [{"kind": "blockAdded", "projectId": "p"}, {"kind": "chiefArrived", "projectId": "p", "sessionId": "s"}], "changes")
	check((b.blocks["p"] as Building.Block).name == "demo", "named")


func test_compaction_starts_and_ends() -> void:
	var b := Building.new()
	b.apply(TestSupport.ev("session.open", 1))
	check_eq(b.apply(TestSupport.ev("compact.start", 2, {"trigger": "manual"})),
		[{"kind": "compactStarted", "projectId": "p", "sessionId": "s", "trigger": "manual"}], "start")
	check(_chief(b).compacting, "compacting")
	check_eq(b.apply(TestSupport.ev("compact.end", 3, {"outcome": "done", "tokensBefore": 150_000, "tokensAfter": 20_000})),
		[{"kind": "compactDone", "projectId": "p", "sessionId": "s", "outcome": "done", "tokensBefore": 150_000,
			"tokensAfter": 20_000}], "end")
	check(not _chief(b).compacting, "done compacting")
	check(b.apply(TestSupport.ev("compact.end", 4, {"outcome": "done"})).is_empty(), "an end with no start changes nothing")


func test_context_updates_keep_each_field() -> void:
	var b := Building.new()
	b.apply(TestSupport.ev("context.update", 1, {"window": 200_000}))
	b.apply(TestSupport.ev("context.update", 2, {"effort": "high"}))
	var c := b.apply(TestSupport.ev("context.update", 3, {"tokens": 84_000, "percent": 42}))
	check_eq(c.back(), {"kind": "context", "projectId": "p", "sessionId": "s"}, "change")
	var ctx := _chief(b).context
	check_eq([ctx.tokens, ctx.window, ctx.percent, ctx.effort, ctx.last_turn_tokens], [84_000, 200_000, 42, "high", null], "fields")
	check(is_equal_approx(ctx.fraction(), 0.42), "fraction")


func test_ticket_title_sticks_to_its_own_ticket() -> void:
	var b := Building.new()
	b.apply(TestSupport.ev("ticket.submit", 1, {"ticketId": "t1", "text": "Fix the sound"}))
	b.apply(TestSupport.ev("ticket.title", 2, {"ticketId": "old", "title": "Stale"}))
	check(_chief(b).ticket.title == null, "another ticket's title is ignored")
	b.apply(TestSupport.ev("ticket.title", 3, {"ticketId": "t1", "title": "  Sound fix \n"}))
	check(_chief(b).ticket.title == "Sound fix", "trimmed")


func test_context_keeps_the_last_turns_tokens() -> void:
	var b := Building.new()
	b.apply(TestSupport.ev("context.update", 1, {"window": 1_000_000, "lastTurnTokens": 137_500}))
	check(_chief(b).context.last_turn_tokens == 137_500, "last turn tokens")


func test_batches_skip_bad_events() -> void:
	var batch: Variant = TownEvent.decode_batch('{"protocol":1,"events":[{"type":"heartbeat","sessionId":"s","seq":1,"ts":5,"projectId":"p"},{"type":"heartbeat"}]}')
	check(batch != null, "decodes")
	if batch != null:
		check(batch["protocol"] == 1, "protocol")
		check((batch["events"] as Array).size() == 1, "the bad event is skipped")
	check(TownEvent.decode_batch("not json") == null, "not a batch")


static func _chief(b: Building) -> Building.Chief:
	return (b.blocks["p"] as Building.Block).chiefs["s"]
