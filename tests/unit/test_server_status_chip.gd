extends GutTest
## Pre-connection server status chip (#607): the state machine + labelling that
## tells a player whether the default server is reachable before they commit to
## Host/Join. The real socket probe is gated off (`live_probe = false`) so these
## drive the states directly and stay deterministic/offline.

var chip: ServerStatusChip


func before_each() -> void:
	chip = ServerStatusChip.new()
	add_child_autofree(chip)
	chip.live_probe = false


func test_remote_target_starts_checking_and_asks_for_a_probe() -> void:
	watch_signals(chip)
	chip.configure("celestrum.com", 7777)
	assert_signal_emitted(chip, "probe_requested", "a remote default kicks off a probe")
	assert_eq(chip._status_text(), chip.CHECKING_TEXT)
	assert_eq(chip._status_color(), PartyTheme.TEXT_DIM, "checking is neutral, not good/bad yet")
	assert_false(chip._retry.visible, "no retry while still checking")


func test_reachable_reports_online_with_rtt() -> void:
	chip.configure("celestrum.com", 7777)
	chip._on_probe_finished(true, 34)
	assert_eq(chip._status_text(), "Online · 34 ms")
	assert_eq(chip._label.text, "Online · 34 ms", "the visible label follows the state")
	assert_eq(chip._status_color(), PartyTheme.SUCCESS)
	assert_false(chip._retry.visible, "nothing to retry when online")


func test_reachable_without_a_reading_still_reads_online() -> void:
	chip.configure("celestrum.com", 7777)
	chip._on_probe_finished(true, -1)
	assert_eq(chip._status_text(), "Online")


func test_unreachable_is_danger_and_offers_a_retry() -> void:
	chip.configure("celestrum.com", 7777)
	chip._on_probe_finished(false, -1)
	assert_eq(chip._status_text(), chip.UNREACHABLE_TEXT)
	assert_eq(chip._status_color(), PartyTheme.DANGER)
	assert_true(chip._retry.visible, "an unreachable server offers a retry")


func test_retry_reprobes_and_hides_itself() -> void:
	chip.configure("celestrum.com", 7777)
	chip._on_probe_finished(false, -1)
	assert_true(chip._retry.visible)
	watch_signals(chip)
	chip._retry.pressed.emit()
	assert_signal_emitted(chip, "probe_requested", "retry starts a fresh probe")
	assert_eq(chip._status_text(), chip.CHECKING_TEXT, "back to checking")
	assert_false(chip._retry.visible, "retry hides once a new probe is in flight")


## Loopback defaults have no server to reach until the player Hosts — the chip
## labels them instead of probing and mislabelling them "Unreachable".
func test_loopback_target_is_labelled_not_probed() -> void:
	for host: String in ["127.0.0.1", "localhost", "::1", ""]:
		var local := ServerStatusChip.new()
		add_child_autofree(local)
		local.live_probe = false
		watch_signals(local)
		local.configure(host, 7777)
		assert_eq(local._status_text(), local.LOCAL_TEXT, "%s is labelled local" % host)
		assert_eq(local._status_color(), PartyTheme.TEXT_DIM, "local is neutral")
		assert_false(local._retry.visible, "nothing to retry for a local target")
		assert_signal_not_emitted(local, "probe_requested", "%s does not probe" % host)
