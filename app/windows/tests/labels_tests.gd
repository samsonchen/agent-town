extends TestSupport
## The language rule, UI string lookup and formatting, and the layout math.

func test_language_follows_the_windows_locale_by_the_spec_rule() -> void:
	for loc: String in ["zh_TW", "zh-TW", "zh_HK", "zh_MO", "zh_Hant", "zh_Hant_TW", "ZH_tw"]:
		check_eq(TownLabels.language_for_locale(loc), "zh-Hant", loc)
	for loc: String in ["zh_CN", "zh_SG", "zh_Hans", "zh_Hans_CN", "zh", "en_US", "ja_JP", ""]:
		check_eq(TownLabels.language_for_locale(loc), "en", loc)


func test_strings_files_parse() -> void:
	var d := TownLabels.parse_strings('/* a comment */\n"Desk %lld" = "%lld 號桌";\n"Say \\"hi\\"" = "說「嗨」";\n')
	check_eq(d, {"Desk %lld": "%lld 號桌", "Say \"hi\"": "說「嗨」"}, "parsed")


func test_traditional_chinese_strings_load_and_format() -> void:
	var zh := TownLabels.new("zh-Hant")
	check_eq(zh.chief_of_staff(), "幕僚長", "a plain string")
	check_eq(zh.desk(2), "2 號桌", "a number")
	check_eq(zh.t("Notes tidied: %@ → %@ tokens", ["152k", "20k"]), "筆記整理完成：152k → 20k tokens", "reordered arguments")
	check_eq(zh.role("typescript-engineer"), "TypeScript 工程師", "a role label from the catalog")
	var en := TownLabels.new("en")
	check_eq(en.desk(2), "Desk 2", "English keeps the key")
	check_eq(en.t("Not translated anywhere"), "Not translated anywhere", "a missing key shows the English")


func test_display_width_counts_cjk_as_two() -> void:
	check_eq(TownLabels.display_width("agent-town"), 10, "Latin")
	check_eq(TownLabels.display_width("修復音效"), 8, "CJK")


func test_context_line() -> void:
	var en := TownLabels.new("en")
	var c := Building.ContextUsage.new()
	check_eq(en.context_line(c), "Context —", "nothing known")
	c.window = 200_000
	check_eq(en.context_line(c), "200K context", "window only")
	c.tokens = 131_000
	c.percent = 66
	c.last_turn_tokens = 12_300
	check_eq(en.context_line(c), "131k / 200K (66%) · last turn 12.3k", "everything")


func test_layout_matches_the_mac() -> void:
	check_eq(Layout.office_size(1), Vector2(8.8, 3.6), "executive block alone")
	check_eq(Layout.block_origin(2), Vector2(0.9, 0.9 + 1.8 + 1.4 + 5.4 + 1.4), "second project block")
	check_eq(Layout.route(Vector2(1.1, 0.55), Vector2(2.3, 1.95)),
		[Vector2(1.7, 0.55), Vector2(1.7, 1.6), Vector2(2.3, 1.6), Vector2(2.3, 1.95)], "walks along the walkways, crossing between desks")


func test_sofa_seats_are_reached_around_the_sofa() -> void:
	check(Layout.is_seat(Vector2(5.2, 3.72)) and Layout.is_seat(Vector2(5.6, 3.72)), "both cushions are seats")
	check(not Layout.is_seat(Vector2(4.4, 4.45)), "a standing spot is not")
	check_eq(Layout.route(Vector2(4.0, 2.95), Vector2(5.6, 3.72)),
		[Vector2(5.98, 2.95), Vector2(5.98, 3.95), Vector2(5.6, 3.95), Vector2(5.6, 3.72)],
		"to the right seat: down beside the sofa, across in front of it, onto the seat")
	check_eq(Layout.route(Vector2(5.2, 3.72), Vector2(1.0, 2.95)),
		[Vector2(5.2, 3.95), Vector2(4.82, 3.95), Vector2(4.82, 2.95), Vector2(1.0, 2.95)],
		"from the left seat: out to the front, around the left side, then the walkway")


func test_leaving_from_another_walkway_crosses_at_the_left_side_lane() -> void:
	# A Chief of Staff carrying a desk out: from the back walkway to the path on the left.
	check_eq(Layout.route(Vector2(2.3, 0.55), Layout.WORKER_ENTRANCE),
		[Vector2(0.3, 0.55), Vector2(0.3, 2.95), Layout.WORKER_ENTRANCE], "down the left side lane, then out")


func test_clip_width_counts_cjk_as_two() -> void:
	check_eq(TownLabels.clip_width("short", 40), "short", "fits")
	check_eq(TownLabels.clip_width("abcdefghij", 5), "abcd…", "cut")
	check_eq(TownLabels.clip_width("測試測試測試", 7), "測試測…", "wide characters")
