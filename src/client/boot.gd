extends Node
## Main-scene entry point for every launch mode of the single codebase:
##   dedicated server : export feature "dedicated_server" or `-- --server`
##   soak-test bot    : `-- --bot ...` (see tests/soak/)
##   normal client    : anything else

const SERVER_HOST_SCRIPT := "res://src/server/server_host.gd"
const BOT_SCRIPT := "res://tests/soak/bot_client.gd"
const DEV_MENU_SCRIPT := "res://src/client/dev_menu.gd"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if OS.has_feature("dedicated_server") or args.has("--server"):
		_spawn(SERVER_HOST_SCRIPT, "ServerHost")
	elif args.has("--bot"):
		_spawn(BOT_SCRIPT, "BotClient")
	else:
		_spawn(DEV_MENU_SCRIPT, "DevMenu")


func _spawn(script_path: String, node_name: String) -> void:
	var node: Node = (load(script_path) as GDScript).new()
	node.name = node_name
	add_child(node)
