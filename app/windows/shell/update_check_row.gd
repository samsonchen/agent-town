class_name UpdateCheckRow
extends HBoxContainer
## When the last update check ran, with Check now. Used in the Updates window and in Settings.
## Port of `CheckRow` in app/macos/Sources/AgentTown/Updates.swift.

var updater: Updater
var labels: TownLabels
## In Settings: when Check now finds an update, open the Updates window (nothing if none, or if the
## check failed). The Updates window's own row and the automatic checks don't.
var opens_updates_window := false
var _status := Label.new()
var _button := Button.new()


func _init(p_updater: Updater, p_labels: TownLabels, p_opens_updates_window := false) -> void:
	updater = p_updater
	labels = p_labels
	opens_updates_window = p_opens_updates_window
	add_theme_constant_override("separation", 10)
	_status.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_status)
	_button.text = labels.t("Check now")
	_button.pressed.connect(check_now)
	add_child(_button)
	updater.changed.connect(_update)
	_update()


## Check now, pressed.
func check_now() -> void:
	await updater.check()
	if opens_updates_window and updater.has_update():
		updater.show_window()


func _update() -> void:
	_button.disabled = updater.checking
	if updater.checking:
		_status.text = labels.t("Checking…")
	elif updater.last_check_failed:
		_status.text = labels.t("The last check failed. It will try again later.")
	elif updater.settings.last_update_check > 0:
		_status.text = labels.t("Last checked: %@", [Updater.format_time(updater.settings.last_update_check)])
	else:
		_status.text = labels.t("Not checked yet.")
