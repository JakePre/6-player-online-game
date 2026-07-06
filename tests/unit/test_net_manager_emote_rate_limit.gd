extends GutTest
## Emote rate limiter (#592): a token bucket replacing the old flat 1000ms
## cooldown, so a quick burst of taps feels snappy while a sustained-spam
## rate still caps a 24-player room. `_emote_allowed(peer_id, now_ms)` takes
## time as a parameter, so the whole bucket is testable without real delays.

const PEER := 42


func after_each() -> void:
	NetManager._emote_tokens = {}


func test_a_full_burst_is_allowed_instantly() -> void:
	for i in int(NetManager.EMOTE_BURST_MAX):
		assert_true(NetManager._emote_allowed(PEER, 1000), "burst token %d/%d" % [i + 1, 3])


func test_the_burst_plus_one_is_rejected() -> void:
	for i in int(NetManager.EMOTE_BURST_MAX):
		NetManager._emote_allowed(PEER, 1000)
	assert_false(NetManager._emote_allowed(PEER, 1000), "the burst is exhausted")


func test_one_token_refills_after_the_refill_interval() -> void:
	for i in int(NetManager.EMOTE_BURST_MAX):
		NetManager._emote_allowed(PEER, 1000)
	assert_false(NetManager._emote_allowed(PEER, 1000 + int(NetManager.EMOTE_REFILL_MS) - 1))
	assert_true(
		NetManager._emote_allowed(PEER, 1000 + int(NetManager.EMOTE_REFILL_MS)),
		"exactly one refill interval grants exactly one token"
	)


func test_tokens_never_exceed_the_burst_cap() -> void:
	NetManager._emote_allowed(PEER, 1000)  # spend one token (2 left)
	# Wait far longer than needed to fully refill -- should cap at max, not
	# accumulate unbounded credit for future bursts.
	var far_future := 1000 + int(NetManager.EMOTE_REFILL_MS) * 100
	for i in int(NetManager.EMOTE_BURST_MAX):
		assert_true(NetManager._emote_allowed(PEER, far_future), "capped burst, not %d" % (i + 1))
	assert_false(NetManager._emote_allowed(PEER, far_future), "no overflow beyond the cap")


func test_sustained_rate_settles_to_one_token_per_refill_interval() -> void:
	for i in int(NetManager.EMOTE_BURST_MAX):
		NetManager._emote_allowed(PEER, 1000)
	var now := 1000
	for _i in 5:
		now += int(NetManager.EMOTE_REFILL_MS)
		assert_true(NetManager._emote_allowed(PEER, now), "sustained rate keeps pace with refill")
		assert_false(
			NetManager._emote_allowed(PEER, now), "no second emote before the next interval"
		)


func test_peers_have_independent_buckets() -> void:
	for i in int(NetManager.EMOTE_BURST_MAX):
		NetManager._emote_allowed(PEER, 1000)
	assert_false(NetManager._emote_allowed(PEER, 1000), "this peer's burst is spent")
	assert_true(NetManager._emote_allowed(99, 1000), "a different peer has its own full burst")
