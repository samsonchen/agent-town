class_name LoopbackServer
extends RefCounted
## The loopback HTTP server: binds 127.0.0.1 on a random port, writes the endpoint file, checks
## each request (TownHTTP.handle) and hands accepted batches over. It does no threading: call
## `poll()` often (the store does, every frame). Port of app/macos/Sources/AgentTown/Server.swift.

## A connection that has not sent a whole request by then is closed.
const REQUEST_TIMEOUT_MS := 5000
const MAX_CONNECTIONS := 32

var token := EndpointFile.new_token()
var port := 0
var endpoint_path := ""

var _server := TCPServer.new()
var _conns: Array[Dictionary] = [] ## {"peer": StreamPeerTCP, "buf": PackedByteArray, "since": int}


## Listens and writes the endpoint file. `path` defaults to %APPDATA%\agent-town-claude-code\endpoint.json.
func start(app_version: String, path: String = "") -> Error:
	var err := _server.listen(0, "127.0.0.1")
	if err != OK:
		return err
	port = _server.get_local_port()
	endpoint_path = path if path != "" else EndpointFile.default_path()
	err = EndpointFile.write(endpoint_path, port, token, OS.get_process_id(), app_version)
	if err != OK:
		_server.stop()
		return err
	return OK


## Closes the server and removes the endpoint file if it is still ours.
func stop() -> void:
	for c: Dictionary in _conns:
		(c["peer"] as StreamPeerTCP).disconnect_from_host()
	_conns.clear()
	_server.stop()
	if endpoint_path != "":
		EndpointFile.remove(endpoint_path, OS.get_process_id())


func is_listening() -> bool:
	return _server.is_listening()


## Accepts connections, reads what has arrived, answers whole requests. Returns the accepted
## batches, each {"protocol": int, "events": Array[TownEvent]}.
func poll(now_ms: int = Time.get_ticks_msec()) -> Array[Dictionary]:
	var batches: Array[Dictionary] = []
	while _server.is_connection_available():
		var peer := _server.take_connection()
		if _conns.size() >= MAX_CONNECTIONS:
			peer.disconnect_from_host()
			continue
		_conns.append({"peer": peer, "buf": PackedByteArray(), "since": now_ms})
	var keep: Array[Dictionary] = []
	for c: Dictionary in _conns:
		var peer: StreamPeerTCP = c["peer"]
		peer.poll()
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			continue
		var n := peer.get_available_bytes()
		if n > 0:
			var got: Array = peer.get_partial_data(n)
			if got[0] == OK:
				# A PackedByteArray is copied on write: append to a local one and store it back.
				var buf: PackedByteArray = c["buf"]
				buf.append_array(got[1])
				c["buf"] = buf
		var req := TownHTTP.parse(c["buf"])
		match req["result"]:
			"complete":
				var r := TownHTTP.handle(req, token)
				_reply(peer, r["status"])
				if r["batch"] != null:
					batches.append(r["batch"])
			"invalid":
				_reply(peer, 400)
			_:
				if now_ms - int(c["since"]) > REQUEST_TIMEOUT_MS:
					peer.disconnect_from_host()
				else:
					keep.append(c)
	_conns = keep
	return batches


func _reply(peer: StreamPeerTCP, status: int) -> void:
	peer.put_data(TownHTTP.response(status))
	peer.disconnect_from_host()
