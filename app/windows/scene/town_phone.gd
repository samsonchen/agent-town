class_name TownPhone
extends RefCounted
## A desk telephone (or the Dispatcher's radio): the device on the desk and the part lifted to the
## ear. Port of `Phone` in app/macos/Sources/AgentTown/Actors.swift.

var device: Node3D
var handset: Node3D
var ringing := false
var tag_lift := 0.12 ## how far above the device the ring tag sits
var _rest: Transform3D


func _init(p_device: Node3D, p_handset: Node3D) -> void:
	device = p_device
	handset = p_handset
	_rest = handset.transform


## The top of the device, for the ring tag.
func anchor() -> Vector3:
	return device.global_position + Vector3(0, tag_lift, 0)


## Shakes the device for `seconds`.
func ring(seconds: float) -> void:
	if ringing or not is_instance_valid(device):
		return
	ringing = true
	var base := device.basis
	var steps := int(seconds / 0.1)
	for i in steps:
		if not is_instance_valid(device):
			return
		device.basis = base if i == steps - 1 else base * Basis(Vector3.UP, 0.18 if i % 2 == 0 else -0.18)
		await device.get_tree().create_timer(0.1).timeout
	if is_instance_valid(device):
		device.basis = base
	ringing = false


## Lifts the handset to `a`'s ear.
func lift(a: TownActor) -> void:
	if not is_instance_valid(handset) or not is_instance_valid(a.root):
		return
	var ear := a.root.global_transform * (Vector3(0.13, 0.43, 0.06) * (Layout.CHARACTER_SCALE / 0.75) / a.root.scale)
	var to := Transform3D(a.root.global_basis.orthonormalized() * Basis(Vector3.BACK, PI / 2.0), ear)
	var tw := handset.create_tween()
	tw.tween_property(handset, "global_transform", to, 0.3)


func hang_up() -> void:
	if not is_instance_valid(handset):
		return
	var tw := handset.create_tween()
	tw.tween_property(handset, "transform", _rest, 0.3)
