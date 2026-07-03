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

## Latest replicated state, straight from PoisonFeast.get_snapshot().
var players := {}
var dishes: Array = []
var pot := 0

var _dish_nodes := {}  # id (int) -> Node3D
var _pot_label: Label
var _staggered := {}  # slot (int) -> bool, for one-shot flinches
var _my_score := 0


func _physics_process(_delta: float) -> void:
	send_move_intent()


func _arena_half() -> float:
	return PoisonFeast.ARENA_HALF


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
				if slot == my_slot:
					play_sfx(&"error")
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
		node.position = to_arena(Vector2(float(entry[1]), float(entry[2])))
	for id: int in _dish_nodes.keys():
		if not seen.has(id):
			(_dish_nodes[id] as Node3D).queue_free()
			_dish_nodes.erase(id)


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
