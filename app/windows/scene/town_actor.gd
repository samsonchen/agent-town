class_name TownActor
extends RefCounted
## One character on screen, with its own queue of story actions (spec: timing rules): each action
## is a coroutine, and they play one after another at full length. Port of `Actor` in
## app/macos/Sources/AgentTown/Actors.swift.

var id: String
var kind: String ## ceo, dispatcher, inspector, chief, worker
var block_id: String
var name: String
var base: String
var scene: TownScene

var root := Node3D.new()
var model: Node3D
var player: AnimationPlayer
var shadow: MeshInstance3D
var current_clip := ""

var hat: Variant = null
var ticket_text: Variant = null
var bubble: Variant = null
var speaking := false ## a speech bubble with no text (spec scene 16)
var model_id: Variant = null
var working := false
var carrying: Node3D = null ## a desk held above the head
var delegating := false ## a Chief of Staff whose ticket staff are working on waits instead of typing
var activity: Variant = null
var phone: TownPhone = null
var on_call := false
var awaiting_approval := false
var steering := false ## the CEO walks under the user's control; scenes leave its animation alone
var home := Vector2.ZERO
var home_facing := Vector2(0, 1)

# Staff and operators (kind "worker").
var role: Variant = null ## the current role, or the last one while waiting on the bench
var department: Variant = null ## the department whose color it wears; null for the neutral outfit
var outfit := ""
var is_operator := false
var job: Variant = null ## "a:<session>/<agentId>" or "t:<session>/<taskId>"
var at_work := false
var waiting_since := 0
var sitting := false
var has_computer := false ## works at a desk with a computer (types); otherwise writes
var note: Variant = null

var _queue: Array[Callable] = []
var _running := false


func _init(p_scene: TownScene, p_id: String, p_kind: String) -> void:
	scene = p_scene
	id = p_id
	kind = p_kind


## The character's position on its block's floor (x, z).
func spot() -> Vector2:
	return Vector2(root.position.x, root.position.z)


## A point `above` meters over the top of the head, following the lean.
func head(above: float = 0.0) -> Vector3:
	return root.global_position + Basis(Vector3.RIGHT, TownScene.LEAN) * Vector3(0, 0.67 * Layout.CHARACTER_SCALE + above, 0)


## Story actions play one after another, each at full length. `action` may await.
func enqueue(action: Callable) -> void:
	_queue.append(action)
	if not _running:
		_run()


func _run() -> void:
	_running = true
	while not _queue.is_empty():
		var next: Callable = _queue.pop_front()
		await next.call()
	_running = false


func is_busy() -> bool:
	return _running


## Plays a clip by name: a looping one unless `loop` is false; "type-right", "type-left" and
## "write" are parts of the interact clips (TownAssets.DERIVED).
func play(clip: String, loop: bool = true, blend: float = 0.15) -> void:
	if player == null or clip == current_clip or not is_instance_valid(player):
		return
	current_clip = clip
	if TownAssets.DERIVED.has(clip):
		var d: Array = TownAssets.DERIVED[clip]
		var length := player.get_animation("derived/" + clip).length
		player.play_section("derived/" + clip, length * float(d[1]), length * float(d[2]), blend, float(d[3]))
	elif loop and player.has_animation("loop/" + clip):
		player.play("loop/" + clip, blend)
	elif player.has_animation(clip):
		player.stop()
		player.play(clip, blend)


## The looping clip for where the character is now (spec: activities).
func settle() -> void:
	if on_call or steering:
		return
	if awaiting_approval:
		play("holding-right")
	elif working and not delegating:
		if is_operator:
			play("interact-left" if activity == "shell" else "interact-right") # hands on the racks
		else:
			play("type-right" if has_computer else "write") # typing at the computer, else writing
	elif sitting:
		play("sit")
	else:
		play("idle")
