extends GutTest
## The hat wardrobe surface (#935): buy spends the wallet + owns the hat +
## equips it; equip persists the selection; affordability gating holds. State
## is injected (no disk) and the appearance RPC is skipped without a peer.

var panel: WardrobePanel


func before_each() -> void:
	panel = WardrobePanel.new()
	panel.persist = false  # no user:// writes in tests
	add_child_autofree(panel)


func _state(coins: int, owned := ["none"], selected := "none") -> void:
	panel.set_state({"coins": coins}, {"owned_hats": owned, "selected_hat": selected})


func test_buy_spends_owns_and_equips_when_affordable() -> void:
	var price := HatCatalog.price(&"party_cone")
	_state(price + 50)
	watch_signals(panel)
	assert_true(panel.can_buy(&"party_cone"), "affordable")
	assert_true(panel.buy(&"party_cone"))
	assert_eq(panel.coins(), 50, "the price was spent from the wallet")
	assert_true(panel.is_owned(&"party_cone"), "owned forever now")
	assert_eq(panel.selected_hat(), &"party_cone", "and auto-equipped")
	assert_signal_emitted_with_parameters(panel, "hat_equipped", [&"party_cone"])


func test_cannot_buy_what_you_cannot_afford() -> void:
	_state(HatCatalog.price(&"top_hat") - 1)
	assert_false(panel.can_buy(&"top_hat"), "one coin short")
	assert_false(panel.buy(&"top_hat"), "the buy is refused")
	assert_false(panel.is_owned(&"top_hat"))


func test_buying_an_owned_hat_is_a_noop_and_costs_nothing() -> void:
	_state(9999, ["none", "party_cone"])
	assert_false(panel.can_buy(&"party_cone"), "already owned")
	assert_false(panel.buy(&"party_cone"))
	assert_eq(panel.coins(), 9999, "no coins spent re-buying")


func test_equip_switches_an_owned_hat_without_spending() -> void:
	_state(100, ["none", "top_hat"], "none")
	assert_true(panel.equip(&"top_hat"))
	assert_eq(panel.selected_hat(), &"top_hat")
	assert_eq(panel.coins(), 100, "equipping is free")
	assert_false(panel.equip(&"crown"), "can't equip an unowned hat")


func test_rows_reflect_state() -> void:
	_state(HatCatalog.price(&"party_cone"), ["none"], "none")
	var rows: VBoxContainer = panel.get_node("Rows")
	var cone: Button = rows.get_node("party_cone")
	assert_string_contains(cone.text, "Buy", "affordable + unowned reads Buy")
	var crown: Button = rows.get_node("crown")
	assert_string_contains(crown.text, "Locked", "unaffordable reads Locked")
	assert_true(crown.disabled, "and can't be pressed")
