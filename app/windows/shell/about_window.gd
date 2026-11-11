class_name AboutWindow
extends Window
## About agent-town: the version, the author, the license with a link, the repository, and the
## third-party components with their licenses. Port of app/macos/Sources/AgentTown/About.swift.

const REPOSITORY := "https://github.com/samsonchen/agent-town"
const CC0 := "https://creativecommons.org/publicdomain/zero/1.0/"
const OFL := "https://openfontlicense.org/open-font-license-official-text/"

var labels: TownLabels


func _init(p_labels: TownLabels) -> void:
	labels = p_labels
	title = labels.t("About agent-town")
	transient = true
	unresizable = true
	theme = SettingsWindow.ui_theme()
	close_requested.connect(hide)


func _ready() -> void:
	var margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	margin.add_child(box)
	var text := RichTextLabel.new()
	text.bbcode_enabled = true
	text.fit_content = true
	text.custom_minimum_size = Vector2(500, 0)
	text.meta_clicked.connect(func(meta: Variant) -> void: OS.shell_open(str(meta)))
	var version: String = ProjectSettings.get_setting("application/config/version", "0.0.0")
	var lines: Array[String] = [
		"[font_size=20][b]agent-town[/b][/font_size]",
		labels.t("Version %@", [version]),
		labels.t("Shows Claude Code's work as a small office."),
		labels.t("By Samson Chen"),
		"[url=%s]%s[/url]" % [REPOSITORY, REPOSITORY],
		"",
		"[b]%s[/b]" % labels.t("License"),
		_links(labels.t("agent-town is licensed under the [Apache License 2.0](https://www.apache.org/licenses/LICENSE-2.0).")),
		"",
		"[b]%s[/b]" % labels.t("Third-party components"),
		"Kenney Mini Characters, Kenney Furniture Kit — " + _links(labels.t("3D models, license: [%@](%@)", ["CC0 1.0", CC0])),
		labels.t("CC0 does not require credit; we credit Kenney (kenney.nl) anyway."),
		"Cubic 11 (俐方體11號) — " + _links(labels.t("Font, license: [%@](%@)", ["SIL OFL 1.1", OFL])),
	]
	text.text = "\n".join(lines)
	box.add_child(text)
	var close := Button.new()
	close.text = labels.t("Close")
	close.size_flags_horizontal = Control.SIZE_SHRINK_END
	close.pressed.connect(hide)
	box.add_child(close)
	size = Vector2i(margin.get_combined_minimum_size()) + Vector2i(40, 20)


## Markdown links "[text](url)", as the shared strings write them, as BBCode.
static func _links(s: String) -> String:
	var re := RegEx.create_from_string("\\[([^\\]]+)\\]\\(([^)]+)\\)")
	return re.sub(s, "[url=$2]$1[/url]", true)
