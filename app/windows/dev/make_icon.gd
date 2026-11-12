extends SceneTree
## Writes installer/agent-town.ico from the shared app icon: PNG images at 16 to 256 pixels in one
## ICO file (Windows Vista and later read PNG inside ICO). Run after the app icon changes:
##   godot --headless --path app/windows --script res://dev/make_icon.gd

const SIZES := [16, 24, 32, 48, 64, 128, 256]


func _initialize() -> void:
	var src := Image.load_from_file(ProjectSettings.globalize_path("res://shared/icons/app-icon-1024.png"))
	var pngs: Array[PackedByteArray] = []
	for s: int in SIZES:
		var img := src.duplicate() as Image
		img.resize(s, s, Image.INTERPOLATE_LANCZOS)
		pngs.append(img.save_png_to_buffer())
	var out := PackedByteArray()
	out.append_array(_u16(0) + _u16(1) + _u16(SIZES.size())) # reserved, type icon, count
	var offset := 6 + 16 * SIZES.size()
	for i in SIZES.size():
		var s: int = SIZES[i]
		out.append(s % 256) # 256 is written as 0
		out.append(s % 256)
		out.append(0) # palette
		out.append(0) # reserved
		out.append_array(_u16(1) + _u16(32) + _u32(pngs[i].size()) + _u32(offset))
		offset += pngs[i].size()
	for p in pngs:
		out.append_array(p)
	var path := ProjectSettings.globalize_path("res://installer/agent-town.ico")
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(out)
	f.close()
	print("wrote ", path, " (", out.size(), " bytes)")
	quit()


static func _u16(v: int) -> PackedByteArray:
	return PackedByteArray([v & 0xFF, (v >> 8) & 0xFF])


static func _u32(v: int) -> PackedByteArray:
	return PackedByteArray([v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF])
