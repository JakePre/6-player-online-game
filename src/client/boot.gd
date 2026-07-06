extends Node
## Main-scene entry point for every launch mode of the single codebase:
##   dedicated server : export feature "dedicated_server" or `-- --server`
##   server dashboard : export feature "server_app" or `-- --server-ui` (#145)
##   soak-test bot    : `-- --bot ...` (see tests/soak/)
##   solo debug launch: `-- --debug-minigame=<id> ...` (dev iteration only;
##                       server must run --debug-rpcs, see debug_launcher.gd)
##   normal client    : anything else

const SERVER_HOST_SCRIPT := "res://src/server/server_host.gd"
const SERVER_DASHBOARD_SCENE := "res://src/server/server_dashboard.tscn"
const BOT_SCRIPT := "res://tests/soak/bot_client.gd"
const PLAYTEST_BOT_SCRIPT := "res://tests/soak/playtest_bot.gd"
const DEBUG_LAUNCHER_SCRIPT := "res://src/client/debug_launcher.gd"
const APP_SHELL_SCENE := "res://src/client/app_shell.tscn"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if OS.has_feature("server_app") or args.has("--server-ui"):
		# Windows Server preset (#145): the server with a status window.
		var dashboard: Node = (load(SERVER_DASHBOARD_SCENE) as PackedScene).instantiate()
		dashboard.name = "ServerDashboard"
		add_child(dashboard)
	elif OS.has_feature("dedicated_server") or args.has("--server"):
		_spawn(SERVER_HOST_SCRIPT, "ServerHost")
	elif args.has("--bot"):
		_spawn(BOT_SCRIPT, "BotClient")
	elif args.has("--playtest"):
		_spawn(PLAYTEST_BOT_SCRIPT, "PlaytestBot")
	else:
		# Widest possible pad coverage before any input is read (M17-01).
		ControllerDb.install()
		var shell: Node = (load(APP_SHELL_SCENE) as PackedScene).instantiate()
		shell.name = "AppShell"
		add_child(shell)
		if not NetManager._arg_value(args, "--debug-minigame", "").is_empty():
			_spawn(DEBUG_LAUNCHER_SCRIPT, "DebugLauncher")


func _spawn(script_path: String, node_name: String) -> void:
	var node: Node = (load(script_path) as GDScript).new()
	node.name = node_name
	add_child(node)
