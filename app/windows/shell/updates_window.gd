class_name UpdatesWindow
extends Window
## The Updates window: what is newer and how to update it (docs/spec.md: Updates). Port of
## `UpdatesView` in app/macos/Sources/AgentTown/Updates.swift.

var updater: Updater
var labels: TownLabels
var _box: VBoxContainer
var _margin: MarginContainer


func _init(p_updater: Updater, p_labels: TownLabels) -> void:
	updater = p_updater
	labels = p_labels
	title = labels.t("Updates")
	transient = true
	unresizable = true
	theme = SettingsWindow.ui_theme()
	close_requested.connect(hide)


func _ready() -> void:
	var margin := MarginContainer.new()
	_margin = margin
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	add_child(margin)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 12)
	outer.custom_minimum_size = Vector2(520, 0)
	margin.add_child(outer)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 8)
	outer.add_child(_box)
	outer.add_child(HSeparator.new())
	outer.add_child(UpdateCheckRow.new(updater, labels))
	var close := Button.new()
	close.text = labels.t("Close")
	close.size_flags_horizontal = Control.SIZE_SHRINK_END
	close.pressed.connect(hide)
	outer.add_child(close)
	updater.changed.connect(_rebuild)
	_rebuild()


func _rebuild() -> void:
	for c in _box.get_children():
		_box.remove_child(c)
		c.queue_free()
	_heading("agent-town")
	var app: Variant = updater.app_update()
	if updater.store_build:
		_line(labels.t("You have %@.", [updater.app_version]) + " " + labels.t("The Microsoft Store keeps agent-town up to date."))
	elif app != null:
		_line(labels.t("agent-town %@ is available", [app["version"]]), true)
		_line(labels.t("You have %@.", [updater.app_version]))
		if str(app["notes"]) != "":
			var notes := RichTextLabel.new()
			notes.text = app["notes"]
			notes.selection_enabled = true
			notes.custom_minimum_size = Vector2(500, 100)
			_box.add_child(notes)
		var link := LinkButton.new()
		link.text = labels.t("View release")
		link.pressed.connect(func() -> void: OS.shell_open(app["page"]))
		_box.add_child(link)
		var download := Button.new()
		download.text = labels.t("Download")
		download.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		download.pressed.connect(func() -> void: OS.shell_open(app["download"] if app["download"] != "" else app["page"]))
		_box.add_child(download)
		_line(labels.t("Run the downloaded installer: it replaces the installed agent-town."))
	elif updater.app_checked:
		_line(labels.t("agent-town %@ is up to date.", [updater.app_version]))
	else:
		_line(labels.t("You have %@.", [updater.app_version]) + " " + labels.t("Not checked yet."))
	_box.add_child(HSeparator.new())
	_heading("town-link")
	var plugin := updater.plugin_update()
	if plugin != "":
		_line(labels.t("town-link %@ is available", [plugin]), true)
		_line(labels.t("These sessions use an older town-link:"))
		for g in _groups():
			_line("• " + g)
		for cmd in Updater.PLUGIN_COMMANDS:
			_command(cmd)
		_line(labels.t("Then restart those Claude Code sessions: a session keeps the town-link it started with."))
	elif updater.newest_plugin != "":
		_line(labels.t("town-link %@ is the newest. No open session uses an older one.", [updater.newest_plugin]))
	else:
		_line(labels.t("Not checked yet."))
	_fit.call_deferred()


## As big as the content, kept centered where it was.
func _fit() -> void:
	var center := position + size / 2
	size = Vector2i(_margin.get_combined_minimum_size())
	if visible:
		position = center - size / 2


## One line per project and version: "agent-town: 1.0.2 or older (2 sessions)".
func _groups() -> Array[String]:
	var counts: Dictionary = {}
	var order: Array[String] = []
	for s: Dictionary in updater.outdated:
		var v: String = s["version"]
		var line := "%s: %s" % [s["project"], v if v != "" else labels.t("1.0.2 or older")]
		if not counts.has(line):
			order.append(line)
		counts[line] = int(counts.get(line, 0)) + 1
	var out: Array[String] = []
	for line in order:
		out.append(line + " " + labels.t("(%lld sessions)", [counts[line]]) if int(counts[line]) > 1 else line)
	return out


func _heading(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 16)
	_box.add_child(l)


func _line(text: String, bold: bool = false) -> void:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(500, 0)
	if bold:
		l.add_theme_color_override("font_color", Color.WHITE)
		l.add_theme_font_size_override("font_size", 15)
	_box.add_child(l)


## A command to run, with a Copy button.
func _command(cmd: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var field := LineEdit.new()
	field.text = cmd
	field.editable = false
	field.add_theme_color_override("font_uneditable_color", Color(0.92, 0.92, 0.92))
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(field)
	var copy := Button.new()
	copy.text = labels.t("Copy")
	copy.pressed.connect(func() -> void:
		DisplayServer.clipboard_set(cmd)
		copy.text = labels.t("Copied"))
	row.add_child(copy)
	_box.add_child(row)
