class_name EndpointFile
extends RefCounted
## The endpoint file the app writes so town-link can find it (docs/protocol.md): on Windows
## %APPDATA%\agent-town\endpoint.json. The file is protected by where it is, the user's own profile.
## Port of EndpointFile in app/macos/Sources/TownCore/Endpoint.swift.

const PROTOCOL_VERSION := 1


static func default_path() -> String:
	return OS.get_environment("APPDATA").path_join("agent-town").path_join("endpoint.json")


## A fresh 32-byte random token, base64url without padding (43 characters).
static func new_token() -> String:
	var b64 := Marshalls.raw_to_base64(Crypto.new().generate_random_bytes(32))
	return b64.replace("+", "-").replace("/", "_").replace("=", "")


## Writes the file in one step: a temporary file, then a rename over the old one.
static func write(path: String, port: int, token: String, pid: int, app_version: String) -> Error:
	var err := DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if err != OK and err != ERR_ALREADY_EXISTS:
		return err
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify({"protocol": PROTOCOL_VERSION, "port": port, "token": token, "pid": pid,
		"app": "agent-town", "appVersion": app_version}))
	f.close()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	return DirAccess.rename_absolute(tmp, path)


## Reads the file, or null when it is missing or not an endpoint file.
static func read(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK or typeof(json.data) != TYPE_DICTIONARY:
		return null
	return json.data


## Deletes the file only if it is ours (same pid), so another running copy's file survives.
static func remove(path: String, pid: int) -> void:
	var f: Variant = read(path)
	if f != null and int((f as Dictionary).get("pid", -1)) == pid:
		DirAccess.remove_absolute(path)
