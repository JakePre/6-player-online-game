extends GutTest
## Gameplay-input flood guard (#707): a per-peer token bucket on
## _rpc_match_input, the same shape as the emote limiter (#592) but with its own
## generous budget. `_input_allowed(peer_id, now_ms)` takes time as a parameter,
## so the whole bucket is testable without real multiplayer transport or delays.

const PEER := 42


func after_each() -> void:
	NetManager._input_tokens = {}


func test_a_full_burst_is_allowed_instantly() -> void:
	for i in int(NetManager.INPUT_BURST_MAX):
		assert_true(
			NetManager._input_allowed(PEER, 1000),
			"burst token %d/%d" % [i + 1, int(NetManager.INPUT_BURST_MAX)]
		)


func test_the_burst_plus_one_is_rejected() -> void:
	for i in int(NetManager.INPUT_BURST_MAX):
		NetManager._input_allowed(PEER, 1000)
	assert_false(NetManager._input_allowed(PEER, 1000), "the burst is exhausted")


func test_one_token_refills_after_the_refill_interval() -> void:
	for i in int(NetManager.INPUT_BURST_MAX):
		NetManager._input_allowed(PEER, 1000)
	assert_false(NetManager._input_allowed(PEER, 1000 + int(NetManager.INPUT_REFILL_MS) - 1))
	assert_true(
		NetManager._input_allowed(PEER, 1000 + int(NetManager.INPUT_REFILL_MS)),
		"exactly one refill interval grants exactly one token"
	)


func test_tokens_never_exceed_the_burst_cap() -> void:
	NetManager._input_allowed(PEER, 1000)  # spend one token
	# Wait far longer than needed to fully refill — should cap at max, not
	# accumulate unbounded credit for a future mega-burst.
	var far_future := 1000 + int(NetManager.INPUT_REFILL_MS) * 1000
	for i in int(NetManager.INPUT_BURST_MAX):
		assert_true(NetManager._input_allowed(PEER, far_future), "capped burst, not %d" % (i + 1))
	assert_false(NetManager._input_allowed(PEER, far_future), "no overflow beyond the cap")


func test_a_packet_rate_flood_is_capped() -> void:
	# A hostile client hammering many intents in the same millisecond gets its
	# burst and no more until tokens refill.
	var allowed := 0
	for _i in 500:
		if NetManager._input_allowed(PEER, 5000):
			allowed += 1
	assert_eq(
		allowed, int(NetManager.INPUT_BURST_MAX), "a same-instant flood only spends the burst"
	)


func test_peers_have_independent_buckets() -> void:
	for i in int(NetManager.INPUT_BURST_MAX):
		NetManager._input_allowed(PEER, 1000)
	assert_false(NetManager._input_allowed(PEER, 1000), "this peer's burst is spent")
	assert_true(NetManager._input_allowed(99, 1000), "a different peer has its own full burst")


func test_a_legitimate_30hz_stream_is_never_dropped() -> void:
	# The real worst case: a movement view sends one intent per 30 Hz physics
	# tick (~33.3 ms apart) for a whole minute. The sustained refill sits well
	# above 30/s, so not a single legit intent is ever throttled.
	var now := 1000
	for _i in 1800:  # 60 s at 30 Hz
		assert_true(NetManager._input_allowed(PEER, now), "30 Hz play stays under budget")
		now += 33
