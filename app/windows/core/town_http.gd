class_name TownHTTP
extends RefCounted
## Just enough HTTP/1.1 for POST /v1/events, and the checks the server makes on each request
## (docs/protocol.md: responses). Port of HTTPParser and EventEndpoint in
## app/macos/Sources/TownCore/Endpoint.swift.

const MAX_HEAD := 16_384
const MAX_BODY := 4 << 20

const REASONS := {204: "No Content", 400: "Bad Request", 401: "Unauthorized", 404: "Not Found",
	405: "Method Not Allowed", 413: "Payload Too Large", 426: "Upgrade Required"}


## Parses one request from the start of `data`. Returns a Dictionary:
##   {"result": "incomplete"} | {"result": "invalid"} |
##   {"result": "complete", "method", "path", "headers" (lowercased names), "body": PackedByteArray, "consumed": int}
static func parse(data: PackedByteArray, max_body: int = MAX_BODY) -> Dictionary:
	var head_end := _find_head_end(data)
	if head_end < 0:
		return {"result": "invalid" if data.size() > MAX_HEAD else "incomplete"}
	var head := data.slice(0, head_end).get_string_from_utf8()
	var lines := head.split("\r\n")
	var parts := lines[0].split(" ", false)
	if parts.size() != 3:
		return {"result": "invalid"}
	var headers: Dictionary = {}
	for i in range(1, lines.size()):
		var c := lines[i].find(":")
		if c < 0:
			continue
		headers[lines[i].substr(0, c).strip_edges().to_lower()] = lines[i].substr(c + 1).strip_edges()
	var length_text: String = headers.get("content-length", "0")
	if not length_text.is_valid_int():
		return {"result": "invalid"}
	var length := length_text.to_int()
	if length < 0 or length > max_body:
		return {"result": "invalid"}
	var body_start := head_end + 4
	if data.size() - body_start < length:
		return {"result": "incomplete"}
	return {"result": "complete", "method": parts[0], "path": parts[1], "headers": headers,
		"body": data.slice(body_start, body_start + length), "consumed": body_start + length}


static func _find_head_end(data: PackedByteArray) -> int:
	for i in range(0, data.size() - 3):
		if data[i] == 13 and data[i + 1] == 10 and data[i + 2] == 13 and data[i + 3] == 10:
			return i
	return -1


## The whole response for a status: no body, and the connection closes.
static func response(status: int) -> PackedByteArray:
	var reason: String = REASONS.get(status, "Error")
	return ("HTTP/1.1 %d %s\r\nContent-Length: 0\r\nConnection: close\r\n\r\n" % [status, reason]).to_utf8_buffer()


## The checks on one parsed request. Returns {"status": int, "batch": Dictionary or null}, where a batch is
## {"protocol": int, "events": Array[TownEvent]}.
static func handle(req: Dictionary, token: String) -> Dictionary:
	if req.get("path") != "/v1/events":
		return {"status": 404, "batch": null}
	if req.get("method") != "POST":
		return {"status": 405, "batch": null}
	if (req.get("headers", {}) as Dictionary).get("authorization", "") != "Bearer " + token:
		return {"status": 401, "batch": null}
	# Read the version alone first, so a future version in another shape gets 426, not 400.
	var text := (req["body"] as PackedByteArray).get_string_from_utf8()
	var json := JSON.new()
	if json.parse(text) != OK or typeof(json.data) != TYPE_DICTIONARY:
		return {"status": 400, "batch": null}
	var version: Variant = (json.data as Dictionary).get("protocol")
	if typeof(version) != TYPE_INT and typeof(version) != TYPE_FLOAT:
		return {"status": 400, "batch": null}
	if int(version) != EndpointFile.PROTOCOL_VERSION:
		return {"status": 426, "batch": null}
	var batch: Variant = TownEvent.decode_batch(text)
	if batch == null:
		return {"status": 400, "batch": null}
	return {"status": 204, "batch": batch}
