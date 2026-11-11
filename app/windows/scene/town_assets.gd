class_name TownAssets
extends RefCounted
## Loads the Kenney models (copied to res://shared/kenney/) and builds characters with their own
## outfit color. Port of app/macos/Sources/AgentTown/Assets.swift; Godot imports the GLB files
## directly, each character with its clips already separate, so there is no clip table.

const CHARACTERS := "res://shared/kenney/mini-characters/"
const FURNITURE := "res://shared/kenney/furniture-kit/"

## Clips made from part of another, played back and forth: a hand tapping at the reach of `interact`,
## for typing (alternating hands) and writing (one hand, slower). name -> [base, from, to, speed].
const DERIVED := {
	"type-right": ["interact-right", 0.35, 0.6, 1.4],
	"type-left": ["interact-left", 0.35, 0.6, 1.4],
	"write": ["interact-right", 0.4, 0.6, 0.7],
}

var catalog: Dictionary ## catalog/characters.json
var _motion: Dictionary = {} ## model name -> [loop library, derived library]
var _colormap: Image
var _cell_w := 32
var _cell_h := 128
var _texture_cache: Dictionary = {} ## "base|#rrggbb" -> ImageTexture
var _scenes: Dictionary = {} ## path -> PackedScene


func _init() -> void:
	catalog = TownLabels._json("res://shared/catalog/characters.json")
	var tex: Texture2D = load(CHARACTERS + "Textures/colormap.png")
	_colormap = tex.get_image()
	_colormap.decompress()
	_colormap.convert(Image.FORMAT_RGBA8)
	var t: Dictionary = catalog["texture"]
	var scale := _colormap.get_width() / int(t["size"])
	_cell_w = int(t["cellWidth"]) * scale
	_cell_h = int(t["cellHeight"]) * scale


func _scene(path: String) -> PackedScene:
	if not _scenes.has(path):
		_scenes[path] = load(path)
	return _scenes[path]


## A furniture model, a fresh copy each call.
func furniture(name: String) -> Node3D:
	return _scene(FURNITURE + name + ".glb").instantiate()


## The base characters, sorted (male-a … female-f).
func character_names() -> Array[String]:
	var out: Array[String] = []
	for k: String in (catalog["characters"] as Dictionary).keys():
		out.append(k)
	out.sort()
	return out


## A character model with its shirt cells tinted to `outfit` ("#rrggbb"); "" keeps its own colors.
func character(base: String, outfit: String = "") -> Node3D:
	var info: Dictionary = catalog["characters"][base]
	var model: Node3D = _scene(CHARACTERS + info["model"] + ".glb").instantiate()
	model.name = base
	if outfit != "":
		dress(model, base, outfit)
	return model


## Gives a character's AnimationPlayer two more libraries, shared by all copies of its model:
## "loop/<clip>", each clip looping, and "derived/<name>" for DERIVED. The imported clips stay
## one-shot, so a clip can play either way without changing it for every character.
func attach_motion(player: AnimationPlayer, model_name: String) -> void:
	if not _motion.has(model_name):
		var loops := AnimationLibrary.new()
		var derived := AnimationLibrary.new()
		for clip: String in player.get_animation_list():
			var a := player.get_animation(clip).duplicate() as Animation
			a.loop_mode = Animation.LOOP_LINEAR
			loops.add_animation(clip, a)
		for name: String in DERIVED:
			var src: String = DERIVED[name][0]
			if player.has_animation(src):
				var a := player.get_animation(src).duplicate() as Animation
				a.loop_mode = Animation.LOOP_PINGPONG
				derived.add_animation(name, a)
		_motion[model_name] = [loops, derived]
	player.add_animation_library("loop", _motion[model_name][0])
	player.add_animation_library("derived", _motion[model_name][1])


## Changes a character's outfit color (a staff member changing into a role's department color).
func dress(model: Node3D, base: String, outfit: String) -> void:
	var tex := _texture(base, outfit)
	for mi: Node in model.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		for s in m.mesh.get_surface_count():
			var mat := m.mesh.surface_get_material(s) as StandardMaterial3D
			if mat == null:
				continue
			var copy := mat.duplicate() as StandardMaterial3D
			copy.albedo_texture = tex
			m.set_surface_override_material(s, copy)


## The colormap with this character's shirt cells tinted to `color`, keeping each pixel's shading.
func _texture(base: String, color: String) -> ImageTexture:
	var key := base + "|" + color
	if _texture_cache.has(key):
		return _texture_cache[key]
	var img := _colormap.duplicate() as Image
	var c := Color(color)
	for cell: Dictionary in catalog["characters"][base]["shirt"]:
		var x0 := int(cell["col"]) * _cell_w
		var y0 := int(cell["row"]) * _cell_h
		var sum := 0.0
		for y in range(y0, y0 + _cell_h):
			for x in range(x0, x0 + _cell_w):
				sum += _lum(img.get_pixel(x, y))
		var mean := maxf(1.0 / 255.0, sum / float(_cell_w * _cell_h))
		for y in range(y0, y0 + _cell_h):
			for x in range(x0, x0 + _cell_w):
				var k := clampf(_lum(img.get_pixel(x, y)) / mean, 0.65, 1.35)
				img.set_pixel(x, y, Color(minf(1.0, c.r * k), minf(1.0, c.g * k), minf(1.0, c.b * k), 1.0))
	var tex := ImageTexture.create_from_image(img)
	_texture_cache[key] = tex
	return tex


static func _lum(p: Color) -> float:
	return 0.299 * p.r + 0.587 * p.g + 0.114 * p.b
