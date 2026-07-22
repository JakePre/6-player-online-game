extends MinigameView3D
## Poison Feast client view (reworked per #174, on the M8-01 MinigameView3D
## tier): the push-your-luck banquet. Dishes are Kenney food-kit models with a
## tier-colored glow ring under them — white (clean), orange (spiced, 1-in-4
## poisoned), purple (delicacy, 1-in-2), gold (final course). The pot rides a
## Control-layer banner; staggered eaters flinch, slow, and show it on their
## nameplate. Whether a specific dish is poisoned never reaches the client —
## tiers are the odds, the bite is the gamble.
##
## GFX enhancements (#1150): banquet table with tablecloth, chairs, candelabras,
## food variety across tiers, goblet pickups, wall banners, rim props, and a
## warm dining mood.

const DISH_SCALE := 2.0
const RING_HEIGHT := 0.05

# --- Food variety per tier (#1150) -------------------------------------------
## Each tier draws from a different set of Kenney food-kit models so the
## risk tier reads at a glance even before the ring color registers.
const TIER_FOOD_SCENES := {
	PoisonFeast.Tier.CLEAN:
	[
		preload("res://assets/environment/kenney_food_kit/bowl-soup.glb"),
		preload("res://assets/environment/kenney_food_kit/bread.glb"),
		preload("res://assets/environment/kenney_food_kit/cheese.glb"),
	],
	PoisonFeast.Tier.SPICED:
	[
		preload("res://assets/environment/kenney_food_kit/taco.glb"),
		preload("res://assets/environment/kenney_food_kit/pepper.glb"),
		preload("res://assets/environment/kenney_food_kit/hot-dog.glb"),
	],
	PoisonFeast.Tier.DELICACY:
	[
		preload("res://assets/environment/kenney_food_kit/cake.glb"),
		preload("res://assets/environment/kenney_food_kit/sundae.glb"),
		preload("res://assets/environment/kenney_food_kit/waffle.glb"),
		preload("res://assets/environment/kenney_food_kit/pancakes.glb"),
	],
	PoisonFeast.Tier.GOLDEN:
	[
		preload("res://assets/environment/kenney_food_kit/turkey.glb"),
		preload("res://assets/environment/kenney_food_kit/cake-birthday.glb"),
		preload("res://assets/environment/kenney_food_kit/pizza.glb"),
	],
}

# --- Table dressing (#1150) --------------------------------------------------
## Table surface sits at this height — dishes are placed on top, players
## walk around the floor.
const TABLE_HEIGHT := 0.7
const TABLE_THICKNESS := 0.08
const TABLE_LEG_RADIUS := 0.06
const TABLE_LEG_INSET := 0.3
## Tablecloth overhang past the tabletop edge.
const TABLECLOTH_OVERHANG := 0.15
## Chair dimensions around the banquet table.
const CHAIR_SEAT_H := 0.35
const CHAIR_BACK_H := 0.3
const CHAIR_SEAT_W := 0.25
const CHAIR_SEAT_D := 0.25
const CHAIR_LEG_RADIUS := 0.025
## Candelabra at each end of the table.
const CANDELABRA_HEIGHT := 0.25
const CANDELABRA_RADIUS := 0.035
const FLAME_RADIUS := 0.055
## Goblet decorations on the table.
const GOBLET_COUNT := 6
## Wall banners hung from the arena perimeter walls.
const BANNER_COUNT := 6
## Rim props from the nature kit for a banquet-hall garden feel.
const RIM_PROP_SCENES: Array[PackedScene] = [
	preload("res://assets/environment/kenney_nature_kit/plant_flatTall.glb"),
	preload("res://assets/environment/kenney_nature_kit/plant_bushSmall.glb"),
	preload("res://assets/environment/kenney_nature_kit/plant_bushTriangle.glb"),
	preload("res://assets/environment/kenney_nature_kit/tree_cone_dark.glb"),
]
const RIM_PROP_COUNT := 16
const RIM_PROP_SEED := 0x1150
## Goblet decoration models.
const GOBLET_SCENES: Array[PackedScene] = [
	preload("res://assets/environment/kenney_food_kit/cup.glb"),
	preload("res://assets/environment/kenney_food_kit/glass.glb"),
	preload("res://assets/environment/kenney_food_kit/soda-glass.glb"),
	preload("res://assets/environment/kenney_food_kit/glass-wine.glb"),
	preload("res://assets/environment/kenney_food_kit/cup-tea.glb"),
]

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


## Warm dining-hall mood for the backdrop (#1150): a rich dark burgundy/amber
## tone that feels like a candlelit banquet.
func _mood() -> Color:
	return Color(0.2, 0.12, 0.08).lerp(Color(0.45, 0.25, 0.12), 0.3)


func _arena_half() -> float:
	# Sim and view derive the same play size from the lobby count via the
	# shared base const, so the rendered floor/camera match the scaled arena.
	return MinigameScaling.arena_half(PoisonFeast.ARENA_HALF, names.size())


func _setup_3d() -> void:
	_pot_label = make_status_label(&"PotLabel")
	_pot_label.add_theme_color_override(&"font_color", TIER_COLORS[PoisonFeast.Tier.GOLDEN])
	# #924: preserves the original +24px offset below the framework baseline
	# (was 40.0 against the pre-fix 16.0 default), now relative so it still
	# clears the chrome.
	_pot_label.position.y = MinigameView3D.CHROME_CLEARANCE_Y + 24.0
	_pot_label.visible = false

	# GFX enhancements (#1150).
	_build_table()
	_build_chairs()
	_build_candelabras()
	_build_goblets()
	_build_banners()
	scatter_rim_props(RIM_PROP_SCENES, RIM_PROP_COUNT, RIM_PROP_SEED)


## Banquet table spanning the arena (#1150): a long rectangular tabletop with
## four legs, a tablecloth, and dishes placed on top. The table sits at
## TABLE_HEIGHT so players walk around on the floor while dishes appear on
## the table.
func _build_table() -> void:
	var half := _arena_half()
	var table_len := half * 1.4
	var table_wid := half * 0.5

	# Tabletop.
	var top_mesh := BoxMesh.new()
	top_mesh.size = Vector3(table_len, TABLE_THICKNESS, table_wid)
	var top_mat := StandardMaterial3D.new()
	top_mat.albedo_color = Color(0.45, 0.28, 0.15)
	top_mat.metallic = 0.1
	top_mat.roughness = 0.8
	top_mesh.material = top_mat
	var top_node := MeshInstance3D.new()
	top_node.name = "TableTop"
	top_node.mesh = top_mesh
	top_node.position.y = TABLE_HEIGHT
	arena.add_child(top_node)

	# Four legs.
	for corner in [[-1, -1], [-1, 1], [1, -1], [1, 1]]:
		var leg_mesh := CylinderMesh.new()
		leg_mesh.top_radius = TABLE_LEG_RADIUS
		leg_mesh.bottom_radius = TABLE_LEG_RADIUS
		leg_mesh.height = TABLE_HEIGHT
		var leg_mat := StandardMaterial3D.new()
		leg_mat.albedo_color = Color(0.35, 0.22, 0.12)
		leg_mat.metallic = 0.05
		leg_mat.roughness = 0.9
		leg_mesh.material = leg_mat
		var leg_node := MeshInstance3D.new()
		leg_node.name = "TableLeg_%d_%d" % corner
		leg_node.mesh = leg_mesh
		leg_node.position = Vector3(
			corner[0] * (table_len * 0.5 - TABLE_LEG_INSET),
			TABLE_HEIGHT * 0.5,
			corner[1] * (table_wid * 0.5 - TABLE_LEG_INSET)
		)
		arena.add_child(leg_node)

	# Tablecloth: a slightly larger plane draped over the tabletop.
	var cloth_mesh := PlaneMesh.new()
	cloth_mesh.size = Vector2(
		table_len + TABLECLOTH_OVERHANG * 2, table_wid + TABLECLOTH_OVERHANG * 2
	)
	var cloth_mat := StandardMaterial3D.new()
	cloth_mat.albedo_color = Color(0.85, 0.75, 0.6)
	cloth_mat.metallic = 0.0
	cloth_mat.roughness = 0.95
	# Subtle diamond pattern via UV jitter (not a real texture, but reads as
	# a textured cloth at game distance).
	cloth_mat.uv1_scale = Vector3(3.0, 3.0, 1.0)
	cloth_mesh.material = cloth_mat
	var cloth_node := MeshInstance3D.new()
	cloth_node.name = "Tablecloth"
	cloth_node.mesh = cloth_mesh
	cloth_node.position.y = TABLE_HEIGHT + TABLE_THICKNESS * 0.5 + 0.005
	cloth_node.rotation.x = -PI / 2.0
	arena.add_child(cloth_node)


## Chairs around the banquet table (#1150): small boxy chairs placed evenly
## around the table perimeter, modeling the banquet-hall setting.
func _build_chairs() -> void:
	var half := _arena_half()
	var table_len := half * 1.4
	var table_wid := half * 0.5
	var chair_count := maxi(8, names.size() + 2)
	var chair_dist := table_len * 0.5 + 0.45

	for i in chair_count:
		var angle := TAU * float(i) / float(chair_count)
		# Alternate between long-side and short-side placement.
		var side_len := table_len * 0.5 + 0.35
		var side_wid := table_wid * 0.5 + 0.35
		var x := cos(angle) * side_len
		var z := sin(angle) * side_wid
		# Clamp to oval-ish ring around the table.
		var ratio := table_len / maxf(table_wid, 0.01)
		var nx := cos(angle) * chair_dist
		var nz := sin(angle) * (chair_dist / ratio)
		# Build the chair.
		_build_single_chair(Vector3(nx, 0.0, nz), angle + PI)


## A single chair at the given position, facing away from the table.
func _build_single_chair(pos: Vector3, facing: float) -> void:
	var root := Node3D.new()
	root.name = "Chair"
	root.position = pos
	root.rotation.y = facing

	# Seat.
	var seat_mesh := BoxMesh.new()
	seat_mesh.size = Vector3(CHAIR_SEAT_W, 0.04, CHAIR_SEAT_D)
	var seat_mat := StandardMaterial3D.new()
	seat_mat.albedo_color = Color(0.4, 0.25, 0.12)
	seat_mat.metallic = 0.0
	seat_mat.roughness = 0.9
	seat_mesh.material = seat_mat
	var seat_node := MeshInstance3D.new()
	seat_node.name = "Seat"
	seat_node.mesh = seat_mesh
	seat_node.position.y = CHAIR_SEAT_H
	root.add_child(seat_node)

	# Backrest.
	var back_mesh := BoxMesh.new()
	back_mesh.size = Vector3(CHAIR_SEAT_W, CHAIR_BACK_H, 0.03)
	var back_mat := StandardMaterial3D.new()
	back_mat.albedo_color = Color(0.4, 0.25, 0.12)
	back_mat.metallic = 0.0
	back_mat.roughness = 0.9
	back_mesh.material = back_mat
	var back_node := MeshInstance3D.new()
	back_node.name = "Back"
	back_node.mesh = back_mesh
	back_node.position = Vector3(0.0, CHAIR_SEAT_H + CHAIR_BACK_H * 0.5, -CHAIR_SEAT_D * 0.5)
	root.add_child(back_node)

	# Four legs.
	for corner in [[-1, -1], [-1, 1], [1, -1], [1, 1]]:
		var leg_mesh := CylinderMesh.new()
		leg_mesh.top_radius = CHAIR_LEG_RADIUS
		leg_mesh.bottom_radius = CHAIR_LEG_RADIUS
		leg_mesh.height = CHAIR_SEAT_H
		var leg_mat := StandardMaterial3D.new()
		leg_mat.albedo_color = Color(0.3, 0.18, 0.08)
		leg_mat.metallic = 0.0
		leg_mat.roughness = 0.9
		leg_mesh.material = leg_mat
		var leg_node := MeshInstance3D.new()
		leg_node.name = "Leg_%d_%d" % corner
		leg_node.mesh = leg_mesh
		leg_node.position = Vector3(
			corner[0] * CHAIR_SEAT_W * 0.35, CHAIR_SEAT_H * 0.5, corner[1] * CHAIR_SEAT_D * 0.35
		)
		root.add_child(leg_node)

	arena.add_child(root)


## Candelabras at each end of the banquet table (#1150): a thin pole with
## an emissive flame sphere.
func _build_candelabras() -> void:
	var half := _arena_half()
	var table_len := half * 1.4
	for end_x in [-1, 1]:
		var pos := Vector3(end_x * (table_len * 0.5 + 0.15), TABLE_HEIGHT + TABLE_THICKNESS, 0.0)

		# Pole.
		var pole_mesh := CylinderMesh.new()
		pole_mesh.top_radius = CANDELABRA_RADIUS
		pole_mesh.bottom_radius = CANDELABRA_RADIUS
		pole_mesh.height = CANDELABRA_HEIGHT
		var pole_mat := StandardMaterial3D.new()
		pole_mat.albedo_color = Color(0.9, 0.85, 0.7)
		pole_mat.metallic = 0.6
		pole_mat.roughness = 0.3
		pole_mesh.material = pole_mat
		var pole_node := MeshInstance3D.new()
		pole_node.name = "CandelabraPole_%d" % (1 if end_x > 0 else 0)
		pole_node.mesh = pole_mesh
		pole_node.position = pos + Vector3(0.0, CANDELABRA_HEIGHT * 0.5, 0.0)
		arena.add_child(pole_node)

		# Flame.
		var flame_mesh := SphereMesh.new()
		flame_mesh.radius = FLAME_RADIUS
		flame_mesh.height = FLAME_RADIUS * 2.0
		var flame_mat := StandardMaterial3D.new()
		flame_mat.albedo_color = Color(1.0, 0.7, 0.2)
		flame_mat.emission_enabled = true
		flame_mat.emission = Color(1.0, 0.5, 0.1)
		flame_mesh.material = flame_mat
		var flame_node := MeshInstance3D.new()
		flame_node.name = "CandelabraFlame_%d" % (1 if end_x > 0 else 0)
		flame_node.mesh = flame_mesh
		flame_node.position = pos + Vector3(0.0, CANDELABRA_HEIGHT, 0.0)
		arena.add_child(flame_node)


## Decorative goblets scattered on the banquet table (#1150): small cup/glass
## models placed along the table center.
func _build_goblets() -> void:
	var half := _arena_half()
	var table_len := half * 1.4
	var table_wid := half * 0.5
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x1150
	for i in GOBLET_COUNT:
		var scene := GOBLET_SCENES[rng.randi() % GOBLET_SCENES.size()]
		var goblet := scene.instantiate() as Node3D
		if goblet == null:
			continue
		goblet.name = "Goblet%d" % i
		# Place along the table center line, slightly offset from dishes.
		var x := rng.randf_range(-table_len * 0.4, table_len * 0.4)
		var z := rng.randf_range(-table_wid * 0.35, table_wid * 0.35)
		goblet.position = Vector3(x, TABLE_HEIGHT + TABLE_THICKNESS, z)
		goblet.scale = Vector3.ONE * 0.8
		arena.add_child(goblet)


## Wall banners hung from the arena perimeter (#1150): vertical colored planes
## with a warm accent, alternating between two banner colors.
func _build_banners() -> void:
	var half := _arena_half()
	var banner_h := 1.6
	var banner_w := 0.5
	var banner_y := 1.0
	var spacing := half * 2.0 / float(BANNER_COUNT + 1)

	for side in [-1, 1]:
		for i in BANNER_COUNT:
			var x := -half + spacing * (i + 1)
			var color := Color(0.6, 0.15, 0.1) if i % 2 == 0 else Color(0.5, 0.25, 0.08)

			var mesh := PlaneMesh.new()
			mesh.size = Vector2(banner_w, banner_h)
			var mat := StandardMaterial3D.new()
			mat.albedo_color = color
			mat.metallic = 0.0
			mat.roughness = 0.8
			mesh.material = mat

			var node := MeshInstance3D.new()
			node.name = "Banner_%d_%d" % [side, i]
			node.mesh = mesh
			node.position = Vector3(x, banner_y, side * half)
			if side > 0:
				node.rotation.y = PI
			arena.add_child(node)


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
		update_rig(slot, Vector2(state[PoisonFeast.PS_X], state[PoisonFeast.PS_Y]))
		var caption := "%s  %d" % [player_name(slot), int(state[PoisonFeast.PS_SCORE])]
		var staggered := int(state[PoisonFeast.PS_STAGGERED]) == 1
		if staggered:
			caption += "  (poisoned!)"
			if not _staggered.get(slot, false):
				rig.play(&"hit")
				# A sick green puff over whoever just bit poison (M13-25).
				fx_burst(
					Vector2(state[PoisonFeast.PS_X], state[PoisonFeast.PS_Y]),
					POISON_PUFF_COLOR,
					1.1
				)
				# Signature cue (#728): poison is a debuff/stagger, not a
				# generic error — docs/AUDIO_GUIDE.md's `powerdown` names it.
				if slot == my_slot:
					play_sfx(&"powerdown")
					request_shake(6.0)
		elif slot == my_slot and int(state[PoisonFeast.PS_SCORE]) > _my_score:
			play_sfx(&"coin")
		_staggered[slot] = staggered
		if slot == my_slot:
			_my_score = int(state[PoisonFeast.PS_SCORE])
		rig.display_name = caption


func _update_dishes() -> void:
	var seen := {}
	for entry: Array in dishes:
		var id := int(entry[PoisonFeast.DL_ID])
		seen[id] = true
		var node: Node3D = _dish_nodes.get(id)
		if node == null:
			node = _build_dish(id, int(entry[PoisonFeast.DL_TIER]))
			_dish_tiers[id] = int(entry[PoisonFeast.DL_TIER])
		# Raise dishes to the table surface height (#1150).
		node.position = to_arena(
			Vector2(float(entry[PoisonFeast.DL_X]), float(entry[PoisonFeast.DL_Y])),
			TABLE_HEIGHT + TABLE_THICKNESS
		)
	for id: int in _dish_nodes.keys():
		if not seen.has(id):
			var node := _dish_nodes[id] as Node3D
			# A dish only leaves the list when eaten: burst it in its tier color.
			var tier: int = _dish_tiers.get(id, PoisonFeast.Tier.CLEAN)
			fx_burst(Vector2(node.position.x, node.position.z), TIER_COLORS[tier], 0.5)
			node.queue_free()
			_dish_nodes.erase(id)
			_dish_tiers.erase(id)


## A dish with a tier-colored emissive ring under it: the tier must read at
## a glance from the iso camera. The food model varies by tier (#1150) so
## the risk level is visible even before the ring color registers.
func _build_dish(id: int, tier: int) -> Node3D:
	var root := Node3D.new()
	root.name = "Dish%d" % id

	# Select a food model from the tier's variety (#1150), seeded by the dish
	# id so the same dish always gets the same model.
	var scenes: Array = TIER_FOOD_SCENES.get(tier, TIER_FOOD_SCENES[PoisonFeast.Tier.CLEAN])
	var scene := scenes[id % scenes.size()] as PackedScene
	var food: Node3D = scene.instantiate()
	food.scale = Vector3.ONE * DISH_SCALE
	root.add_child(food)

	# Tier-colored emissive ring.
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
