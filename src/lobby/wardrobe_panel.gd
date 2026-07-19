class_name WardrobePanel
extends VBoxContainer
## The hat wardrobe (#935): a compact lobby surface listing every HatCatalog
## hat with its price and state — equipped, owned, or locked behind a coin
## price. Buying spends from the StatsStore wallet and marks the hat owned in
## SettingsStore forever; equipping persists the selection and pushes it to the
## room over the appearance RPC so everyone sees it. Pad-navigable (each hat is
## a focusable Button, M17).
##
## State lives in the two stores; the panel mirrors them in memory (injectable
## for tests via set_state) and writes through on every buy/equip.

signal hat_equipped(hat_id: StringName)

## Off in tests so buy/equip mutate the in-memory copies without writing the
## shared user:// stats/settings files (which other suites assert are pristine).
var persist := true

var _stats := {}
var _settings := {}
var _wallet_label: Label
var _rows: VBoxContainer


func _ready() -> void:
	add_theme_constant_override(&"separation", 6)
	var header := Label.new()
	header.text = "Wardrobe"
	header.theme_type_variation = PartyTheme.HEADER_VARIATION
	add_child(header)
	_wallet_label = Label.new()
	_wallet_label.name = "Wallet"
	add_child(_wallet_label)
	_rows = VBoxContainer.new()
	_rows.name = "Rows"
	add_child(_rows)
	load_state()


## Reload both stores from disk and rebuild (the live path).
func load_state() -> void:
	set_state(StatsStore.load_stats(), SettingsStore.load_settings())


## Inject state without touching disk (tests) and rebuild.
func set_state(stats: Dictionary, settings: Dictionary) -> void:
	_stats = stats
	_settings = settings
	refresh()


func coins() -> int:
	return int(_stats.get("coins", 0))


func is_owned(id: StringName) -> bool:
	return String(id) in (_settings.get("owned_hats", ["none"]) as Array)


func selected_hat() -> StringName:
	return StringName(_settings.get("selected_hat", "none"))


func can_buy(id: StringName) -> bool:
	return not is_owned(id) and coins() >= HatCatalog.price(id)


## Buy a locked hat if affordable: spend the coins, own it forever, equip it.
func buy(id: StringName) -> bool:
	if not can_buy(id):
		return false
	_stats = StatsStore.spend(_stats, HatCatalog.price(id))
	if persist:
		StatsStore.save_stats(_stats)
	var owned: Array = (_settings.get("owned_hats", ["none"]) as Array).duplicate()
	owned.append(String(id))
	_settings.owned_hats = owned
	equip(id)
	return true


## Equip an owned hat: persist the selection and push it to the room.
func equip(id: StringName) -> bool:
	if not is_owned(id):
		return false
	_settings.selected_hat = String(id)
	if persist:
		SettingsStore.save_settings(_settings)
	# Only reach the server when actually connected (bare panel / tests skip it).
	if NetManager.multiplayer != null and NetManager.multiplayer.multiplayer_peer != null:
		NetManager.request_set_hat(id)
	hat_equipped.emit(id)
	refresh()
	return true


func refresh() -> void:
	if _wallet_label == null:
		return
	_wallet_label.text = "Coins: %d" % coins()
	# Freed immediately, not queued: a following get_node/refresh in the same
	# frame must not find the stale row still shadowing the rebuilt one.
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.free()
	for id: StringName in HatCatalog.ids():
		_rows.add_child(_build_row(id))


func _build_row(id: StringName) -> Button:
	var button := Button.new()
	button.name = String(id)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	var state := _row_state(id)
	button.text = state
	button.disabled = _row_disabled(id)
	button.pressed.connect(func() -> void: _on_row_pressed(id))
	return button


## The row's label: equipped hats read "✓", owned ones "Equip", and locked
## ones show the price (dimmed to "need N more" when unaffordable).
func _row_state(id: StringName) -> String:
	var name := HatCatalog.display_name(id)
	if selected_hat() == id:
		return "✓ %s (equipped)" % name
	if is_owned(id):
		return "%s — Equip" % name
	var price := HatCatalog.price(id)
	if coins() >= price:
		return "%s — Buy (%d)" % [name, price]
	return "%s — Locked (%d coins)" % [name, price]


func _row_disabled(id: StringName) -> bool:
	# Equipped: nothing to do. Locked + unaffordable: can't act yet.
	return selected_hat() == id or (not is_owned(id) and coins() < HatCatalog.price(id))


func _on_row_pressed(id: StringName) -> void:
	if is_owned(id):
		equip(id)
	else:
		buy(id)
