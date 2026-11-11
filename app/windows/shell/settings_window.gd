class_name SettingsWindow
extends Window
## Settings: Open at login, the language, and the office window's opacity.
## Port of `SettingsView` in app/macos/Sources/AgentTown/Preferences.swift.

signal opacity_changed(value: float)

var settings: TownSettings
var labels: TownLabels
var _restart_row: HBoxContainer
var _login_note: Label
var _percent: Label


func _init(p_settings: TownSettings, p_labels: TownLabels) -> void:
	settings = p_settings
	labels = p_labels
	title = labels.t("Settings")
	transient = true
	exclusive = false
	unresizable = true
	theme = ui_theme()
	close_requested.connect(hide)


func _ready() -> void:
	var margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	margin.add_child(box)

	# Open at login.
	var login := CheckBox.new()
	login.text = labels.t("Open at login")
	login.disabled = not LoginItem.is_available()
	login.button_pressed = LoginItem.is_on()
	box.add_child(login)
	_login_note = Label.new()
	_login_note.add_theme_color_override("font_color", Color(0.45, 0.45, 0.45))
	_login_note.text = "" if LoginItem.is_available() else labels.t("Available in the installed app only.")
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
	restart.pressed.connect(func() -> void:
		OS.set_restart_on_exit(true, OS.get_cmdline_args())
		get_tree().quit())
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

	var close := Button.new()
	close.text = labels.t("Close")
	close.size_flags_horizontal = Control.SIZE_SHRINK_END
	close.pressed.connect(hide)
	box.add_child(close)
	size = Vector2i(margin.get_combined_minimum_size()) + Vector2i(40, 10)


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
