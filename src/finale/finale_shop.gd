class_name FinaleShop
extends RefCounted
## Finale buy-in shop (M5-01, SPEC $6): a 30 s phase where each player spends
## match coins on the four purchasables before The Gauntlet. Pure logic driven
## by tick(delta); the server owns the instance and relays `closed` loadouts
## into the finale (M5-02). Leftover coins are kept per slot — they break
## final-ranking ties (M5-03).

signal closed(loadouts: Dictionary)

const SHOP_SEC := 30.0

## The four purchasables: price in coins and per-player purchase cap.
const ITEMS := {
	&"extra_life": {"price": 100, "cap": 2},
	&"shield": {"price": 40, "cap": 1},
	&"speed_boost": {"price": 40, "cap": 1},
	&"sabotage_token": {"price": 60, "cap": 1},
}

var open := true
var time_left := SHOP_SEC

var _coins := {}
var _bought := {}
var _confirmed := {}


## `coins_by_slot` is {slot: coins earned this match} (RoomMember.score).
func _init(coins_by_slot: Dictionary, shop_sec := SHOP_SEC) -> void:
	time_left = shop_sec
	for slot: int in coins_by_slot:
		_coins[slot] = int(coins_by_slot[slot])
		_bought[slot] = {}
		_confirmed[slot] = false


func tick(delta: float) -> void:
	if not open:
		return
	time_left = maxf(time_left - delta, 0.0)
	if time_left == 0.0:
		_close()


## Returns true and deducts the price if `slot` can afford `item` and is
## under its cap; false otherwise (unknown item/slot, shop closed, confirmed).
func buy(slot: int, item: StringName) -> bool:
	if not _can_trade(slot, item):
		return false
	var price: int = ITEMS[item]["price"]
	var owned: int = _bought[slot].get(item, 0)
	if owned >= int(ITEMS[item]["cap"]) or price > int(_coins[slot]):
		return false
	_coins[slot] = int(_coins[slot]) - price
	_bought[slot][item] = owned + 1
	return true


## Undo one purchase of `item`, restoring its price. Same gating as buy().
func refund(slot: int, item: StringName) -> bool:
	if not _can_trade(slot, item):
		return false
	var owned: int = _bought[slot].get(item, 0)
	if owned <= 0:
		return false
	_coins[slot] = int(_coins[slot]) + int(ITEMS[item]["price"])
	if owned == 1:
		_bought[slot].erase(item)
	else:
		_bought[slot][item] = owned - 1
	return true


## Lock in the slot's loadout. The shop closes early once every slot confirms.
func confirm(slot: int) -> void:
	if not open or not _confirmed.has(slot):
		return
	_confirmed[slot] = true
	if all_confirmed():
		_close()


func all_confirmed() -> bool:
	for slot: int in _confirmed:
		if not _confirmed[slot]:
			return false
	return not _confirmed.is_empty()


func coins_left(slot: int) -> int:
	return int(_coins.get(slot, 0))


## {item: count} for the slot's current purchases.
func loadout(slot: int) -> Dictionary:
	return Dictionary(_bought.get(slot, {})).duplicate()


## {slot: {"items": {item: count}, "coins_left": int}} — the finale's input.
func loadouts() -> Dictionary:
	var out := {}
	for slot: int in _bought:
		out[slot] = {"items": loadout(slot), "coins_left": coins_left(slot)}
	return out


func _can_trade(slot: int, item: StringName) -> bool:
	return open and ITEMS.has(item) and _bought.has(slot) and not _confirmed[slot]


func _close() -> void:
	if not open:
		return
	open = false
	closed.emit(loadouts())
