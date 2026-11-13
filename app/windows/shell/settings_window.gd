class_name SettingsWindow
extends Window
## Settings: Open at login, the language, the office window (opacity, idle blocks, tips), and the
## sounds (spec: sound settings). Port of `SettingsView` in app/macos/Sources/AgentTown/Preferences.swift.

signal opacity_changed(value: float)
signal sounds_changed
signal office_changed ## Hide idle project blocks, Hide after, or Show tips

const SOUND_TITLES := {"dispatch": "Ticket dispatched", "completion": "Work done", "approval": "Approval needed"}

var settings: TownSettings
var updater: Updater ## set before the window enters the tree, for Settings → Updates
var labels: TownLabels
var audio: TownAudio
var _media: Array[String] = []
var _file_dialog: FileDialog
var _file_for := "" ## the sound whose file is being chosen
var _picks: Dictionary = {} ## sound -> its OptionButton
var _restart_row: HBoxContainer
var _login_note: Label
var _percent: Label
var _tips: CheckBox


func _init(p_settings: TownSettings, p_labels: TownLabels, p_audio: TownAudio) -> void:
	settings = p_settings
	labels = p_labels
	audio = p_audio
	title = labels.t("Settings")
	transient = true
	exclusive = false
	unresizable = true
	theme = ui_theme()
	close_requested.connect(hide)
	# Closing a tip in the office window turns Show tips off: show the current value.
	about_to_popup.connect(func() -> void:
		if _tips != null:
			_tips.set_pressed_no_signal(settings.show_tips))


func _ready() -> void:
	var margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	margin.add_child(box)

	# Open at login. A Store copy's is the package's startup task, which Windows Settings turns on.
	if Distribution.is_store():
		var startup := Button.new()
		startup.text = labels.t("Open at login…")
		startup.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		startup.pressed.connect(func() -> void: OS.shell_open(Distribution.STARTUP_SETTINGS))
		box.add_child(startup)
		var startup_note := Label.new()
		startup_note.add_theme_color_override("font_color", Color(0.45, 0.45, 0.45))
		startup_note.text = labels.t("Turn agent-town on in Windows Settings → Apps → Startup.")
		box.add_child(startup_note)
	var login := CheckBox.new()
	login.visible = not Distribution.is_store()
	login.text = labels.t("Open at login")
	login.disabled = not LoginItem.is_available()
	login.button_pressed = LoginItem.is_on()
	box.add_child(login)
	_login_note = Label.new()
	_login_note.add_theme_color_override("font_color", Color(0.45, 0.45, 0.45))
	_login_note.text = "" if LoginItem.is_available() or Distribution.is_store() else labels.t("Available in the installed app only.")
	_login_note.visible = not Distribution.is_store()
	box.add_child(_login_note)
	login.toggled.connect(func(on: bool) -> void:
		var err := LoginItem.set_on(on)
		_login_note.text = "" if err == "" else labels.t("Windows did not allow it: %@", [err])
		login.set_pressed_no_signal(LoginItem.is_on()))

	# Language: applies after a restart.
	var lang_row := HBoxContainer.new()
	lang_row.add_theme_constant_override("separation", 10)
	var lang_label := Label.new()
	lang_label.text = labels.t("Language")
	lang_row.add_child(lang_label)
	var lang := OptionButton.new()
	var choices: Array[String] = ["", "en", "zh-Hant"]
	lang.add_item(labels.t("System (Windows setting)"))
	lang.add_item("English")
	lang.add_item("繁體中文")
	lang.selected = maxi(0, choices.find(settings.language))
	lang_row.add_child(lang)
	box.add_child(lang_row)
	_restart_row = HBoxContainer.new()
	_restart_row.add_theme_constant_override("separation", 10)
	var note := Label.new()
	note.text = labels.t("Restart agent-town to use the new language.")
	_restart_row.add_child(note)
	var restart := Button.new()
	restart.text = labels.t("Restart now")
	restart.pressed.connect(_restart)
	_restart_row.add_child(restart)
	box.add_child(_restart_row)
	lang.item_selected.connect(func(i: int) -> void:
		settings.language = choices[i]
		settings.save()
		_update_restart())
	_update_restart()

	# Opacity: 10% to 100%, live while dragging.
	var op_row := HBoxContainer.new()
	op_row.add_theme_constant_override("separation", 10)
	var op_label := Label.new()
	op_label.text = labels.t("Opacity")
	op_row.add_child(op_label)
	var slider := HSlider.new()
	slider.min_value = TownSettings.OPACITY_MIN
	slider.max_value = TownSettings.OPACITY_MAX
	slider.step = 0.01
	slider.value = settings.opacity
	slider.custom_minimum_size = Vector2(200, 0)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	op_row.add_child(slider)
	_percent = Label.new()
	_percent.custom_minimum_size = Vector2(48, 0)
	op_row.add_child(_percent)
	box.add_child(op_row)
	slider.value_changed.connect(func(v: float) -> void:
		settings.opacity = TownSettings.clamp_opacity(v)
		_percent.text = "%d%%" % roundi(settings.opacity * 100.0)
		opacity_changed.emit(settings.opacity))
	slider.drag_ended.connect(func(_changed: bool) -> void: settings.save())
	_percent.text = "%d%%" % roundi(settings.opacity * 100.0)

	_build_office(box)
	_build_sounds(box)
	_build_updates(box)

	var close := Button.new()
	close.text = labels.t("Close")
	close.size_flags_horizontal = Control.SIZE_SHRINK_END
	close.pressed.connect(hide)
	box.add_child(close)
	size = Vector2i(margin.get_combined_minimum_size()) + Vector2i(40, 10)


# --- Office -------------------------------------------------------------------------------

## Hide idle project blocks, with Hide after N seconds beside it, and Show tips (spec: settings).
func _build_office(box: VBoxContainer) -> void:
	box.add_child(HSeparator.new())
	var heading := Label.new()
	heading.text = labels.t("Office")
	heading.add_theme_font_size_override("font_size", 16)
	box.add_child(heading)
	# Compact view: the scale is set when the window is made, so a change needs a restart.
	var compact := CheckBox.new()
	compact.text = labels.t("Compact view")
	compact.button_pressed = settings.compact_view
	box.add_child(compact)
	var restart_row := HBoxContainer.new()
	restart_row.add_theme_constant_override("separation", 10)
	var note := Label.new()
	note.text = labels.t("Restart agent-town to change the view.")
	restart_row.add_child(note)
	var restart := Button.new()
	restart.text = labels.t("Restart now")
	restart.pressed.connect(_restart)
	restart_row.add_child(restart)
	box.add_child(restart_row)
	restart_row.visible = settings.compact_view != ViewScale.compact
	compact.toggled.connect(func(on: bool) -> void:
		settings.compact_view = on
		settings.save()
		restart_row.visible = on != ViewScale.compact)
	var hide_idle := CheckBox.new()
	hide_idle.text = labels.t("Hide idle project blocks")
	hide_idle.button_pressed = settings.hide_idle_blocks
	box.add_child(hide_idle)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var before := Label.new()
	before.text = labels.t("Hide after")
	row.add_child(before)
	var secs := SpinBox.new()
	secs.min_value = TownSettings.IDLE_HIDE_MIN
	secs.max_value = TownSettings.IDLE_HIDE_MAX
	secs.step = 1
	secs.value = settings.idle_hide_seconds
	secs.editable = settings.hide_idle_blocks
	row.add_child(secs)
	var after := Label.new()
	after.text = labels.t("seconds")
	row.add_child(after)
	box.add_child(row)
	hide_idle.toggled.connect(func(on: bool) -> void:
		settings.hide_idle_blocks = on
		secs.editable = on
		settings.save()
		office_changed.emit())
	secs.value_changed.connect(func(v: float) -> void:
		settings.idle_hide_seconds = TownSettings.clamp_idle_hide(v)
		settings.save()
		office_changed.emit())
	_tips = CheckBox.new()
	_tips.text = labels.t("Show tips")
	_tips.button_pressed = settings.show_tips
	_tips.toggled.connect(func(on: bool) -> void:
		settings.show_tips = on
		settings.save()
		office_changed.emit())
	box.add_child(_tips)


# --- Updates ------------------------------------------------------------------------------

## Check for updates automatically, and when the last check ran, with Check now (spec: Updates).
func _build_updates(box: VBoxContainer) -> void:
	if updater == null:
		return
	box.add_child(HSeparator.new())
	var heading := Label.new()
	heading.text = labels.t("Updates")
	heading.add_theme_font_size_override("font_size", 16)
	box.add_child(heading)
	var auto := CheckBox.new()
	auto.text = labels.t("Check for updates automatically")
	auto.button_pressed = settings.check_updates
	auto.toggled.connect(func(on: bool) -> void:
		settings.check_updates = on
		settings.save())
	box.add_child(auto)
	if updater.store_build:
		var note := Label.new()
		note.add_theme_color_override("font_color", Color(0.45, 0.45, 0.45))
		note.text = labels.t("Checks for a newer town-link. The Microsoft Store updates agent-town.")
		box.add_child(note)
	box.add_child(UpdateCheckRow.new(updater, labels, true))


# --- Sounds -------------------------------------------------------------------------------

func _build_sounds(box: VBoxContainer) -> void:
	_media = TownAudio.media_names()
	box.add_child(HSeparator.new())
	var heading := Label.new()
	heading.text = labels.t("Sounds")
	heading.add_theme_font_size_override("font_size", 16)
	box.add_child(heading)

	# Volume: agent-town's own sounds, 0% to 100%.
	var vol_row := HBoxContainer.new()
	vol_row.add_theme_constant_override("separation", 10)
	var vol_label := Label.new()
	vol_label.text = labels.t("Volume")
	vol_row.add_child(vol_label)
	var vol := HSlider.new()
	vol.min_value = 0.0
	vol.max_value = 1.0
	vol.step = 0.01
	vol.value = settings.volume
	vol.custom_minimum_size = Vector2(200, 0)
	vol.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	vol_row.add_child(vol)
	var vol_pct := Label.new()
	vol_pct.custom_minimum_size = Vector2(48, 0)
	vol_pct.text = "%d%%" % roundi(settings.volume * 100.0)
	vol_row.add_child(vol_pct)
	box.add_child(vol_row)
	vol.value_changed.connect(func(v: float) -> void:
		settings.volume = TownSettings.clamp_volume(v)
		vol_pct.text = "%d%%" % roundi(settings.volume * 100.0)
		sounds_changed.emit())
	vol.drag_ended.connect(func(_changed: bool) -> void: settings.save())

	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 8)
	box.add_child(grid)
	for key: String in TownSettings.SOUNDS:
		var on := CheckBox.new()
		on.text = labels.t(SOUND_TITLES[key])
		on.button_pressed = settings.sound_on[key]
		on.toggled.connect(func(v: bool) -> void:
			settings.sound_on[key] = v
			settings.save()
			sounds_changed.emit())
		grid.add_child(on)
		var pick := OptionButton.new()
		pick.custom_minimum_size = Vector2(260, 0)
		pick.fit_to_longest_item = false
		_picks[key] = pick
		_fill_choices(pick, key)
		pick.item_selected.connect(func(i: int) -> void: _choice_picked(pick, key, i))
		grid.add_child(pick)
		var play := Button.new()
		play.text = labels.t("Play")
		play.pressed.connect(func() -> void: audio.preview(key))
		grid.add_child(play)
		if key == "completion":
			# The completion threshold, under its row.
			grid.add_child(Control.new())
			var th_row := HBoxContainer.new()
			th_row.add_theme_constant_override("separation", 6)
			var before := Label.new()
			before.text = labels.t("Only when a task takes at least")
			th_row.add_child(before)
			var th := SpinBox.new()
			th.min_value = 0
			th.max_value = TownSettings.THRESHOLD_MAX
			th.step = 1
			th.value = settings.completion_threshold
			th.value_changed.connect(func(v: float) -> void:
				settings.completion_threshold = TownSettings.clamp_threshold(v)
				settings.save()
				sounds_changed.emit())
			th_row.add_child(th)
			var after := Label.new()
			after.text = labels.t("seconds (0: every task)")
			th_row.add_child(after)
			grid.add_child(th_row)
			grid.add_child(Control.new())

	_file_dialog = FileDialog.new()
	_file_dialog.use_native_dialog = true
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_file_dialog.filters = PackedStringArray(["*.wav, *.mp3, *.ogg ; " + labels.t("Sound files")])
	_file_dialog.file_selected.connect(_file_chosen)
	add_child(_file_dialog)


## The list for one sound: the default first and marked, every other sound in C:\Windows\Media,
## the user's own file when one is chosen, then "Choose a file…". Item metadata is the choice.
func _fill_choices(pick: OptionButton, key: String) -> void:
	pick.clear()
	var default_name: String = TownAudio.DEFAULTS[key]
	pick.add_item(labels.t("%@ (default)", [default_name]))
	pick.set_item_metadata(0, "")
	for name in _media:
		if name == default_name:
			continue
		pick.add_item(name)
		pick.set_item_metadata(pick.item_count - 1, "media:" + name)
	var choice: String = settings.sound_choice[key]
	if choice.begins_with("file:"):
		pick.add_separator()
		pick.add_item(choice.substr(5).get_file())
		pick.set_item_metadata(pick.item_count - 1, choice)
	pick.add_separator()
	pick.add_item(labels.t("Choose a file…"))
	pick.set_item_metadata(pick.item_count - 1, "choose")
	pick.selected = 0
	for i in pick.item_count:
		if pick.get_item_metadata(i) == choice:
			pick.selected = i


func _choice_picked(pick: OptionButton, key: String, i: int) -> void:
	var meta: Variant = pick.get_item_metadata(i)
	if meta == "choose":
		_file_for = key
		_fill_choices(pick, key) # back to the current choice until a file is picked
		_file_dialog.popup_centered_ratio(0.6)
		return
	settings.sound_choice[key] = str(meta)
	settings.save()
	sounds_changed.emit()
	audio.preview(key)


func _file_chosen(path: String) -> void:
	if _file_for == "" or TownAudio.load_stream(path) == null:
		return
	settings.sound_choice[_file_for] = "file:" + path
	settings.save()
	sounds_changed.emit()
	audio.preview(_file_for)
	_fill_choices(_picks[_file_for], _file_for)


## Restart now (language, compact view): the app's Quit, then a new run with the same arguments.
signal restart_requested


func _restart() -> void:
	restart_requested.emit()


## The "Restart now" row shows only when the choice differs from the language the app runs in.
func _update_restart() -> void:
	var wanted := settings.language if settings.language != "" else TownLabels.language_for_locale(OS.get_locale())
	_restart_row.visible = wanted != labels.language


## The look of the app's own windows: the Windows UI font, with Microsoft JhengHei UI for Chinese.
static func ui_theme() -> Theme:
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Segoe UI", "Microsoft JhengHei UI", "Microsoft JhengHei"])
	var t := Theme.new()
	t.default_font = font
	t.default_font_size = 14
	return t
