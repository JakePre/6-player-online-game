extends MinigameView3D
## Coin Scramble client view (M8-03): renders the replicated arena in the
## shared 2.5D iso-arena (M8-01, MinigameView3D) — players as CharacterRig
## instances (position/facing/walk-idle driven by the snapshot, coin count on
## the nameplate), coins as upright spinning gold coin models (coin-gold.glb)
## that bob and drop-in so they read at camera distance (#209, #1130). Visual
## enhancements: rim props, treasure chest burst, stone-pavers floor texture,
## warm mood theme. Presentation-tier swap only: state storage and the render
## contract are unchanged from the 2D pass (M3-06).

const COIN_COLOR := Color(1.0, 0.84, 0.25)
const COIN_RADIUS := 0.38
const COIN_HEIGHT := 0.1
const COIN_HOVER := 0.45
const COIN_SPIN_HZ := 0.8
const COIN_BOB := 0.08
## 3D coin model (#1130): swap from CylinderMesh disc to the Kenney gold coin
## model so coins read as real objects, not flat primitives.
const COIN_MODEL := preload("res://assets/environment/kenney_platformer_kit/coin-gold.glb")
## Treasure chest (#1130): periodic burst of coins from center, visual spectacle.
const CHEST_MODEL := preload("res://assets/environment/kenney_platformer_kit/chest.glb")
const CHEST_BURST_INTERVAL := 3.5
const CHEST_BURST_HEIGHT := 1.5
## Rim scenery (#1130): barrels, crates, and flowers ring the plaza edge via
## the shared scatter_rim_props helper. Fixed seed for a reproducible layout.
const RIM_PROP_SCENES: Array[PackedScene] = [
	preload("res://assets/environment/kenney_platformer_kit/barrel.glb"),
	preload("res://assets/environment/kenney_platformer_kit/crate.glb"),
	preload("res://assets/environment/kenney_platformer_kit/flowers.glb"),
	preload("res://assets/environment/kenney_platformer_kit/rocks.glb"),
]
const RIM_PROP_COUNT := 20
const RIM_PROP_SEED := 0x1130
## Floor texture (#1130): stone-pavers for a warm plaza feel, replacing the
## default grey platform tint.
const FLOOR_TEXTURE := preload("res://assets/generated/textures/stone-pavers.png")
const FLOOR_TILES := 6.0

## Sky-drop spawn presentation (#781): a fresh coin falls from height and
## settles with a slight overshoot instead of popping into existence.
## STYLE_GUIDE.md's Motion section calls out TRANS_OVERSHOOT (back-out) as
## reserved for playful pop-ins "(podium, coins)" at DUR_SLOW (0.4s).
const COIN_DROP_HEIGHT := 4.0
const COIN_DROP_SEC := 0.4

## Latest replicated state, straight from CoinScramble.get_snapshot().
var players := {}
var coins: Array = []

var _coin_nodes: Array[Node3D] = []
var _chest_node: Node3D
var _chest_timer: Timer
# M13-02 FX seeding: per-slot coin counts, last coin layout, and whether a
# coin pass ran yet (the counts dict fills earlier in the same render, so it
# cannot double as the seed flag).
var _counts_seen := {}
var _coins_seen: Array = []
var _coins_rendered_once := false
# Sky-drop (#781): per-`coins`-index freshness this snapshot, and the wall
# time each pooled node last started dropping (parallel to _coin_nodes,
# stale/default entries read as "already landed" — see _process).
var _coin_fresh: Array[bool] = []
var _coin_drop_start: Array[float] = []


func _physics_process(_delta: float) -> void:
	send_move_intent()


## Spin and bob the coins; phase comes from wall time so the per-snapshot
## node rebuild in _update_coins never resets the motion.
func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	var spin := now * TAU * COIN_SPIN_HZ
	for i in _coin_nodes.size():
		var node := _coin_nodes[i]
		# Pooled surplus (#709) is hidden, not freed — don't animate it.
		if not node.visible:
			continue
		node.rotation = Vector3(PI / 2.0, spin + i, 0.0)
		var rest_y := COIN_HOVER + sin(now * 2.0 + i) * COIN_BOB
		var drop_t := 1.0
		if i < _coin_drop_start.size():
			drop_t = clampf((now - _coin_drop_start[i]) / COIN_DROP_SEC, 0.0, 1.0)
		if drop_t < 1.0:
			node.position.y = lerpf(COIN_HOVER + COIN_DROP_HEIGHT, rest_y, _ease_out_back(drop_t))
		else:
			node.position.y = rest_y


## Standard easeOutBack: overshoots past 1.0 before settling — the "playful
## pop-in" curve STYLE_GUIDE.md names coins for (TRANS_OVERSHOOT/back-out).
static func _ease_out_back(t: float) -> float:
	const C1 := 1.70158
	const C3 := C1 + 1.0
	var p := t - 1.0
	return 1.0 + C3 * p * p * p + C1 * p * p


## Warm gold floor to match the coin-grab theme (#589).
func _floor_tint() -> Color:
	return Color(1.0, 0.94, 0.78)


## Warm amber/gold mood for the party-stadium shell (#1130): pushes the
## dusk base toward the coin-gold theme so the backdrop, ring, and crowd
## all read as a warm plaza evening.
func _mood() -> Color:
	return Color(0.2, 0.15, 0.12).lerp(COIN_COLOR, 0.35)


func _arena_half() -> float:
	# Sim and view derive the same play size from the lobby count via the shared
	# base const, so the rendered floor/camera match the scaled arena (M15).
	return MinigameScaling.arena_half(CoinScramble.ARENA_HALF, names.size())


## Stone-pavers floor texture (#1130): replaces the default grey platform tint
## with a warm stone plaza feel, matching the market-plaza coin-scramble theme.
func _build_floor() -> void:
	var half := _arena_half()
	var surface_mesh := PlaneMesh.new()
	surface_mesh.size = Vector2(half * 2.0, half * 2.0)
	var surface_material := StandardMaterial3D.new()
	surface_material.albedo_texture = FLOOR_TEXTURE
	surface_material.uv1_scale = Vector3(FLOOR_TILES, FLOOR_TILES, 1.0)
	surface_mesh.material = surface_material
	var surface := MeshInstance3D.new()
	surface.name = "Floor"
	surface.mesh = surface_mesh
	surface.position = to_arena(Vector2.ZERO, 0.01)
	arena.add_child(surface)


func _setup_3d() -> void:
	# Chest at center (#1130): periodically bursts coins outward.
	_chest_node = CHEST_MODEL.instantiate() as Node3D
	_chest_node.name = "Chest"
	_chest_node.position = to_arena(Vector2.ZERO, 0.0)
	arena.add_child(_chest_node)
	_chest_timer = Timer.new()
	_chest_timer.name = "ChestTimer"
	_chest_timer.wait_time = CHEST_BURST_INTERVAL
	_chest_timer.one_shot = false
	_chest_timer.timeout.connect(_on_chest_burst)
	add_child(_chest_timer)
	_chest_timer.start()
	# Ring the plaza with barrels, crates, and flowers (#1130) — themed
	# rim props for the coin-scramble market-plaza feel.
	scatter_rim_props(RIM_PROP_SCENES, RIM_PROP_COUNT, RIM_PROP_SEED)


## Periodic coin burst from the treasure chest (#1130): gold coins erupt
## from the center chest, creating spectacle and reinforcing the coin theme.
func _on_chest_burst() -> void:
	fx_burst(Vector2.ZERO, COIN_COLOR, CHEST_BURST_HEIGHT)


func _render_3d(game: Dictionary) -> void:
	players = game.get("players", {})
	coins = game.get("coins", [])
	_update_players()
	_update_coins()


func _update_players() -> void:
	for slot: int in players:
		var state: Array = players[slot]
		var rig := rig_for_slot(slot)
		if rig == null:
			continue
		update_rig(slot, Vector2(state[CoinScramble.PS_X], state[CoinScramble.PS_Y]))
		rig.display_name = "%s  %d" % [player_name(slot), int(state[CoinScramble.PS_COLLECTED])]
		# Pickup sparkle (M13-02): the count ticking up flashes the collector.
		# Bump scatter (#587): a bumped player's count drops (SPEC: the sim
		# scatters 20% of their haul) — burst the coins outward from them for
		# clarity + spectacle, distinct from the calm pickup sparkle.
		var count := int(state[CoinScramble.PS_COLLECTED])
		if _counts_seen.has(slot):
			var before := int(_counts_seen[slot])
			if count > before:
				var at := Vector2(state[CoinScramble.PS_X], state[CoinScramble.PS_Y])
				fx_sparkle(at, player_color(slot))
				# Coin burst (#781): a gold burst distinct from the bump-scatter's
				# player-colored one below, so "gained" and "lost" read apart.
				fx_burst(at, COIN_COLOR)
				if slot == my_slot:
					play_sfx(&"coin")
			elif count < before:
				fx_burst(
					Vector2(state[CoinScramble.PS_X], state[CoinScramble.PS_Y]), player_color(slot)
				)
				# Signature cue (#728): a bump scatter, not an error/rejection —
				# docs/AUDIO_GUIDE.md's `bump` meaning names this exact event.
				if slot == my_slot:
					play_sfx(&"bump")
		_counts_seen[slot] = count


func _update_coins() -> void:
	# Spawn drop-ins (M13-02, #781): a coin at a position we have not seen
	# before just rained in - dust where it lands, and (below, via
	# _coin_fresh) it visibly falls into place instead of popping in. Value-
	# matched against last snapshot, not index, since a coin's array index
	# shifts whenever an earlier coin is collected (Array.remove_at).
	_coin_fresh.resize(coins.size())
	for i in coins.size():
		var coin: Array = coins[i]
		var fresh := true
		for old: Array in _coins_seen:
			if (
				absf(float(old[CoinScramble.CO_X]) - float(coin[CoinScramble.CO_X])) < 0.01
				and absf(float(old[CoinScramble.CO_Y]) - float(coin[CoinScramble.CO_Y])) < 0.01
			):
				fresh = false
				break
		_coin_fresh[i] = fresh
		if fresh and _coins_rendered_once:
			fx_dust(Vector2(coin[CoinScramble.CO_X], coin[CoinScramble.CO_Y]))
	_coins_seen = coins.duplicate(true)
	_coins_rendered_once = true
	# Pooled (#709): reuse the disc nodes across snapshots, hiding surplus, so a
	# 30 Hz coin field stops churning MeshInstance3D allocations.
	sync_pool(_coin_nodes, coins.size(), _make_coin, _place_coin)


func _make_coin() -> Node3D:
	return COIN_MODEL.instantiate()


func _place_coin(node: Node3D, index: int) -> void:
	var coin: Array = coins[index]
	# X/Z are sim truth, always applied; Y (drop/hover/bob) is owned by
	# _process once a fresh coin's drop starts (#781), so only the initial
	# value is set here.
	node.position = to_arena(Vector2(coin[CoinScramble.CO_X], coin[CoinScramble.CO_Y]), COIN_HOVER)
	if index < _coin_fresh.size() and _coin_fresh[index] and not ArenaFX.reduced_motion:
		if _coin_drop_start.size() < _coin_nodes.size():
			_coin_drop_start.resize(_coin_nodes.size())
		_coin_drop_start[index] = Time.get_ticks_msec() / 1000.0
