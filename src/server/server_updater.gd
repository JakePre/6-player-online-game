class_name ServerUpdater
extends Node
## Dedicated-server self-update (#145): checks GitHub Releases for a newer
## server build on boot and every RECHECK_SEC, and logs loudly when one
## exists. Applying is operator opt-in — `--auto-update` or
## PARTY_RUSH_AUTO_UPDATE=1 — and even then the swap waits until no rooms
## are live before restarting. Container deployments should keep updating
## by pulling a new image; this targets bare-metal hosts.

const RECHECK_SEC := 6 * 3600.0
## How often a staged update re-checks whether the rooms have emptied.
const RETRY_APPLY_SEC := 300.0

var _checker: UpdateChecker
var _updater: Updater
var _auto_update := false
var _staged_version := ""


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_auto_update = (
		args.has("--auto-update") or OS.get_environment("PARTY_RUSH_AUTO_UPDATE") == "1"
	)
	_checker = UpdateChecker.new()
	_checker.asset_platform = "server"
	add_child(_checker)
	_checker.update_available.connect(_on_update_available)
	_checker.up_to_date.connect(
		func() -> void: print("[server] build v%s is current" % AppVersion.VERSION)
	)
	_checker.check_failed.connect(func() -> void: print("[server] update check failed"))
	_updater = Updater.new()
	add_child(_updater)
	_updater.staged.connect(_on_staged)
	_updater.failed.connect(
		func(reason: String) -> void: printerr("[server] update failed: %s" % reason)
	)
	_checker.check()
	var recheck := Timer.new()
	recheck.wait_time = RECHECK_SEC
	recheck.timeout.connect(_checker.check)
	add_child(recheck)
	recheck.start()


func _on_update_available(version: String, url: String) -> void:
	print("[server] UPDATE AVAILABLE v%s (running v%s)" % [version, AppVersion.VERSION])
	if not _auto_update:
		print("[server] pass --auto-update (or PARTY_RUSH_AUTO_UPDATE=1) to apply on restart")
		return
	if _staged_version == version:
		return
	print("[server] auto-update: downloading v%s" % version)
	_updater.download_and_stage(version, url)


func _on_staged(version: String) -> void:
	_staged_version = version
	print("[server] v%s staged" % version)
	_try_apply()


## Never restart out from under live rooms: apply immediately when idle,
## otherwise retry after the players have had time to finish.
func _try_apply() -> void:
	var manager: RoomManager = NetManager.room_manager
	if manager == null or manager.rooms.is_empty():
		print("[server] restarting to apply v%s" % _staged_version)
		_updater.apply_and_restart()
		return
	print(
		(
			"[server] update v%s waits for %d live room(s); retrying in %d s"
			% [_staged_version, manager.rooms.size(), int(RETRY_APPLY_SEC)]
		)
	)
	get_tree().create_timer(RETRY_APPLY_SEC).timeout.connect(_try_apply)
