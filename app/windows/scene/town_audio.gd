class_name TownAudio
extends Node
## Plays the three sounds (spec: sounds) from the Windows system sounds in C:\Windows\Media,
## loaded at run time and never bundled (docs/windows/spec.md). A missing file plays nothing.

const MEDIA := "C:/Windows/Media/"
const FILES := {
	"completion": "Windows Notify System Generic.wav",
	"approval": "Windows Notify Messaging.wav",
	"dispatch": "Windows Ringout.wav",
}

var muted := false
var volume := 1.0 ## 0 to 1
var _streams: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []


func _ready() -> void:
	for key: String in FILES:
		var path: String = MEDIA + FILES[key]
		if FileAccess.file_exists(path):
			_streams[key] = AudioStreamWAV.load_from_file(path)
	for i in 3:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)


func play(key: String) -> void:
	if muted or not _streams.has(key):
		return
	for p in _players:
		if not p.playing:
			p.stream = _streams[key]
			p.volume_db = linear_to_db(maxf(0.001, volume))
			p.play()
			return
