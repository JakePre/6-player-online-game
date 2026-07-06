extends GutTest
## Diagnostics log (M18-06): the leveled JSONL trail — pure line format, the
## level gate, inert-until-configured, file writing/flush, and rotation.

const DIR := "user://logs"


func after_each() -> void:
	DiagnosticsLog._close()
	_wipe_logs()


func _wipe_logs() -> void:
	var dir := DirAccess.open(DIR)
	if dir == null:
		return
	for name in dir.get_files():
		dir.remove(name)


func _read(path: String) -> Array:
	var lines: Array = []
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return lines
	while not f.eof_reached():
		var line := f.get_line()
		if not line.is_empty():
			lines.append(JSON.parse_string(line))
	return lines


func test_format_line_has_required_keys_and_flat_fields() -> void:
	var line := DiagnosticsLog.format_line(
		1751780421.317, 42.1, DiagnosticsLog.Level.WARN, &"tick", &"overrun", {"ms": 41.0}
	)
	var obj: Dictionary = JSON.parse_string(line)
	assert_eq(obj.lvl, "WARN")
	assert_eq(obj.cat, "tick")
	assert_eq(obj.ev, "overrun")
	assert_almost_eq(float(obj.up), 42.1, 0.001)
	assert_almost_eq(float(obj.ms), 41.0, 0.001, "custom fields ride along")


func test_a_field_cannot_clobber_a_required_key() -> void:
	var line := DiagnosticsLog.format_line(
		1.0, 2.0, DiagnosticsLog.Level.INFO, &"x", &"y", {"ev": "SPOOFED", "cat": "SPOOFED"}
	)
	var obj: Dictionary = JSON.parse_string(line)
	assert_eq(obj.ev, "y", "the real event wins")
	assert_eq(obj.cat, "x")


func test_inert_until_configured() -> void:
	assert_false(DiagnosticsLog.is_active(), "does nothing before configure()")
	DiagnosticsLog.event(&"net", &"noop")  # must not crash or write
	assert_eq(DiagnosticsLog.current_path(), "")


func test_configure_writes_a_leveled_jsonl_file() -> void:
	DiagnosticsLog.configure("test", DiagnosticsLog.Level.INFO, "fixed")
	assert_true(DiagnosticsLog.is_active())
	DiagnosticsLog.event(&"room", &"create", {"room": "ABCDEF"})
	DiagnosticsLog.flush()
	var lines := _read(DiagnosticsLog.current_path())
	# log_start + create.
	assert_eq(lines.size(), 2)
	assert_eq(lines[1].ev, "create")
	assert_eq(lines[1].room, "ABCDEF")


func test_level_gate_drops_below_threshold() -> void:
	DiagnosticsLog.configure("test", DiagnosticsLog.Level.WARN, "fixed")
	DiagnosticsLog.event(&"x", &"info_line")  # INFO < WARN, dropped
	DiagnosticsLog.debug(&"x", &"debug_line")  # dropped
	DiagnosticsLog.warn(&"x", &"warn_line")  # kept
	DiagnosticsLog.flush()
	var lines := _read(DiagnosticsLog.current_path())
	var events := lines.map(func(o: Dictionary) -> String: return String(o.ev))
	assert_true("warn_line" in events)
	assert_false("info_line" in events, "INFO is below the WARN threshold")


func test_errors_flush_immediately() -> void:
	DiagnosticsLog.configure("test", DiagnosticsLog.Level.INFO, "fixed")
	DiagnosticsLog.error(&"err", &"boom", {"why": "test"})
	# No explicit flush(): error() flushes itself so the line survives a crash.
	var lines := _read(DiagnosticsLog.current_path())
	var events := lines.map(func(o: Dictionary) -> String: return String(o.ev))
	assert_true("boom" in events, "the error line is already on disk")


func test_prune_keeps_only_the_newest_files() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	# Seed more than the cap with sortable timestamped names.
	for i in DiagnosticsLog.MAX_FILES + 3:
		var f := FileAccess.open("%s/server-2026010%d.log" % [DIR, i], FileAccess.WRITE)
		f.store_line("x")
		f.close()
	DiagnosticsLog._prune_old_files()
	var dir := DirAccess.open(DIR)
	var remaining := 0
	for name in dir.get_files():
		if name.ends_with(".log"):
			remaining += 1
	# _prune keeps MAX_FILES-1 to leave room for the one about to open.
	assert_lte(remaining, DiagnosticsLog.MAX_FILES, "old logs are pruned")
