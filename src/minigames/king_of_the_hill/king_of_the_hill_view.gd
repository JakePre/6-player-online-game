extends MinigameView3D
## King of the Hill client view (M8-04): renders the replicated arena in the
## shared 2.5D iso-arena (M8-01, MinigameView3D) — players as CharacterRig
## instances (position/facing/walk-idle from the snapshot, points on the
## nameplate), the shrinking scoring zone as a translucent gold disc capping a
## real hill-crest model (#919), and shove-horn/anchor pickups as their own
## shapes rather than colored boxes. Visual enhancements (#1137): gold particle
## fountain rising from the scoring zone, decorative flag rim props around the
## hill perimeter, warm golden-hour mood. Presentation-tier swap only: state
## storage and the render contract are unchanged from the 2D pass (M4-01).

## Declarative button input (#947): use the held pickup (shove / anchor).
const INPUT_ACTIONS := {&"action_primary": "use"}
const ZONE_COLOR := Color(0.96, 0.79, 0.2, 0.35)
const ZONE_ANCHORED_COLOR := Color(0.3, 0.75, 0.95, 0.45)
## Real rock obstacles (#929) instead of grey primitive cylinders. Half-widths
## are each model's horizontal AABB extent / 2 (the #919 probe technique),
## used to scale a rock so its visual footprint matches PILLAR_RADIUS.
const OBSTACLE_ROCK_SCENES: Array[PackedScene] = [
	preload("res://assets/environment/kenney_nature_kit/rock_tallC.glb"),
	preload("res://assets/environment/kenney_nature_kit/rock_tallD.glb"),
]
const OBSTACLE_ROCK_HALF_WIDTHS: Array[float] = [0.2281, 0.2307]
## Held-item label tint only now — the world pickups (#919) read by shape
## (horn vs anchor), not color.
const ITEM_COLORS: Array[Color] = [Color(0.95, 0.4, 0.25), Color(0.3, 0.75, 0.95)]
const ITEM_NAMES: Array[String] = ["SHOVE", "ANCHOR"]
## Unit-radius disc; the node's X/Z scale is the zone radius from the snapshot.
const ZONE_DISC_HEIGHT := 0.04

## Real hill-crest model (#919, MDL-010): a low grassy mound the zone disc
## caps. Base-pivoted (probed AABB: y 0..0.6459, x/z half-width 1.5, matching
## the generated-models convention) — sits at ground level and scales its
## footprint with the zone radius, same treatment the disc already got; the
## disc rides on top of it instead of floating at ground level.
const HILL_CREST_SCENE := preload("res://assets/generated/models/hill-crest.glb")
const HILL_CREST_HALF_WIDTH := 1.5
const HILL_CREST_HEIGHT := 0.6459
## Real item models (#919, MDL-011/012): a shove horn and an anchor, both
## base-pivoted. Shape now carries identity — the pickups no longer need a
## color tint to tell them apart.
const SHOVE_HORN_SCENE := preload("res://assets/generated/models/shove-horn.glb")
const ANCHOR_SCENE := preload("res://assets/generated/models/anchor.glb")
## How long a fired shove's rig animation is protected from update_rig()'s
## walk/idle overwrite (#587) — the same _reaction_hold idiom rumble_ring
## uses for hit/ko, ported here since KotH detects item-use by diffing
## `held` rather than a dedicated event.
const SHOVE_HOLD_SEC := 0.6

## Rim scenery (#813): pines, rocks, and flags ring the grassy hilltop, dressing
## the arena edge via the shared scatter_rim_props helper. Fixed seed so the
## layout is stable and reproducible.
const RIM_PROP_SCENES: Array[PackedScene] = [
	preload("res://assets/environment/kenney_nature_kit/tree_pineRoundA.glb"),
	preload("res://assets/environment/kenney_nature_kit/tree_pineRoundD.glb"),
	preload("res://assets/environment/kenney_nature_kit/rock_smallA.glb"),
	preload("res://assets/environment/kenney_nature_kit/rock_tallA.glb"),
	preload("res://assets/environment/kenney_platformer_kit/flag.glb"),
]
const RIM_PROP_COUNT := 20
const RIM_PROP_SEED := 0x40C
## Gold particle fountain (#1137): gentle rising gold particles from the scoring
## zone, making the hill feel like a reward. Continuous CPUParticles3D, not
## one-shot — the fountain runs as long as the zone is visible.
const FOUNTAIN_AMOUNT := 30
const FOUNTAIN_LIFETIME := 2.0
const FOUNTAIN_SPEED := 2.0
const FOUNTAIN_COLOR := Color(0.96, 0.79, 0.2)
const FOUNTAIN_HEIGHT := 0.8

## Latest replicated state, straight from KingOfTheHill.get_snapshot().
var players := {}
var zone: Array = []
var items: Array = []
var held := {}
var anchored := false

var _zone_node: MeshInstance3D
var _zone_material: StandardMaterial3D
var _hill_crest: Node3D
# M13-03 FX state: zone center for relocation bursts, per-slot points for
# scoring sparkles, snapshot counter for the shimmer throb.
var _zone_center_seen := Vector2.INF
var _points_seen := {}
var _pulse_ticks := 0
var _pillars_built := false
# Pooled (#709): reused across snapshots, hiding surplus instead of freeing.
var _item_nodes: Array[Node3D] = []
var _items: Array = []
var _held_label: Label
## Last-seen held map, for pickup-moment detection (#260).
var _last_held := {}
## Continuous gold particle fountain (#1137): rises from the scoring zone
## center, visible when the zone is active.
var _fountain: CPUParticles3D


func _physics_process(_delta: float) -> void:
	send_move_intent()


## An actual grassy hilltop (#813): tile the arena with the Kenney grass block
## instead of the grey platform, so King of the Hill reads as a green field.
## The block carries its own grass color, so no tint is layered over it.
func _floor_tile_scene() -> PackedScene:
	return preload("res://assets/environment/kenney_platformer_kit/block-grass.glb")


## Warm golden-hour mood (#1137): pushes the party-stadium shell toward a warm
## amber/gold tone, matching the grassy hilltop and gold fountain theme.
func _mood() -> Color:
	return Color(0.2, 0.15, 0.12).lerp(FOUNTAIN_COLOR, 0.25)


## formula-twin — must mirror KingOfTheHill._setup (scaled _play_half). The sim
## derives _play_half = MinigameScaling.arena_half(ARENA_HALF, slots.size());
## this view re-derives the same value. If the scaling formula changes in the
## sim but not here, the rendered floor/camera will mismatch the sim's arena.
func _arena_half() -> float:
	# Grow the framed floor with the lobby to match the sim's scaled play area
	# (M15, ADR 003 F4); at <=6 players this is the tuned KingOfTheHill.ARENA_HALF.
	return MinigameScaling.arena_half(KingOfTheHill.ARENA_HALF, names.size())


func _setup_3d() -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 1.0
	mesh.bottom_radius = 1.0
	mesh.height = ZONE_DISC_HEIGHT
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = ZONE_COLOR
	material.emission_enabled = true
	material.emission = Color(ZONE_COLOR, 1.0)
	material.emission_energy_multiplier = 0.3
	mesh.material = material
	_zone_material = material
	_zone_node = MeshInstance3D.new()
	_zone_node.name = "Zone"
	_zone_node.mesh = mesh
	_zone_node.visible = false
	arena.add_child(_zone_node)
	_hill_crest = HILL_CREST_SCENE.instantiate() as Node3D
	_hill_crest.name = "HillCrest"
	_hill_crest.visible = false
	arena.add_child(_hill_crest)
	# Ring the grassy hilltop with pines and rocks (#813) — the demonstrator for
	# the shared scatter_rim_props helper.
	scatter_rim_props(RIM_PROP_SCENES, RIM_PROP_COUNT, RIM_PROP_SEED)
	# Gold particle fountain (#1137): continuous rising gold particles from the
	# scoring zone, making the hill feel like a reward.
	_fountain = CPUParticles3D.new()
	_fountain.name = "Fountain"
	_fountain.one_shot = false
	_fountain.emitting = false
	_fountain.amount = FOUNTAIN_AMOUNT
	_fountain.lifetime = FOUNTAIN_LIFETIME
	_fountain.color = FOUNTAIN_COLOR
	_fountain.direction = Vector3.UP
	_fountain.spread = 25.0
	_fountain.initial_velocity_min = FOUNTAIN_SPEED * 0.6
	_fountain.initial_velocity_max = FOUNTAIN_SPEED
	_fountain.gravity = Vector3(0.0, 1.5, 0.0)
	_fountain.scale_amount_min = 0.5
	_fountain.scale_amount_max = 1.5
	_fountain.hue_variation_min = 0.0
	_fountain.hue_variation_max = 0.05
	var fountain_mesh := SphereMesh.new()
	fountain_mesh.radius = 0.06
	fountain_mesh.height = 0.12
	_fountain.mesh = fountain_mesh
	arena.add_child(_fountain)
	# Held-item indicator for the local player (#139), on the always-on-top
	# banner layer (#258).
	_held_label = make_banner(&"HeldItem")


## Pillars are static per round; built once from the first snapshot carrying
## them (#139). Real rocks (#929) instead of grey primitive cylinders —
## base-pivoted like the item pickups, scaled per-model so the visual
## footprint matches PL_RADIUS.
func _build_pillars(pillar_list: Array) -> void:
	_pillars_built = true
	for i in pillar_list.size():
		var pillar: Array = pillar_list[i]
		var variant := i % OBSTACLE_ROCK_SCENES.size()
		var rock := OBSTACLE_ROCK_SCENES[variant].instantiate() as Node3D
		rock.scale = (
			Vector3.ONE
			* (float(pillar[KingOfTheHill.PL_RADIUS]) / OBSTACLE_ROCK_HALF_WIDTHS[variant])
		)
		rock.position = to_arena(
			Vector2(float(pillar[KingOfTheHill.PL_X]), float(pillar[KingOfTheHill.PL_Y])), 0.0
		)
		arena.add_child(rock)


func _render_3d(game: Dictionary) -> void:
	players = game.get("players", {})
	zone = game.get("zone", [])
	items = game.get("items", [])
	held = game.get("held", {})
	anchored = bool(game.get("anchored", false))
	if not _pillars_built and game.has("pillars"):
		_build_pillars(game.pillars)
	_zone_material.albedo_color = ZONE_ANCHORED_COLOR if anchored else ZONE_COLOR
	_update_items()
	_update_held()
	_update_players()
	_update_zone()


func _update_items() -> void:
	_items = items
	sync_pool(_item_nodes, items.size(), _make_item, _place_item)


## Both real models ride the same pool node (#919), one visible at a time —
## `sync_pool` reuses a node's factory across any index, so a slot that was a
## horn one spawn can be an anchor the next; toggling visibility avoids
## rebuilding the node every time an item's type changes.
func _make_item() -> Node3D:
	var root := Node3D.new()
	var horn := SHOVE_HORN_SCENE.instantiate()
	horn.name = "Horn"
	root.add_child(horn)
	var anchor := ANCHOR_SCENE.instantiate()
	anchor.name = "Anchor"
	root.add_child(anchor)
	return root


func _place_item(node: Node3D, index: int) -> void:
	var item: Array = _items[index]
	var kind := clampi(int(item[KingOfTheHill.IT_TYPE]), 0, 1)
	(node.get_node("Horn") as Node3D).visible = kind == KingOfTheHill.Item.SHOVE
	(node.get_node("Anchor") as Node3D).visible = kind == KingOfTheHill.Item.ANCHOR
	# Base-pivoted models sit right on the ground, unlike the old floating box.
	node.position = to_arena(
		Vector2(float(item[KingOfTheHill.IT_X]), float(item[KingOfTheHill.IT_Y])), 0.0
	)


## Pickup flash + sound so grabbing reads (#260), plus a shove animation on
## the rig the instant a held Shove Blast fires (#587): the item clearing
## from `held` while it was SHOVE is the use-moment (no dedicated "used"
## event in the snapshot).
func _update_held_feedback() -> void:
	for slot: int in held:
		if not _last_held.has(slot) and slot == my_slot:
			# A weapon/buff pickup (#728, docs/AUDIO_GUIDE.md), not currency.
			play_sfx(&"powerup")
	for slot: int in _last_held:
		if held.has(slot):
			continue
		if int(_last_held[slot]) != KingOfTheHill.Item.SHOVE:
			continue
		var rig := rig_for_slot(slot)
		if rig != null:
			# The rig owns its own flourish hold now (#942); update_rig keeps
			# the pose while stationary and yields to walk the moment it moves.
			rig.play_protected(&"interact", SHOVE_HOLD_SEC)
	_last_held = held.duplicate()


func _update_held() -> void:
	_update_held_feedback()
	if _held_label == null:
		return
	if held.has(my_slot):
		var item := clampi(int(held[my_slot]), 0, 1)
		# Device-aware (#844): was a hardcoded "Space / Ⓐ" both-scheme string;
		# now shows only the active device's binding, live on remap/device change
		# (this label rebuilds every snapshot render, so no extra signal needed).
		_held_label.text = (
			"%s — press %s" % [ITEM_NAMES[item], InputGlyphs.glyph_for(&"action_primary")]
		)
		_held_label.modulate = ITEM_COLORS[item]
	else:
		_held_label.text = ""


func _update_players() -> void:
	for slot: int in players:
		var state: Array = players[slot]
		var rig := rig_for_slot(slot)
		if rig == null:
			continue
		# The shove flourish plays out while the player stands still (#587) but
		# never stalls movement (#800): the rig's own play_protected hold does
		# both structurally now (#942), so this is a plain update_rig call.
		update_rig(slot, Vector2(state[KingOfTheHill.PS_X], state[KingOfTheHill.PS_Y]))
		rig.display_name = "%s  %d" % [player_name(slot), int(state[KingOfTheHill.PS_POINTS])]
		# Scoring sparkles (M13-03): points ticking up while holding the hill
		# shed a sparkle in the scorer's color. Seeded via _points_seen.
		var points := int(state[KingOfTheHill.PS_POINTS])
		if _points_seen.has(slot) and points > int(_points_seen[slot]):
			fx_sparkle(
				Vector2(state[KingOfTheHill.PS_X], state[KingOfTheHill.PS_Y]), player_color(slot)
			)
			# A tick-up while holding the hill (POINTS_PER_SEC=2, so at most
			# 2 Hz — never a machine-gun) — a small satisfying consume (#728).
			if slot == my_slot:
				play_sfx(&"pop")
		_points_seen[slot] = points


func _update_zone() -> void:
	var zone_visible := zone.size() == KingOfTheHill.ZN_COUNT
	_zone_node.visible = zone_visible
	_hill_crest.visible = zone_visible
	# Gold fountain (#1137): emit only when the zone is visible and motion
	# is not reduced; position syncs with the zone center below.
	if _fountain != null:
		_fountain.emitting = zone_visible and not ArenaFX.reduced_motion
	if not zone_visible:
		return
	# Shimmer throb + relocation FX (M13-03): the disc breathes on a snapshot
	# cadence, and the zone jumping fires a burst where it was + dust where it
	# lands (seeded on the first sighting).
	_pulse_ticks += 1
	_zone_material.emission_energy_multiplier = 0.3 + 0.15 * sin(_pulse_ticks * TAU / 16.0)
	var center := Vector2(zone[KingOfTheHill.ZN_X], zone[KingOfTheHill.ZN_Y])
	if _zone_center_seen != Vector2.INF and _zone_center_seen.distance_to(center) > 0.5:
		fx_burst(_zone_center_seen, ZONE_COLOR, 0.3)
		fx_dust(center)
	_zone_center_seen = center
	# The sim never shrinks below ZONE_MIN_RADIUS; the floor only guards a
	# malformed snapshot from producing a degenerate (zero-scale) basis.
	var radius := maxf(float(zone[KingOfTheHill.ZN_RADIUS]), 0.001)
	# The disc caps the hill crest (#919) instead of floating at ground level —
	# same footprint scaling the disc already used, now shared with the model.
	_zone_node.position = to_arena(center, HILL_CREST_HEIGHT + ZONE_DISC_HEIGHT / 2.0)
	_zone_node.scale = Vector3(radius, 1.0, radius)
	_hill_crest.position = to_arena(center, 0.0)
	var crest_scale := radius / HILL_CREST_HALF_WIDTH
	_hill_crest.scale = Vector3(crest_scale, 1.0, crest_scale)
	# Gold fountain (#1137): rises from the crest top above the zone disc.
	if _fountain != null:
		_fountain.position = to_arena(center, HILL_CREST_HEIGHT + FOUNTAIN_HEIGHT)
		_fountain.scale = Vector3(crest_scale * 0.5, 1.0, crest_scale * 0.5)
