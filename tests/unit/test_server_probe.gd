extends GutTest
## Server reachability probe (#607): the pure status + chip formatting behind
## the main menu's pre-connection indicator. The connect/ping orchestration
## lives in main_menu (network, not unit-tested by instantiation, like the
## update check); this covers everything that decides what the player sees.


func test_starts_checking() -> void:
	var probe := ServerProbe.new()
	assert_eq(probe.status, ServerProbe.Status.CHECKING)
	assert_eq(probe.rtt_ms, -1)


func test_marks_online_with_clamped_rtt() -> void:
	var probe := ServerProbe.new()
	probe.mark_online(34)
	assert_eq(probe.status, ServerProbe.Status.ONLINE)
	assert_eq(probe.rtt_ms, 34)
	probe.mark_online(-5)
	assert_eq(probe.rtt_ms, 0, "a nonsense negative rtt clamps to 0")


func test_marks_unreachable_clears_rtt() -> void:
	var probe := ServerProbe.new()
	probe.mark_online(20)
	probe.mark_unreachable()
	assert_eq(probe.status, ServerProbe.Status.UNREACHABLE)
	assert_eq(probe.rtt_ms, -1)


func test_chip_text_per_state_names_the_address() -> void:
	assert_eq(
		ServerProbe.chip_text(ServerProbe.Status.CHECKING, -1, "celestrum.com"),
		"Checking celestrum.com…"
	)
	assert_eq(
		ServerProbe.chip_text(ServerProbe.Status.ONLINE, 34, "celestrum.com"),
		"celestrum.com · online · 34 ms"
	)
	assert_string_contains(
		ServerProbe.chip_text(ServerProbe.Status.UNREACHABLE, -1, "celestrum.com"),
		"unreachable"
	)
	# Graceful for a local/custom override — just reflects the address.
	assert_string_contains(
		ServerProbe.chip_text(ServerProbe.Status.ONLINE, 1, "127.0.0.1"), "127.0.0.1"
	)


func test_chip_color_is_semantic() -> void:
	assert_eq(ServerProbe.chip_color(ServerProbe.Status.ONLINE), PartyTheme.SUCCESS)
	assert_eq(ServerProbe.chip_color(ServerProbe.Status.UNREACHABLE), PartyTheme.DANGER)
	assert_eq(ServerProbe.chip_color(ServerProbe.Status.CHECKING), PartyTheme.TEXT_DIM)


func test_retry_shows_only_when_unreachable() -> void:
	assert_false(ServerProbe.retry_visible(ServerProbe.Status.CHECKING))
	assert_false(ServerProbe.retry_visible(ServerProbe.Status.ONLINE))
	assert_true(ServerProbe.retry_visible(ServerProbe.Status.UNREACHABLE))
