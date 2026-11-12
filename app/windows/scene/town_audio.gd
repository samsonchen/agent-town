class_name TownAudio
extends Node
## Plays the three sounds (spec: sounds, sound settings). Each plays the user's choice: a sound
## from C:\Windows\Media (never bundled), or a WAV, MP3 or Ogg file of their own; a choice that
## cannot be loaded falls back to the default, and a missing default plays nothing.

const MEDIA := "C:/Windows/Media/"
const DEFAULTS := {
	"completion": "Windows Notify",
	"approval": "Windows Exclamation",
	"dispatch": "Windows Battery Low",
}
const FILE_TYPES: Array[String] = ["wav", "mp3", "ogg"]

var muted := false ## the tray menu's Sound item: off mutes all three
var volume := 1.0 ## 0 to 1
var enabled: Dictionary = {"dispatch": true, "completion": true, "approval": true}
var _choices: Dictionary = {"dispatch": "", "completion": "", "approval": ""}
var _streams: Dictionary = {} ## key -> AudioStream, or no entry when nothing can play
var _players: Array[AudioStreamPlayer] = []


func _ready() -> void:
	for i in 3:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	for key: String in DEFAULTS:
		_load(key)


## Sets a sound's choice ("" for the default, "media:<name>", "file:<path>") and loads it.
func choose(key: String, choice: String) -> void:
	_choices[key] = choice
	_load(key)


## Plays a sound for an event in the office, unless muted or switched off.
func play(key: String) -> void:
	if muted or not enabled.get(key, true):
		return
	_play_stream(_streams.get(key))


## Plays a sound once from Settings' Play button, whatever the switches say.
func preview(key: String) -> void:
	_play_stream(_streams.get(key))


func _play_stream(stream: AudioStream) -> void:
	if stream == null:
		return
	for p in _players:
		if not p.playing:
			p.stream = stream
			p.volume_db = linear_to_db(maxf(0.0001, volume))
			p.play()
			return


func _load(key: String) -> void:
	var stream := load_stream(path_for(_choices.get(key, "")))
	if stream == null:
		stream = load_stream(path_for("media:" + DEFAULTS[key]))
	if stream == null:
		_streams.erase(key)
	else:
		_streams[key] = stream


## The file a choice names, or "" for the default.
static func path_for(choice: String) -> String:
	if choice.begins_with("media:"):
		return MEDIA + choice.substr(6) + ".wav"
	if choice.begins_with("file:"):
		return choice.substr(5)
	return ""


## Loads a WAV, MP3 or Ogg Vorbis file at run time, or null when it is missing or unreadable.
static func load_stream(path: String) -> AudioStream:
	if path == "" or not FileAccess.file_exists(path):
		return null
	match path.get_extension().to_lower():
		"wav":
			return AudioStreamWAV.load_from_file(path)
		"mp3":
			return AudioStreamMP3.load_from_file(path)
		"ogg":
			return AudioStreamOggVorbis.load_from_file(path)
	return null


## The sounds Settings lists: every WAV in C:\Windows\Media, by name, sorted.
static func media_names() -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(MEDIA)
	if dir == null:
		return out
	for f in dir.get_files():
		if f.get_extension().to_lower() == "wav":
			out.append(f.get_basename())
	out.sort_custom(func(a: String, b: String) -> bool: return a.naturalnocasecmp_to(b) < 0)
	return out
