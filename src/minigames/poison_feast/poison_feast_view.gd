extends MinigameView3D
## Poison Feast client view (reworked per #174, on the M8-01 MinigameView3D
## tier): the push-your-luck banquet. Dishes are Kenney food-kit bowls with a
## tier-colored glow ring under them — white (clean), orange (spiced, 1-in-4
## poisoned), purple (delicacy, 1-in-2), gold (final course). The pot rides a
## Control-layer banner; staggered eaters flinch, slow, and show it on their
## nameplate. Whether a specific dish is poisoned never reaches the client —
## tiers are the odds, the bite is the gamble.

const DISH_SCENE := preload("res://assets/environment/kenney_food_kit/bowl-soup.glb")
const DISH_SCALE := 2.0
const RING_HEIGHT := 0.05

const TIER_COLORS := {
	PoisonFeast.Tier.CLEAN: Color(0.92, 0.94, 0.9),
	PoisonFeast.Tier.SPICED: Color(0.95, 0.55, 0.2),
	PoisonFeast.Tier.DELICACY: Color(0.7, 0.35, 0.9),
	PoisonFeast.Tier.GOLDEN: Color(1.0, 0.85, 0.2),
}
const POISON_PUFF_COLOR := Color(0.4, 0.85, 0.35)

## Latest replicated state, straight from PoisonFeast.get_snapshot().
var players := {}
var dishes: Array = []
var pot := 0

var _dish_nodes := {}  # id (int) -> Node3D
var _dish_tiers := {}  # id (int) -> tier, for the tier-colored bite burst (M13-25)
var _pot_label: Label
var _staggered := {}  # slot (int) -> bool, for one-shot flinches
var _my_score := 0
var _prev_pot := 0


func _physics_process(_delta: float) -> void:
	send_move_intent()


## Sickly-green floor for the banquet menace (#589).
func _floor_tint() -> Color:
	return Color(0.88, 0.98, 0.82)


func _arena_half() -> float:
	# Sim and view derive the same play size from the lobby count via the
	# shared base const, so the rendered floor/camera match the scaled arena.
	return MinigameScaling.arena_half(PoisonFeast.ARENA_HALF, names.size())


func _setup_3d() -> void:
	_pot_label = Label.new()
	_pot_label.name = "PotLabel"
	_pot_label.add_theme_font_size_override(&"font_size", 28)
	_pot_label.add_theme_color_override(&"font_color", TIER_COLORS[PoisonFeast.Tier.GOLDEN])
	_pot_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_pot_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_pot_label.position.y = 40.0
	_pot_label.visible = false
	add_child(_pot_label)


func _render_3d(game: Dictionary) -> void:
	players = game.get("players", {})
	dishes = game.get("dishes", [])
	pot = int(game.get("pot", 0))
	_pot_label.visible = pot > 0
	_pot_label.text = "POT: %d — next clean bite takes it!" % pot
	# A clean bite emptied the pot (M13-25): pop a gold burst on the table.
	if _prev_pot > 0 and pot == 0:
		fx_burst(Vector2.ZERO, TIER_COLORS[PoisonFeast.Tier.GOLDEN], 1.0)
		# Signature cue (#728): the whole table hears the pot get claimed.
		play_sfx(&"pop")
	_prev_pot = pot
	_update_players()
	_update_dishes()


func _update_players() -> void:
	for slot: int in players:
		var state: Array = players[slot]
		var rig := rig_for_slot(slot)
		if rig == null:
			continue
		update_rig(slot, Vector2(state[0], state[1]))
		var caption := "%s  %d" % [player_name(slot), int(state[2])]
		var staggered := int(state[3]) == 1
		if staggered:
			caption += "  (poisoned!)"
			if not _staggered.get(slot, false):
				rig.play(&"hit")
				# A sick green puff over whoever just bit poison (M13-25).
				fx_burst(Vector2(state[0], state[1]), POISON_PUFF_COLOR, 1.1)
				# Signature cue (#728): poison is a debuff/stagger, not a
				# generic error — docs/AUDIO_GUIDE.md's `powerdown` names it.
				if slot == my_slot:
					play_sfx(&"powerdown")
					request_shake(6.0)
		elif slot == my_slot and int(state[2]) > _my_score:
			play_sfx(&"coin")
		_staggered[slot] = staggered
		if slot == my_slot:
			_my_score = int(state[2])
		rig.display_name = caption


func _update_dishes() -> void:
	var seen := {}
	for entry: Array in dishes:
		var id := int(entry[0])
		seen[id] = true
		var node: Node3D = _dish_nodes.get(id)
		if node == null:
			node = _build_dish(id, int(entry[3]))
			_dish_tiers[id] = int(entry[3])
		node.position = to_arena(Vector2(float(entry[1]), float(entry[2])))
	for id: int in _dish_nodes.keys():
		if not seen.has(id):
			var node := _dish_nodes[id] as Node3D
			# A dish only leaves the list when eaten: burst it in its tier color.
			var tier: int = _dish_tiers.get(id, PoisonFeast.Tier.CLEAN)
			fx_burst(Vector2(node.position.x, node.position.z), TIER_COLORS[tier], 0.5)
			node.queue_free()
			_dish_nodes.erase(id)
			_dish_tiers.erase(id)


## A bowl with a tier-colored emissive ring under it: the tier must read at
## a glance from the iso camera, the bowl model is shared.
func _build_dish(id: int, tier: int) -> Node3D:
	var root := Node3D.new()
	root.name = "Dish%d" % id
	var bowl: Node3D = DISH_SCENE.instantiate()
	bowl.scale = Vector3.ONE * DISH_SCALE
	root.add_child(bowl)

	var mesh := TorusMesh.new()
	mesh.inner_radius = 0.5
	mesh.outer_radius = 0.75
	var material := StandardMaterial3D.new()
	var color: Color = TIER_COLORS.get(tier, TIER_COLORS[PoisonFeast.Tier.CLEAN])
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color * 0.8
	mesh.material = material
	var ring := MeshInstance3D.new()
	ring.name = "TierRing"
	ring.mesh = mesh
	ring.position.y = RING_HEIGHT
	root.add_child(ring)

	arena.add_child(root)
	_dish_nodes[id] = root
	return root
