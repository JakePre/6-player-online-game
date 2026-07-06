class_name BotInputDriver
extends RefCounted
## Shared random-input generator for practice-mode bots (#577, server-driven
## in-room members) and the headless playtest bots (#560). Produces a
## plausible gameplay intent — a movement stick plus sometimes one action —
## that every sim validates off the wire, so keys a game doesn't read simply
## no-op. One generator covers the whole roster; seed per bot for variety.

const ACTION_CHANCE := 0.3
## One-shot action booleans the roster's sims read off the wire (surveyed
## across src/minigames/*), pressed at random. Numeric intents (vote, lane,
## pad, aim) are rolled separately in next_intent().
const ACTION_KEYS: Array[String] = [
	"jump",
	"act",
	"fire",
	"dash",
	"use",
	"swing",
	"throw",
	"smash",
	"jab",
	"shove",
	"pull",
	"putt",
	"roll",
]

var _rng := RandomNumberGenerator.new()


func _init(seed_value: int) -> void:
	_rng.seed = seed_value


## A plausible random gameplay intent: a movement stick plus sometimes one
## action key or numeric roll. Deterministic given the seed + call order.
func next_intent() -> Dictionary:
	var intent := {
		"mx": _rng.randf_range(-1.0, 1.0),
		"my": _rng.randf_range(-1.0, 1.0),
	}
	if _rng.randf() < ACTION_CHANCE:
		match _rng.randi_range(0, 3):
			0:
				intent[ACTION_KEYS[_rng.randi_range(0, ACTION_KEYS.size() - 1)]] = true
			1:
				intent["ax"] = _rng.randf_range(-1.0, 1.0)
				intent["ay"] = _rng.randf_range(-1.0, 1.0)
			2:
				intent["vote"] = _rng.randi_range(0, 5)
			3:
				intent["lane"] = _rng.randi_range(0, 3)
				intent["pad"] = _rng.randi_range(0, 8)
	return intent
