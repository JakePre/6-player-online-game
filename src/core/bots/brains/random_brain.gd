class_name RandomBrain
extends BotBrain
## Fallback brain (M19, #684): games without a dedicated brain yet keep the
## pre-M19 behavior exactly — the shared random-intent generator (#560/#577).

var _driver: BotInputDriver


func _init(bot_slot: int, seed_value: int) -> void:
	super(bot_slot, seed_value)
	_driver = BotInputDriver.new(seed_value)


func think(_match_state: Dictionary, _private: Dictionary) -> Dictionary:
	return _driver.next_intent()
