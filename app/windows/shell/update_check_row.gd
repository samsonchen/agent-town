class_name UpdateCheckRow
extends HBoxContainer
## When the last update check ran, with Check now. Used in the Updates window and in Settings.
## Port of `CheckRow` in app/macos/Sources/AgentTown/Updates.swift.

var updater: Updater
var labels: TownLabels
var _status := Label.new()
var _button := Button.new()


func _init(p_updater: Updater, p_labels: TownLabels) -> void:
	updater = p_updater
	labels = p_labels
	add_theme_constant_override("separation", 10)
	_status.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_status)
	_button.text = labels.t("Check now")
	_button.pressed.connect(func() -> void: updater.check())
	add_child(_button)
	updater.changed.connect(_update)
	_update()


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
