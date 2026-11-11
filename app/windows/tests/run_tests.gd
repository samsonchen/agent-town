extends SceneTree
## Headless test runner: runs every `test_*` method of every script in res://tests/ named `*_tests.gd`.
## Run from the repo root:
##   godot --headless --path app/windows --script res://tests/run_tests.gd
## Exits with 0 when all pass, 1 otherwise.

func _init() -> void:
	var failed := 0
	var passed := 0
	var dir := DirAccess.open("res://tests")
	var files := Array(dir.get_files()).filter(func(f: String) -> bool: return f.ends_with("_tests.gd") and f != "run_tests.gd")
	files.sort()
	for f: String in files:
		var suite: Object = (load("res://tests/" + f) as GDScript).new()
		var names: Array = []
		for m: Dictionary in suite.get_method_list():
			if (m["name"] as String).begins_with("test_"):
				names.append(m["name"])
		names.sort()
		for n: String in names:
			suite.set("failures", PackedStringArray())
			suite.call(n)
			var failures: PackedStringArray = suite.get("failures")
			if failures.is_empty():
				passed += 1
				print("  ok    ", f.get_basename(), ".", n)
			else:
				failed += 1
				print("  FAIL  ", f.get_basename(), ".", n)
				for line: String in failures:
					print("        ", line)
	print("%d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)
