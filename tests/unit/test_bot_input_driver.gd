extends GutTest
## Shared random-input generator (#577) used by practice bots and the headless
## playtest bots: a movement stick, sometimes one action, always seed-driven.


func test_every_intent_carries_a_movement_stick() -> void:
	var driver := BotInputDriver.new(1)
	for _i in 50:
		var intent := driver.next_intent()
		assert_true(intent.has("mx") and intent.has("my"), "movement always present")
		assert_between(float(intent.mx), -1.0, 1.0)
		assert_between(float(intent.my), -1.0, 1.0)


func test_same_seed_reproduces_the_same_stream() -> void:
	var a := BotInputDriver.new(1234)
	var b := BotInputDriver.new(1234)
	for _i in 20:
		assert_eq(a.next_intent(), b.next_intent(), "deterministic per seed")


func test_different_seeds_diverge() -> void:
	var a := BotInputDriver.new(1)
	var b := BotInputDriver.new(2)
	var same := true
	for _i in 20:
		if a.next_intent() != b.next_intent():
			same = false
			break
	assert_false(same, "distinct seeds produce distinct behavior")


func test_actions_fire_sometimes_and_are_valid_keys() -> void:
	var driver := BotInputDriver.new(7)
	var saw_action := false
	for _i in 200:
		var intent: Dictionary = driver.next_intent()
		for key: String in intent:
			if key in ["mx", "my", "ax", "ay", "vote", "lane", "pad"]:
				continue
			# Any remaining boolean key must be a real roster action.
			assert_true(key in BotInputDriver.ACTION_KEYS, "%s is a known action" % key)
			saw_action = true
	assert_true(saw_action, "over 200 rolls, some intents press an action")


func test_action_set_covers_the_side_scroll_verbs() -> void:
	# Regression: the side-scroll games (Knock-Off jab, Loadout throw/fire)
	# must be reachable, or bots can't exercise them.
	for verb in ["jump", "fire", "throw", "smash", "jab"]:
		assert_true(verb in BotInputDriver.ACTION_KEYS, "%s is drivable" % verb)
