extends TestSupport
## The update notices' reading of GitHub's answers (UpdatesTests.swift on the Mac).

const RELEASES := """[
  {"tag_name":"v9.0.0","draft":false,"prerelease":false,"body":"mac","html_url":"https://x/m","assets":[]},
  {"tag_name":"windows-v1.1.0","draft":true,"prerelease":false,"body":"draft","html_url":"https://x/d","assets":[]},
  {"tag_name":"windows-v0.2.12","draft":false,"prerelease":true,"body":"pre","html_url":"https://x/p","assets":[]},
  {"tag_name":"windows-v0.2.10","draft":false,"prerelease":false,"body":"ten","html_url":"https://x/10",
   "assets":[{"name":"agent-town-setup-0.2.10.exe","browser_download_url":"https://x/10.exe"}]},
  {"tag_name":"windows-v0.2.9","draft":false,"prerelease":false,"body":"nine","html_url":"https://x/9","assets":[]}
]"""


func test_versions_compare_number_by_number() -> void:
	check_eq(UpdateFeed.compare(UpdateFeed.parse_version("1.0.9"), UpdateFeed.parse_version("1.0.10")), -1, "1.0.9 < 1.0.10")
	check_eq(UpdateFeed.compare(UpdateFeed.parse_version("1.0"), UpdateFeed.parse_version("1.0.0")), 0, "1.0 == 1.0.0")
	check_eq(UpdateFeed.compare(UpdateFeed.parse_version("2.0.0"), UpdateFeed.parse_version("1.9.9")), 1, "2.0.0 > 1.9.9")
	for bad: String in ["1.0.x", "", "1..0", "1.-1", "+1.0"]:
		check_eq(UpdateFeed.parse_version(bad), null, "not a version: " + bad)


func test_newest_windows_release_skips_mac_drafts_and_pre_releases() -> void:
	var r: Variant = UpdateFeed.newest_release(RELEASES)
	check(r != null, "found one")
	check_eq([r["version"], r["notes"], r["download"]], ["0.2.10", "ten", "https://x/10.exe"], "windows-v0.2.10")
	var m: Variant = UpdateFeed.newest_release(RELEASES, "v", ".dmg")
	check_eq([m["version"], m["download"]], ["9.0.0", ""], "the Mac's tag prefix")


func test_bad_answers_give_nothing() -> void:
	check_eq(UpdateFeed.newest_release("{\"message\":\"rate limited\"}"), null, "rate limited")
	check_eq(UpdateFeed.plugin_version("{\"version\":\"1.0.3\"}"), "1.0.3", "manifest")
	check_eq(UpdateFeed.plugin_version("not json"), "", "not json")
	check_eq([UpdateFeed.is_release_list("[]"), UpdateFeed.is_release_list("{\"message\":\"x\"}")], [true, false], "a release list")
	check_eq(UpdateFeed.newest_release("[]"), null, "no Windows release yet")


func test_a_session_without_a_version_is_older() -> void:
	check_eq(UpdateFeed.is_older("", "1.0.3"), true, "no version")
	check_eq(UpdateFeed.is_older("1.0.2", "1.0.3"), true, "older")
	check_eq(UpdateFeed.is_older("1.0.3", "1.0.3"), false, "same")
	check_eq(UpdateFeed.is_older("1.0.4", "1.0.3"), false, "newer")
	check_eq(UpdateFeed.is_older("1.0.2", "garbage"), false, "newest not a version")
