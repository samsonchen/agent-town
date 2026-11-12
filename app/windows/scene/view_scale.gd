class_name ViewScale
extends RefCounted
## Compact view (Settings → Office; read once at launch, so a change applies after a restart): the
## office is drawn at half scale and its text at 75%, the smallest that stays readable. The layout
## in meters is the same either way. Port of `ViewScale` in app/macos/Sources/AgentTown/Layout.swift.

static var compact := false
## The office's drawing scale.
static var world := 1.0
## Tags, signs, statements and context bars.
static var text := 1.0


static func set_compact(on: bool) -> void:
	compact = on
	world = 0.5 if on else 1.0
	text = 0.75 if on else 1.0
