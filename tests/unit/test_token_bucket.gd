extends GutTest
## TokenBucket (#770): the per-key rate-limit math extracted from NetManager's
## emote (#592) and input (#707) limiters. Those two limiters' suites
## (test_net_manager_{emote,input}_rate_limit) exercise this through the live
## delegations; this pins the class's own contract directly — burst, refill,
## cap, and per-key independence — with explicit config, no NetManager.

const BURST := 3.0
const REFILL_MS := 500.0
const KEY := 7


func test_a_full_burst_is_allowed_then_the_next_is_rejected() -> void:
	var state := {}
	for i in int(BURST):
		assert_true(TokenBucket.consume(state, KEY, 1000, BURST, REFILL_MS), "burst token %d" % i)
	assert_false(TokenBucket.consume(state, KEY, 1000, BURST, REFILL_MS), "burst exhausted")


func test_one_token_refills_after_exactly_one_interval() -> void:
	var state := {}
	for i in int(BURST):
		TokenBucket.consume(state, KEY, 1000, BURST, REFILL_MS)
	assert_false(
		TokenBucket.consume(state, KEY, 1000 + int(REFILL_MS) - 1, BURST, REFILL_MS),
		"just short of a refill interval grants nothing"
	)
	assert_true(
		TokenBucket.consume(state, KEY, 1000 + int(REFILL_MS), BURST, REFILL_MS),
		"exactly one interval grants exactly one token"
	)


func test_tokens_never_exceed_the_burst_cap() -> void:
	var state := {}
	TokenBucket.consume(state, KEY, 1000, BURST, REFILL_MS)  # spend one
	var far_future := 1000 + int(REFILL_MS) * 100
	for i in int(BURST):
		assert_true(TokenBucket.consume(state, KEY, far_future, BURST, REFILL_MS), "capped burst")
	assert_false(
		TokenBucket.consume(state, KEY, far_future, BURST, REFILL_MS), "no overflow beyond the cap"
	)


func test_keys_have_independent_buckets() -> void:
	var state := {}
	for i in int(BURST):
		TokenBucket.consume(state, KEY, 1000, BURST, REFILL_MS)
	assert_false(TokenBucket.consume(state, KEY, 1000, BURST, REFILL_MS), "this key is spent")
	assert_true(
		TokenBucket.consume(state, 99, 1000, BURST, REFILL_MS), "a new key has a full burst"
	)
