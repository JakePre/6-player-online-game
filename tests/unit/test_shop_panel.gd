extends GutTest
## The finale buy-in shop UI (#554): a pure renderer of the FINALE_SHOP
## snapshot — item rows, affordability gating, and the confirm state.

var panel: ShopPanel


func before_each() -> void:
	panel = (load("res://src/finale/shop_panel.tscn") as PackedScene).instantiate()
	add_child_autofree(panel)


func _shop_state(mine: Dictionary, others := {}) -> Dictionary:
	var players := {0: mine}
	players.merge(others)
	return {"players": players}


func test_renders_all_four_items() -> void:
	assert_eq(
		panel.get_node("%ShopItems").get_child_count(),
		FinaleShop.ITEMS.size(),
		"one row per purchasable"
	)


func test_render_reflects_coins_items_and_confirm_counts() -> void:
	panel.render(
		_shop_state(
			{"coins": 120, "items": {&"extra_life": 1}, "confirmed": false},
			{1: {"coins": 0, "items": {}, "confirmed": true}}
		),
		0,
		21.0
	)
	assert_eq((panel.get_node("%ShopCoinsLabel") as Label).text, "Your coins: 120")
	assert_eq((panel.get_node("%ShopConfirmedLabel") as Label).text, "1/2 locked in")
	var confirm: Button = panel.get_node("%ShopConfirmButton")
	assert_false(confirm.disabled, "not yet locked in")


func test_confirmed_player_gets_locked_controls() -> void:
	panel.render(_shop_state({"coins": 500, "items": {}, "confirmed": true}), 0, 10.0)
	var confirm: Button = panel.get_node("%ShopConfirmButton")
	assert_true(confirm.disabled)
	assert_eq(confirm.text, "Locked in!")


func test_unaffordable_items_disable_buy() -> void:
	panel.render(_shop_state({"coins": 50, "items": {}, "confirmed": false}), 0, 10.0)
	var extra_life_buy: Button = panel._rows[&"extra_life"]["buy"]
	var shield_buy: Button = panel._rows[&"shield"]["buy"]
	assert_true(extra_life_buy.disabled, "100c life unaffordable at 50c")
	assert_false(shield_buy.disabled, "40c shield affordable")


func test_capped_items_disable_buy_and_enable_refund() -> void:
	panel.render(_shop_state({"coins": 500, "items": {&"shield": 1}, "confirmed": false}), 0, 10.0)
	var shield: Dictionary = panel._rows[&"shield"]
	assert_true((shield.buy as Button).disabled, "cap 1 reached")
	assert_false((shield.refund as Button).disabled, "owned items refundable")
	assert_eq((shield.owned as Label).text, "×1")
