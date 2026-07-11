extends GutTest
## Human-like imperfection layer on BotBrain (#818): think() stays a pure
## decision (every per-brain test calls it directly, unaffected regardless of
## error_rate); think_with_error() is the wrapper the live server pump and
## practice-bot driver actually call, occasionally substituting a slip —
## delayed reaction, dropped input, or jittered aim/movement.


## A brain with a fixed, non-trivial think() so slips are observable against
## a known baseline instead of chasing another brain's own randomness.
class FixedBrain:
	extends BotBrain

	func think(_match_state: Dictionary, _private: Dictionary) -> Dictionary:
		return {"mx": 1.0, "my": 0.0, "jump": true}


class ButtonOnlyBrain:
	extends BotBrain

	func think(_match_state: Dictionary, _private: Dictionary) -> Dictionary:
		return {"jump": true}


## A distinct intent per call (a rising tick counter) so a delayed-reaction
## slip — replaying a prior call's intent instead of this call's — is
## observable: think() still runs every tick (only its result gets discarded
## on a delay), so a returned tick lagging the call count proves a replay.
class SequenceBrain:
	extends BotBrain

	var _n := 0

	func think(_match_state: Dictionary, _private: Dictionary) -> Dictionary:
		_n += 1
		return {"tick": _n}


func test_default_error_rate_is_nonzero_with_zero_extra_wiring() -> void:
	var brain := RandomBrain.new(0, 1)
	assert_eq(brain.error_rate, BotBrain.DEFAULT_ERROR_RATE, "drivers get imperfection for free")


func test_zero_error_rate_is_an_exact_passthrough() -> void:
	var brain := FixedBrain.new(0, 1)
	brain.error_rate = 0.0
	for _i in 50:
		assert_eq(brain.think_with_error({}, {}), {"mx": 1.0, "my": 0.0, "jump": true})


func test_error_rate_one_produces_a_mix_of_slips() -> void:
	var brain := FixedBrain.new(0, 1)
	brain.error_rate = 1.0
	var saw_miss := false
	var saw_jitter := false
	for _i in 200:
		var intent := brain.think_with_error({}, {})
		if intent.is_empty():
			saw_miss = true
			continue
		assert_true(intent.get("jump", false), "non-direction fields ride through a slip untouched")
		if not is_equal_approx(float(intent.mx), 1.0) or not is_equal_approx(float(intent.my), 0.0):
			saw_jitter = true
	assert_true(saw_miss, "an always-erroneous bot drops input at least once in 200 ticks")
	assert_true(saw_jitter, "an always-erroneous bot jitters aim at least once in 200 ticks")


func test_delayed_reaction_replays_a_stale_intent() -> void:
	var brain := SequenceBrain.new(0, 1)
	brain.error_rate = 1.0
	var saw_stale := false
	for i in range(1, 201):
		var intent := brain.think_with_error({}, {})
		if not intent.is_empty() and int(intent.tick) < i:
			saw_stale = true
	assert_true(
		saw_stale, "an always-erroneous bot replays a stale decision at least once in 200 ticks"
	)


func test_jitter_preserves_magnitude_and_other_fields() -> void:
	var brain := FixedBrain.new(0, 1)
	var noisy: Dictionary = brain._jitter_aim({"mx": 1.0, "my": 0.0, "jump": true})
	assert_true(noisy.jump, "button fields pass through untouched")
	var dir := Vector2(noisy.mx, noisy.my)
	assert_almost_eq(dir.length(), 1.0, 0.01, "jitter rotates the direction, not its length")


func test_jitter_ignores_intents_without_a_direction_pair() -> void:
	var brain := ButtonOnlyBrain.new(0, 1)
	assert_eq(
		brain._jitter_aim({"jump": true}), {"jump": true}, "nothing to rotate — passes through"
	)


func test_button_only_brain_never_fabricates_a_direction() -> void:
	var brain := ButtonOnlyBrain.new(0, 1)
	brain.error_rate = 1.0
	for _i in 100:
		var intent := brain.think_with_error({}, {})
		assert_true(intent.is_empty() or intent.keys() == ["jump"], "still no mx/my out of nowhere")
