extends TestSupport
## The HTTP parser, the request checks, the endpoint file and a real loopback round trip.
## The first three are ports of app/macos/Tests/TownCoreTests/EndpointTests.swift.

const GOOD_BODY := '{"protocol":1,"events":[{"type":"heartbeat","sessionId":"s","seq":1,"ts":1,"projectId":"p"},{"type":"x"}]}'


static func _request(body: String, token: String = "tok", path: String = "/v1/events", method: String = "POST") -> PackedByteArray:
	return ("%s %s HTTP/1.1\r\nHost: 127.0.0.1\r\nAuthorization: Bearer %s\r\nContent-Type: application/json\r\nContent-Length: %d\r\n\r\n%s"
		% [method, path, token, body.to_utf8_buffer().size(), body]).to_utf8_buffer()


func _status(data: PackedByteArray, token: String = "tok") -> int:
	var req := TownHTTP.parse(data)
	return int(TownHTTP.handle(req, token)["status"]) if req["result"] == "complete" else -1


func test_parses_a_whole_request_and_waits_for_a_partial_one() -> void:
	var full := _request(GOOD_BODY)
	var req := TownHTTP.parse(full)
	check(req["result"] == "complete", "complete")
	if req["result"] == "complete":
		check(req["consumed"] == full.size(), "consumed all")
		check((req["headers"] as Dictionary).get("content-type") == "application/json", "headers lowercased")
	check(TownHTTP.parse(full.slice(0, full.size() - 3))["result"] == "incomplete", "partial body waits")
	check(TownHTTP.parse("GET /\r\n\r\n".to_utf8_buffer())["result"] == "invalid", "bad request line")


func test_endpoint_statuses() -> void:
	check_eq(_status(_request(GOOD_BODY)), 204, "good")
	check_eq(_status(_request(GOOD_BODY, "wrong")), 401, "wrong token")
	check_eq(_status(_request(GOOD_BODY, "tok", "/other")), 404, "other path")
	check_eq(_status(_request(GOOD_BODY, "tok", "/v1/events", "GET")), 405, "GET")
	check_eq(_status(_request('{"protocol":2,"events":[]}')), 426, "future version")
	check_eq(_status(_request('{"protocol":2,"items":{"a":1}}')), 426, "future version in another shape")
	check_eq(_status(_request('{"events":[]}')), 400, "no version")
	check_eq(_status(_request("not json")), 400, "not JSON")
	var r := TownHTTP.handle(TownHTTP.parse(_request(GOOD_BODY)), "tok")
	check(r["batch"] != null and (r["batch"]["events"] as Array).size() == 1, "a malformed event is skipped, the rest kept")


func test_endpoint_file_is_removed_only_by_its_owner() -> void:
	var path := OS.get_temp_dir().path_join("agent-town-test-%d" % randi()).path_join("endpoint.json")
	var token := EndpointFile.new_token()
	check(token.length() == 43, "token is 43 characters")
	check(EndpointFile.write(path, 4242, token, 1000, "test") == OK, "written")
	check_eq(EndpointFile.read(path), {"protocol": 1, "port": 4242, "token": token, "pid": 1000, "app": "agent-town",
		"appVersion": "test"}, "contents")
	check(EndpointFile.write(path, 4243, token, 1000, "test") == OK, "rewritten over the old one")
	check(int((EndpointFile.read(path) as Dictionary)["port"]) == 4243, "new port")
	EndpointFile.remove(path, 1001)
	check(FileAccess.file_exists(path), "another pid leaves it")
	EndpointFile.remove(path, 1000)
	check(not FileAccess.file_exists(path), "its own pid removes it")
	DirAccess.remove_absolute(path.get_base_dir())


## Sends raw bytes to the server over a real socket and returns the HTTP status it answers.
func _round_trip(server: LoopbackServer, data: PackedByteArray, batches: Array[Dictionary]) -> int:
	var client := StreamPeerTCP.new()
	if client.connect_to_host("127.0.0.1", server.port) != OK:
		return -1
	var reply := PackedByteArray()
	var sent := false
	for i in 200:
		client.poll()
		batches.append_array(server.poll())
		if client.get_status() == StreamPeerTCP.STATUS_CONNECTED:
			if not sent:
				client.put_data(data)
				sent = true
			var n := client.get_available_bytes()
			if n > 0:
				reply.append_array(client.get_partial_data(n)[1])
		elif sent and client.get_status() != StreamPeerTCP.STATUS_CONNECTING:
			break
		var text := reply.get_string_from_utf8()
		if text.contains("\r\n\r\n"):
			return text.get_slice(" ", 1).to_int()
		OS.delay_msec(5)
	var text := reply.get_string_from_utf8()
	return text.get_slice(" ", 1).to_int() if text.begins_with("HTTP/1.1 ") else -1


func test_server_answers_over_loopback_and_hands_batches_over() -> void:
	var path := OS.get_temp_dir().path_join("agent-town-test-%d" % randi()).path_join("endpoint.json")
	var server := LoopbackServer.new()
	check(server.start("test", path) == OK, "starts")
	var f: Variant = EndpointFile.read(path)
	check(f != null and int(f["port"]) == server.port and f["token"] == server.token, "endpoint file names the port and token")
	var batches: Array[Dictionary] = []
	check_eq(_round_trip(server, _request(GOOD_BODY, server.token), batches), 204, "accepted")
	check(batches.size() == 1 and (batches[0]["events"] as Array).size() == 1, "batch handed over")
	check_eq(_round_trip(server, _request(GOOD_BODY, "wrong"), batches), 401, "wrong token refused")
	check_eq(_round_trip(server, _request('{"protocol":2,"events":[]}', server.token), batches), 426, "future version refused")
	check(batches.size() == 1, "refused batches are not handed over")
	server.stop()
	check(not FileAccess.file_exists(path), "stop removes the endpoint file")
	DirAccess.remove_absolute(path.get_base_dir())


func test_store_applies_batches_in_order() -> void:
	var store := TownStore.new()
	var seen: Array[String] = []
	store.changed.connect(func(c: Dictionary) -> void: seen.append(c["kind"]))
	var ev := func(type: String, seq: int, fields: Dictionary = {}) -> TownEvent:
		return TownEvent.make(type, "s", seq, seq, "p", fields)
	# seq 2 arrives before seq 1; the store waits for 1, then applies both in order.
	var e2: TownEvent = ev.call("ticket.submit", 2, {"ticketId": "t1", "text": "x"})
	var e1: TownEvent = ev.call("session.open", 1, {"projectName": "demo"})
	store.receive({"protocol": 1, "events": [e2] as Array[TownEvent]}, 1000)
	store.receive({"protocol": 1, "events": [e1] as Array[TownEvent]}, 1010)
	check_eq(seen, ["blockAdded", "chiefArrived", "ticketSubmitted"], "in seq order")
	check(store.last_event_ms == 1010, "last event time")
	store.free()
