class_name ShopPanel
extends PanelContainer
## The finale buy-in shop UI (SPEC $6, #554): 30 s to spend match coins on the
## four purchasables before The Gauntlet. A pure renderer of the FINALE_SHOP
## snapshot — every click just sends a shop intent on the match-input channel
## and waits for the authoritative state to echo back, so a lost packet is
## visibly un-bought and re-clickable. Styled per PartyTheme (M16).

## Display copy per FinaleShop item id, in shop display order.
const ITEM_COPY := [
	{
		"id": &"extra_life",
		"name": "Extra Life",
		"blurb": "Respawn once more after a knockout",
	},
	{"id": &"shield", "name": "Shield", "blurb": "Shrug off the first hit"},
	{"id": &"speed_boost", "name": "Speed Boost", "blurb": "Move 30% faster, all finale"},
	{
		"id": &"sabotage_token",
		"name": "Sabotage Token",
		"blurb": "Trigger one hazard on a rival",
	},
]

var _rows := {}
var _my_confirmed := false

@onready var _time_label: Label = %ShopTimeLabel
@onready var _coins_label: Label = %ShopCoinsLabel
@onready var _items_column: VBoxContainer = %ShopItems
@onready var _confirm_button: Button = %ShopConfirmButton
@onready var _confirmed_label: Label = %ShopConfirmedLabel


func _ready() -> void:
	for entry: Dictionary in ITEM_COPY:
		_items_column.add_child(_build_row(entry))
	_confirm_button.pressed.connect(_send.bind({"action": "confirm"}))


## Pad navigation (M17-04): the match screen calls this when the shop phase
## opens so a controller lands on the first Buy button immediately.
func grab_initial_focus() -> void:
	for entry: Dictionary in ITEM_COPY:
		var row: Dictionary = _rows.get(entry.id, {})
		var buy: Button = row.get("buy")
		if buy != null and not buy.disabled:
			buy.grab_focus()
			return
	%ShopConfirmButton.grab_focus()


## Renders the authoritative shop snapshot: {"players": {slot: {coins, items,
## confirmed}}}. `time_left` comes from the match snapshot's clock.
func render(shop: Dictionary, my_slot: int, time_left: float) -> void:
	# Pad parity (M17-02): remember who held focus BEFORE we start disabling
	# buttons, so we can rescue a controller whose focused control goes away.
	var prev_focus: Control = null
	if is_inside_tree():
		prev_focus = get_viewport().gui_get_focus_owner()
	_time_label.text = MatchFormat.clock(time_left)
	var players: Dictionary = shop.get("players", {})
	var mine: Dictionary = players.get(my_slot, {})
	_my_confirmed = bool(mine.get("confirmed", false))
	var coins := int(mine.get("coins", 0))
	var items: Dictionary = mine.get("items", {})
	_coins_label.text = "Your coins: %d" % coins
	for id: StringName in _rows:
		_update_row(id, items, coins)
	var confirmed := 0
	for slot: Variant in players:
		if bool(players[slot].get("confirmed", false)):
			confirmed += 1
	_confirmed_label.text = "%d/%d locked in" % [confirmed, players.size()]
	_confirm_button.disabled = _my_confirmed
	_confirm_button.text = "Locked in!" if _my_confirmed else "Lock in"
	_rescue_focus(prev_focus)


## Pad parity (M17-02): buying an item to its cap (or spending down so it is
## unaffordable) disables its Buy button — and Godot drops focus to null when
## the focused control is disabled, stranding a controller with no anchor. If
## the control we just disabled was OURS and had focus, hand focus to the next
## live control. We only act when we owned the lost focus, so normal stick
## navigation is never stolen.
func _rescue_focus(prev_focus: Control) -> void:
	if prev_focus == null or not _owns(prev_focus):
		return
	if prev_focus is Button and not (prev_focus as Button).disabled:
		return  # still focusable; the user is fine where they are
	for id: StringName in _rows:
		var buy: Button = _rows[id]["buy"]
		if not buy.disabled:
			buy.grab_focus()
			return
	for id: StringName in _rows:
		var refund: Button = _rows[id]["refund"]
		if not refund.disabled:
			refund.grab_focus()
			return
	if not _confirm_button.disabled:
		_confirm_button.grab_focus()


## True if `control` is one of the shop's own interactive buttons.
func _owns(control: Control) -> bool:
	if control == _confirm_button:
		return true
	for id: StringName in _rows:
		if control == _rows[id]["buy"] or control == _rows[id]["refund"]:
			return true
	return false


func _build_row(entry: Dictionary) -> Control:
	var id: StringName = entry.id
	var price := int(FinaleShop.ITEMS[id]["price"])
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", PartyTheme.SPACE_SM)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var name_label := Label.new()
	name_label.text = "%s — %dc" % [entry.name, price]
	name_label.theme_type_variation = PartyTheme.HINT_VARIATION
	text.add_child(name_label)
	var blurb := Label.new()
	blurb.text = entry.blurb
	blurb.theme_type_variation = PartyTheme.SMALL_VARIATION
	text.add_child(blurb)
	row.add_child(text)
	var owned := Label.new()
	owned.theme_type_variation = PartyTheme.HEADER_VARIATION
	owned.text = ""
	row.add_child(owned)
	var refund := Button.new()
	refund.text = "–"
	refund.pressed.connect(_send.bind({"action": "refund", "item": String(id)}))
	row.add_child(refund)
	var buy := Button.new()
	buy.text = "Buy"
	buy.pressed.connect(_send.bind({"action": "buy", "item": String(id)}))
	row.add_child(buy)
	_rows[id] = {"owned": owned, "buy": buy, "refund": refund}
	return row


func _update_row(id: StringName, items: Dictionary, coins: int) -> void:
	var row: Dictionary = _rows[id]
	var count := int(items.get(id, 0))
	var price := int(FinaleShop.ITEMS[id]["price"])
	var cap := int(FinaleShop.ITEMS[id]["cap"])
	(row.owned as Label).text = "×%d" % count if count > 0 else ""
	(row.buy as Button).disabled = _my_confirmed or count >= cap or price > coins
	(row.refund as Button).disabled = _my_confirmed or count <= 0


func _send(action: Dictionary) -> void:
	NetManager.send_match_input({"shop": action})
