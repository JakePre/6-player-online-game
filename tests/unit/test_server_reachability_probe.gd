extends GutTest
## Server reachability probe (#607): a one-shot ENet look-before-you-leap check.
## Its reachability *result* depends on a live server, which a headless unit run
## has none of — so these cover the deterministic contract (never touches the
## shared multiplayer peer; cancels cleanly) rather than asserting a real connect.


func test_never_touches_the_shared_multiplayer_peer() -> void:
	var before := multiplayer.multiplayer_peer
	var probe := ServerReachabilityProbe.new()
	add_child_autofree(probe)
	probe.start("127.0.0.1", 65535)
	assert_eq(
		multiplayer.multiplayer_peer, before, "the probe must not hijack the real session peer"
	)
	probe.cancel()


func test_cancel_before_finish_stays_quiet() -> void:
	var probe := ServerReachabilityProbe.new()
	add_child_autofree(probe)
	watch_signals(probe)
	probe.start("127.0.0.1", 65535)
	probe.cancel()
	await wait_frames(2)
	assert_signal_not_emitted(probe, "finished", "a cancelled probe emits no result")


func test_cancel_without_start_is_safe() -> void:
	var probe := ServerReachabilityProbe.new()
	add_child_autofree(probe)
	probe.cancel()
	pass_test("cancelling a never-started probe does not crash")
