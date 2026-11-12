class_name UpdateFeed
extends RefCounted
## Reads what GitHub answers, for the update notices (docs/spec.md: Updates). Port of
## app/macos/Sources/TownCore/Updates.swift.

## The releases of the repository, newest first by GitHub's order.
const RELEASES_URL := "https://api.github.com/repos/samsonchen/agent-town/releases?per_page=50"
## town-link's manifest on `main`: what `claude plugin update` installs.
const PLUGIN_MANIFEST_URL := "https://raw.githubusercontent.com/samsonchen/agent-town/main/plugin/.claude-plugin/plugin.json"
## The Windows app's tags are windows-v<version>; the macOS app's are v<version>.
const TAG_PREFIX := "windows-v"
const DOWNLOAD_SUFFIX := ".exe"


## A version such as "1.0.10" as its numbers, or null for anything that is not dot-separated numbers.
static func parse_version(text: String) -> Variant:
	var pieces := text.split(".", true)
	if pieces.is_empty():
		return null
	var out: Array[int] = []
	for p in pieces:
		if p == "" or not p.is_valid_int() or not p.lstrip("0123456789").is_empty():
			return null
		out.append(int(p))
	return out


## -1, 0 or 1, comparing number by number ("1.0" equals "1.0.0").
static func compare(a: Array, b: Array) -> int:
	for i in maxi(a.size(), b.size()):
		var x: int = a[i] if i < a.size() else 0
		var y: int = b[i] if i < b.size() else 0
		if x != y:
			return -1 if x < y else 1
	return 0


## The highest-versioned release whose tag is `<prefix><version>`, skipping drafts and
## pre-releases, as {"version", "tag", "notes", "page", "download"} ("download" is "" when the
## release has no asset ending in `suffix`). GitHub's "Latest" flag is not used. Null for an answer
## that is not a list of releases.
static func newest_release(json_text: String, prefix: String = TAG_PREFIX, suffix: String = DOWNLOAD_SUFFIX) -> Variant:
	var j := JSON.new()
	if j.parse(json_text) != OK or typeof(j.data) != TYPE_ARRAY:
		return null
	var best: Variant = null
	var best_v: Array = []
	for r: Variant in j.data:
		if typeof(r) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = r
		var tag := str(d.get("tag_name", ""))
		if d.get("draft", false) == true or d.get("prerelease", false) == true or not tag.begins_with(prefix):
			continue
		var rest := tag.substr(prefix.length())
		var v: Variant = parse_version(rest)
		if not rest.contains(".") or v == null:
			continue
		if best != null and compare(best_v, v) >= 0:
			continue
		var download := ""
		var assets: Variant = d.get("assets", [])
		if typeof(assets) == TYPE_ARRAY:
			for a: Variant in assets:
				if typeof(a) == TYPE_DICTIONARY and str(a.get("name", "")).to_lower().ends_with(suffix.to_lower()):
					download = str(a.get("browser_download_url", ""))
					break
		var body: Variant = d.get("body", "")
		best = {"version": rest, "tag": tag, "notes": body if typeof(body) == TYPE_STRING else "",
			"page": str(d.get("html_url", "")), "download": download}
		best_v = v
	return best


## True when GitHub answered with a list of releases (which may hold no Windows release yet).
static func is_release_list(json_text: String) -> bool:
	var j := JSON.new()
	return j.parse(json_text) == OK and typeof(j.data) == TYPE_ARRAY


## The `version` in a plugin.json, if it is a version number; else "".
static func plugin_version(json_text: String) -> String:
	var j := JSON.new()
	if j.parse(json_text) != OK or typeof(j.data) != TYPE_DICTIONARY:
		return ""
	var v: Variant = (j.data as Dictionary).get("version")
	return v if typeof(v) == TYPE_STRING and parse_version(v) != null else ""


## Whether `running` is older than `newest`. A running version that isn't a version number ("":
## town-link 1.0.2 or older) counts as older.
static func is_older(running: String, newest: String) -> bool:
	var n: Variant = parse_version(newest)
	if n == null:
		return false
	var r: Variant = parse_version(running)
	return r == null or compare(r, n) < 0
