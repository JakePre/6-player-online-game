extends Node
## Diagnostics log (M18-06, see docs/DIAGNOSTICS.md): a leveled JSON-lines
## trail written to user://logs/<role>-<timestamp>.log for post-hoc analysis
## of live sessions — the server logs always, the client when opted in
## (M18-07). Autoload, but **inert until configure()** so tests and opted-out
## clients pay nothing.
##
## One JSON object per line: {t, up, lvl, cat, ev, ...fields}. Writes are
## buffered and flushed on a short timer (never on the 30 Hz tick), and
## immediately for ERROR and on exit, so the last lines before a crash survive.

enum Level { DEBUG, INFO, WARN, ERROR }

const LOG_DIR := "user://logs"
const FLUSH_INTERVAL_SEC := 1.0
## Keep the newest few logs; a long-lived server must not fill the disk.
const MAX_FILES := 10
const MAX_BYTES := 50 * 1024 * 1024

var _role := ""
var _min_level: Level = Level.INFO
var _file: FileAccess = null
var _buffer: PackedStringArray = []
var _bytes_written := 0
var _flush_accum := 0.0
var _start_usec := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)  # nothing to do until configured


## Starts logging as `role` ("server"/"client") at `min_level`. Idempotent-ish:
## a second call rotates to a fresh file. `stamp` lets callers pass a
## deterministic filename component (tests); production passes a timestamp.
func configure(role: String, min_level: Level = Level.INFO, stamp := "") -> void:
	_role = role
	_min_level = min_level
	_start_usec = Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(LOG_DIR)
	_prune_old_files()
	var name := "%s-%s.log" % [role, stamp if not stamp.is_empty() else _timestamp()]
	_file = FileAccess.open("%s/%s" % [LOG_DIR, name], FileAccess.WRITE)
	_bytes_written = 0
	_buffer.clear()
	set_process(true)
	event(&"app", &"log_start", {"role": role, "level": Level.keys()[min_level]})


func is_active() -> bool:
	return _file != null


## Public counterpart to configure(): flushes and closes the file. For the
## client's opt-in log (M18-07), turned off live when the setting flips off.
func stop() -> void:
	_close()


func current_path() -> String:
	return _file.get_path() if _file != null else ""


func event(cat: StringName, ev: StringName, fields := {}) -> void:
	_write(Level.INFO, cat, ev, fields)


func debug(cat: StringName, ev: StringName, fields := {}) -> void:
	_write(Level.DEBUG, cat, ev, fields)


func warn(cat: StringName, ev: StringName, fields := {}) -> void:
	_write(Level.WARN, cat, ev, fields)


func error(cat: StringName, ev: StringName, fields := {}) -> void:
	_write(Level.ERROR, cat, ev, fields)
	flush()  # errors hit disk immediately — they may be the last line


func _write(level: Level, cat: StringName, ev: StringName, fields: Dictionary) -> void:
	if _file == null or level < _min_level:
		return
	var uptime := float(Time.get_ticks_usec() - _start_usec) / 1_000_000.0
	var line := format_line(Time.get_unix_time_from_system(), uptime, level, cat, ev, fields)
	_buffer.append(line)
	_bytes_written += line.length() + 1


## Pure serializer: one flat JSON object, required keys first. Static so it is
## unit-tested without touching the filesystem.
static func format_line(
	unix_t: float, uptime: float, level: Level, cat: StringName, ev: StringName, fields: Dictionary
) -> String:
	var entry := {
		"t": snappedf(unix_t, 0.001),
		"up": snappedf(uptime, 0.001),
		"lvl": Level.keys()[level],
		"cat": String(cat),
		"ev": String(ev),
	}
	for key: String in fields:
		# Never let a field clobber a required key.
		if not entry.has(key):
			entry[key] = fields[key]
	return JSON.stringify(entry)


func _process(delta: float) -> void:
	_flush_accum += delta
	if _flush_accum >= FLUSH_INTERVAL_SEC:
		_flush_accum = 0.0
		flush()


## Drain the buffer to disk. Also rotates if the file has grown past the cap.
func flush() -> void:
	if _file == null or _buffer.is_empty():
		return
	for line in _buffer:
		_file.store_line(line)
	_buffer.clear()
	_file.flush()
	if _bytes_written >= MAX_BYTES:
		_rotate()


func _rotate() -> void:
	var role := _role
	var level := _min_level
	_close()
	configure(role, level)


func _close() -> void:
	if _file == null:
		return
	flush()
	_file.close()
	_file = null
	set_process(false)


## Newest-first by name (timestamped), delete everything past MAX_FILES so a
## new log always has room.
func _prune_old_files() -> void:
	var dir := DirAccess.open(LOG_DIR)
	if dir == null:
		return
	var logs: Array[String] = []
	for name in dir.get_files():
		if name.ends_with(".log"):
			logs.append(name)
	logs.sort()
	logs.reverse()
	for i in range(MAX_FILES - 1, logs.size()):
		dir.remove(logs[i])


func _timestamp() -> String:
	var now := Time.get_datetime_dict_from_system()
	return (
		"%04d%02d%02d-%02d%02d%02d"
		% [now.year, now.month, now.day, now.hour, now.minute, now.second]
	)


func _notification(what: int) -> void:
	# Flush the tail before the process goes away.
	if (
		what == NOTIFICATION_WM_CLOSE_REQUEST
		or what == NOTIFICATION_CRASH
		or what == NOTIFICATION_PREDELETE
		or what == NOTIFICATION_EXIT_TREE
	):
		if _file != null:
			event(&"app", &"log_stop", {})
			_close()
