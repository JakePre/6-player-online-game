extends GutTest
## Windows server dashboard (#145 part 1): UI wrapper around ServerHost —
## tested with autostart off so no real port is bound.

var dashboard: ServerDashboard


func before_each() -> void:
	var scene: PackedScene = load("res://src/server/server_dashboard.tscn")
	dashboard = scene.instantiate()
	dashboard.autostart = false
	add_child_autofree(dashboard)


func test_shows_not_running_without_a_server() -> void:
	var label: Label = dashboard.get_node("%StatusLabel")
	assert_string_contains(label.text, "NOT RUNNING")


func test_autostart_off_spawns_no_server_host() -> void:
	assert_false(dashboard.has_node("ServerHost"))


func test_log_lines_append_and_stay_bounded() -> void:
	for i in ServerDashboard.MAX_LOG_LINES + 20:
		dashboard.log_line("event %d" % i)
	var log: RichTextLabel = dashboard.get_node("%Log")
	assert_lte(log.get_paragraph_count(), ServerDashboard.MAX_LOG_LINES + 1)
	assert_string_contains(log.get_parsed_text(), "event %d" % (ServerDashboard.MAX_LOG_LINES + 19))
