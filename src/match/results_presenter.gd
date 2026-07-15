class_name ResultsPresenter
extends RefCounted
## Round-results presentation for MatchScreen (#943 part 2): fills the results
## panel (title + ranked lines, packed for large lobbies) and flies the "+N"
## coin chips toward the running-totals HUD row.
##
## MatchScreen keeps the totals row itself (the persistent HUD), panel
## visibility, stats recording, and standings/podium (which route through
## StandingsPanel). This owns only the results-panel content and its coin
## decoration — the coins are added to the match-screen root (passed in) so a
## `get_node("CoinFly<slot>")` from there still resolves.

## Ranked result lines pack into at most this many rows (several entries per
## row for large lobbies) so the list never overflows the panel (M15-06).
const RESULTS_MAX_ROWS := 12
## Coin-chip flight duration and the grid it packs into (M6-02 / M15-06).
const COIN_FLY_SEC := 0.6
const COIN_GRID_SPACING := Vector2(80.0, 30.0)

var _title: Label
var _list: VBoxContainer
## The match-screen root: coins are parented here and its size / global
## position anchor the flight. `_totals_row` is the HUD row they fly toward.
var _root: Control
var _totals_row: Control


func _init(title: Label, list: VBoxContainer, root: Control, totals_row: Control) -> void:
	_title = title
	_list = list
	_root = root
	_totals_row = totals_row


## Fills the results panel for a completed round.
func render(round_number: int, placements: Array, awards: Dictionary, names: Dictionary) -> void:
	_title.text = "Round %d results" % round_number
	_fill_list(_fit_result_lines(MatchFormat.result_lines(placements, awards, names)))


## "+N" coin chips fly from mid-screen to the running-total row (M6-02). Pure
## decoration: totals are already correct before the flight starts, so reduced
## motion (M12-03) skips it outright — nothing to show at rest.
func fly_coins(awards: Dictionary) -> void:
	if ArenaFX.reduced_motion:
		return
	var slots: Array = awards.keys()
	slots.sort()
	var earners := slots.filter(func(s: int) -> bool: return int(awards.get(s, 0)) > 0)
	var placed := 0
	for slot: int in earners:
		var coin := Label.new()
		coin.name = "CoinFly%d" % slot
		coin.text = "+%d" % int(awards[slot])
		# The chunky display face makes the +N read as it flies (M16-08).
		coin.theme_type_variation = &"HeaderLabel"
		coin.add_theme_color_override("font_color", PlayerPalette.color_for_slot(slot))
		_root.add_child(coin)
		var offset := _coin_grid_offset(placed, earners.size(), _root.size.x)
		coin.position = _root.size / 2.0 + offset - Vector2(_root.size.x * 0.25, 0.0)
		# global_position (not local .position) so the target stays correct no
		# matter how many containers now sit between TotalsRow and the root
		# (#571 added a ScrollContainer wrapper to cap the HUD's height).
		var target := _totals_row.global_position - _root.global_position + offset
		var tween := _root.create_tween()
		# EASE_IN is deliberate — chips accelerate away; the curve stays on-token.
		tween.set_ease(Tween.EASE_IN).set_trans(PartyTheme.TRANS_DEFAULT)
		tween.tween_property(coin, "position", target, COIN_FLY_SEC)
		tween.tween_callback(coin.queue_free)
		placed += 1


## Grid slot for coin chip `index` of `count`, packed into as many columns as
## fit `width` so no chip flies off-screen at large player counts (M15-06).
## Offset is relative to the totals row's left edge.
func _coin_grid_offset(index: int, count: int, width: float) -> Vector2:
	var cols := maxi(1, mini(count, int((width - 48.0) / COIN_GRID_SPACING.x)))
	return Vector2(
		24.0 + (index % cols) * COIN_GRID_SPACING.x, (index / cols) * COIN_GRID_SPACING.y
	)


## Packs ranked result lines into at most RESULTS_MAX_ROWS rows (several entries
## per row for large lobbies) so the list never overflows the panel; small
## lobbies keep one entry per row (M15-06).
func _fit_result_lines(lines: Array[String]) -> Array[String]:
	if lines.size() <= RESULTS_MAX_ROWS:
		return lines
	var per_row := int(ceil(float(lines.size()) / float(RESULTS_MAX_ROWS)))
	var packed: Array[String] = []
	for i in range(0, lines.size(), per_row):
		packed.append("     ".join(lines.slice(i, i + per_row)))
	return packed


func _fill_list(lines: Array[String]) -> void:
	for child in _list.get_children():
		child.queue_free()
	for line in lines:
		var label := Label.new()
		label.text = line
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_list.add_child(label)
