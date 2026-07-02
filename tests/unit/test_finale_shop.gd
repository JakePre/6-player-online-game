extends GutTest
## Finale buy-in shop (SPEC $6): prices, caps, coin math, confirm/early-close,
## and the 30 s timer.


func _shop(coins := {0: 200, 1: 100}) -> FinaleShop:
	return FinaleShop.new(coins)


func test_prices_and_caps_match_spec() -> void:
	assert_eq(FinaleShop.ITEMS[&"extra_life"], {"price": 100, "cap": 2})
	assert_eq(FinaleShop.ITEMS[&"shield"], {"price": 40, "cap": 1})
	assert_eq(FinaleShop.ITEMS[&"speed_boost"], {"price": 40, "cap": 1})
	assert_eq(FinaleShop.ITEMS[&"sabotage_token"], {"price": 60, "cap": 1})


func test_buy_deducts_price() -> void:
	var shop := _shop()
	assert_true(shop.buy(0, &"extra_life"))
	assert_eq(shop.coins_left(0), 100)
	assert_eq(shop.loadout(0), {&"extra_life": 1})


func test_insufficient_funds_rejected() -> void:
	var shop := _shop({0: 39})
	assert_false(shop.buy(0, &"shield"))
	assert_eq(shop.coins_left(0), 39)
	assert_eq(shop.loadout(0), {})


func test_extra_life_cap_is_two() -> void:
	var shop := _shop({0: 500})
	assert_true(shop.buy(0, &"extra_life"))
	assert_true(shop.buy(0, &"extra_life"))
	assert_false(shop.buy(0, &"extra_life"))
	assert_eq(shop.coins_left(0), 300)
	assert_eq(shop.loadout(0), {&"extra_life": 2})


func test_single_purchase_items_capped_at_one() -> void:
	var shop := _shop()
	for item: StringName in [&"shield", &"speed_boost", &"sabotage_token"]:
		assert_true(shop.buy(0, item), "first %s" % item)
		assert_false(shop.buy(0, item), "second %s" % item)


func test_unknown_item_and_unknown_slot_rejected() -> void:
	var shop := _shop()
	assert_false(shop.buy(0, &"rocket_launcher"))
	assert_false(shop.buy(9, &"shield"))
	assert_eq(shop.coins_left(9), 0)


func test_refund_restores_price_and_count() -> void:
	var shop := _shop()
	shop.buy(0, &"sabotage_token")
	assert_true(shop.refund(0, &"sabotage_token"))
	assert_eq(shop.coins_left(0), 200)
	assert_eq(shop.loadout(0), {})
	assert_false(shop.refund(0, &"sabotage_token"))


func test_refund_one_of_two_lives() -> void:
	var shop := _shop()
	shop.buy(0, &"extra_life")
	shop.buy(0, &"extra_life")
	assert_true(shop.refund(0, &"extra_life"))
	assert_eq(shop.coins_left(0), 100)
	assert_eq(shop.loadout(0), {&"extra_life": 1})


func test_confirmed_slot_is_locked() -> void:
	var shop := _shop()
	shop.buy(0, &"shield")
	shop.confirm(0)
	assert_false(shop.buy(0, &"speed_boost"))
	assert_false(shop.refund(0, &"shield"))
	assert_true(shop.buy(1, &"shield"), "other slots still shop")


func test_all_confirmed_closes_early_with_loadouts() -> void:
	var shop := _shop()
	watch_signals(shop)
	shop.buy(0, &"extra_life")
	shop.confirm(0)
	assert_true(shop.open)
	shop.confirm(1)
	assert_false(shop.open)
	var expected := {
		0: {"items": {&"extra_life": 1}, "coins_left": 100},
		1: {"items": {}, "coins_left": 100},
	}
	assert_signal_emitted_with_parameters(shop, "closed", [expected])


func test_timer_expiry_closes_shop() -> void:
	var shop := _shop()
	watch_signals(shop)
	shop.tick(29.9)
	assert_true(shop.open)
	shop.tick(0.2)
	assert_false(shop.open)
	assert_eq(shop.time_left, 0.0)
	assert_signal_emit_count(shop, "closed", 1)


func test_no_trading_after_close() -> void:
	var shop := _shop()
	shop.buy(0, &"shield")
	shop.tick(FinaleShop.SHOP_SEC)
	assert_false(shop.buy(0, &"speed_boost"))
	assert_false(shop.refund(0, &"shield"))
	assert_eq(shop.coins_left(0), 160)


func test_close_emits_once() -> void:
	var shop := _shop()
	watch_signals(shop)
	shop.confirm(0)
	shop.confirm(1)
	shop.tick(FinaleShop.SHOP_SEC)
	assert_signal_emit_count(shop, "closed", 1)


func test_loadout_copies_do_not_leak_state() -> void:
	var shop := _shop()
	shop.buy(0, &"shield")
	var snapshot := shop.loadout(0)
	snapshot[&"extra_life"] = 99
	assert_eq(shop.loadout(0), {&"shield": 1})
