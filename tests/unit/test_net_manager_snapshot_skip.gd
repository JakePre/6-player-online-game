extends GutTest
## Empty-idle snapshot-broadcast skip (#765, the #710 deferred follow-up). The
## server only fans a snapshot out in states MatchScreen actually renders;
## every other state (and a room with no live match) ships a frame the client
## discards. This pins the predicate that decides it, so a future State enum
## edit can't silently start (or stop) broadcasting a state.


func test_client_consumed_states_are_broadcast() -> void:
	for state: int in [
		MatchController.State.COUNTDOWN,
		MatchController.State.PLAY,
		MatchController.State.FINALE_PLAY,
		MatchController.State.FINALE_SHOP,
	]:
		assert_true(
			NetManager.snapshot_state_reaches_client(state),
			"state %d is rendered by MatchScreen, so it must broadcast" % state
		)


func test_chrome_states_are_skipped() -> void:
	# MatchScreen._on_snapshot early-returns on all of these, so a 30 Hz frame
	# in them is pure idle/between-round bandwidth.
	for state: int in [
		MatchController.State.INTRO,
		MatchController.State.RESULTS,
		MatchController.State.LEADERBOARD,
		MatchController.State.PODIUM,
		MatchController.State.DONE,
	]:
		assert_false(
			NetManager.snapshot_state_reaches_client(state),
			"state %d is discarded by the client, so it must skip" % state
		)


func test_consumed_set_matches_the_predicate() -> void:
	# The const and the predicate must not drift apart.
	for state: int in NetManager.CLIENT_CONSUMED_STATES:
		assert_true(NetManager.snapshot_state_reaches_client(state))
	assert_eq(
		NetManager.CLIENT_CONSUMED_STATES.size(),
		4,
		"COUNTDOWN, PLAY, FINALE_PLAY, FINALE_SHOP — update this if a rendered state is added"
	)
