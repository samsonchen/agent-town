class_name BlockNode
extends RefCounted
## One office block: the executive office, or a project's office with its desks, server room and
## resource bench. Port of `BlockNode` in app/macos/Sources/AgentTown/Actors.swift.

var id: String
var name: String
var node := Node3D.new()
var placed := false
var desk_phones: Dictionary = {} ## desk slot -> TownPhone on a Chief of Staff desk
var chief_slots: Dictionary = {} ## session_id -> Chief of Staff desk slot

var bench: Array[TownActor] = [] ## characters waiting on the bench
var bench_spots: Dictionary = {} ## actor id -> bench spot index
var staff_slots: Dictionary = {} ## actor id -> staff desk slot
var console_slots: Dictionary = {} ## actor id -> console slot
var jobs: Dictionary = {} ## job key -> TownActor doing it
var pending_done: Dictionary = {} ## job key -> status, for jobs that ended before their character got to work
var deferred: Dictionary = {} ## job key -> Array[Callable], messages from characters still on their way
var speaker: Node3D = null ## the bench's speaker, for paging
var carried: Dictionary = {} ## back-row slot -> desk Node3D carried in and set down
var active_desk: Dictionary = {} ## session -> job key of the desk worker with the main agent's work now
var temp_slots: Dictionary = {} ## actor id -> back-row slot, for staff who carry a desk in
var leaving_slots: Array[int] = [] ## back-row slots whose Chief left but whose desk is not carried out yet


## A back-row slot with no Chief, no desk carried in, and no one bringing or taking one.
func free_back_slot() -> int:
	for b in range(1, Layout.MAX_DESKS):
		if not chief_slots.values().has(b) and not temp_slots.values().has(b) and not carried.has(b) and not leaving_slots.has(b):
			return b
	return -1


## The lowest slot number not in `used` (below `limit`).
static func free_slot(used: Dictionary, limit: int = 64) -> int:
	var taken := used.values()
	for i in limit:
		if not taken.has(i):
			return i
	return limit
