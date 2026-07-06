extends MinigameView3D
## Musical Platforms client view (M10-02): renders the replicated arena in
## the shared 2.5D iso-arena — players as CharacterRigs (losers collapse and
## dim), platforms as discs that appear when the music stops and light up in
## the claimant's color, and a Control-layer call-out flipping between
## DANCE! and GRAB A PLATFORM! so the phase is readable instantly.

const PLATFORM_FREE_COLOR := Color(0.75, 0.75, 0.8, 0.55)
const PLATFORM_DISC_HEIGHT := 0.06
const ELIMINATED_COLOR := Color(0.42, 0.42, 0.46)
const MUSIC_TEXT := "DANCE!"
const STOP_TEXT := "GRAB A PLATFORM!"

## Latest replicated state, straight from MusicalPlatforms.get_snapshot().
var players := {}
var phase: int = MusicalPlatforms.Phase.MUSIC
var platforms: Array = []
var fallen: Array = []

var _platform_pool: Array[MeshInstance3D] = []
var _phase_label: Label
var _downed := {}
# pool index -> claimant from the previous snapshot (M13-08 claim flashes).
var _claims_seen := {}
# Wave tracking for drop-in dust (M13-08): platforms empty last render, and
# whether any render happened yet (rejoin seeding).
var _platforms_were_empty := true
var _rendered_once := false
# -1 = unseeded, so a mid-match rejoin does not shake on its first snapshot.
var _fallen_seen := -1


func _physics_process(_delta: float) -> void:
	send_move_intent()


## Soft lavender floor for the musical whimsy (#589).
func _floor_tint() -> Color:
	return Color(0.92, 0.88, 1.0)


func _arena_half() -> float:
	# Grow the framed floor with the lobby to match the sim's scaled play area
	# (M15, ADR 003 F4); at <=6 players this is the tuned MusicalPlatforms.ARENA_HALF.
	return MinigameScaling.arena_half(MusicalPlatforms.ARENA_HALF, names.size())


func _setup_3d() -> void:
	# Pool sized to the worst case for this lobby: "players - 1" platforms
	# spawn on the very first STOP round, and it only shrinks from there — a
	# fixed pool (previously 5, the <=6-player max) silently dropped
	# platforms past that once the cap grew (M15, ADR 003; #457).
	var pool_size := maxi(names.size() - 1, 1)
	for i in pool_size:
		var mesh := CylinderMesh.new()
		mesh.top_radius = MusicalPlatforms.PLATFORM_RADIUS
		mesh.bottom_radius = MusicalPlatforms.PLATFORM_RADIUS
		mesh.height = PLATFORM_DISC_HEIGHT
		var material := StandardMaterial3D.new()
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.albedo_color = PLATFORM_FREE_COLOR
		mesh.material = material
		var node := MeshInstance3D.new()
		node.name = "Platform%d" % i
		node.mesh = mesh
		node.visible = false
		arena.add_child(node)
		_platform_pool.append(node)
	_phase_label = Label.new()
	_phase_label.name = "PhaseLabel"
	_phase_label.add_theme_font_size_override(&"font_size", 32)
	_phase_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_phase_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_phase_label.position.y = 16.0
	add_child(_phase_label)


func _render_3d(game: Dictionary) -> void:
	players = game.get("players", {})
	phase = int(game.get("phase", MusicalPlatforms.Phase.MUSIC))
	platforms = game.get("platforms", [])
	fallen = game.get("fallen", [])
	_phase_label.text = STOP_TEXT if phase == MusicalPlatforms.Phase.STOP else MUSIC_TEXT
	_update_players()
	_update_platforms()
	_shake_on_new_downs()


func _update_players() -> void:
	for slot: int in players:
		var state: Array = players[slot]
		var rig := rig_for_slot(slot)
		if rig == null:
			continue
		update_rig(slot, Vector2(state[0], state[1]))
	for group: Array in fallen:
		for slot: int in group:
			_down_rig(slot)


func _down_rig(slot: int) -> void:
	if _downed.has(slot):
		return
	var rig := rig_for_slot(slot)
	if rig == null:
		return
	_downed[slot] = true
	rig.play(&"ko")
	rig.player_color = ELIMINATED_COLOR
	# Dust where they drop (M13-08).
	fx_dust(Vector2(rig.position.x, rig.position.z))


## Free platforms are neutral gray; claimed ones take the claimant's color so
## "which are still up for grabs" reads at a glance.
func _update_platforms() -> void:
	for i in _platform_pool.size():
		var node := _platform_pool[i]
		node.visible = i < platforms.size()
		if not node.visible:
			continue
		var state: Array = platforms[i]
		node.position = to_arena(Vector2(state[0], state[1]), PLATFORM_DISC_HEIGHT / 2.0)
		var claimant := int(state[2])
		var material: StandardMaterial3D = (node.mesh as CylinderMesh).material
		if claimant == -1:
			material.albedo_color = PLATFORM_FREE_COLOR
		else:
			var color := player_color(claimant)
			color.a = 0.75
			material.albedo_color = color
		# Claim flash (M13-08): the moment a pad flips from free to owned,
		# sparkle in the claimant's color; a fresh wave of platforms puffs
		# dust as it drops in (skipped on the client's very first render, so
		# rejoiners aren't greeted with a dust storm).
		var at := Vector2(state[0], state[1])
		if _platforms_were_empty and _rendered_once:
			fx_dust(at)
		if int(_claims_seen.get(i, -1)) == -1 and claimant != -1:
			fx_sparkle(at, player_color(claimant))
			if claimant == my_slot:
				play_sfx(&"confirm")
		_claims_seen[i] = claimant
	_platforms_were_empty = platforms.is_empty()
	_rendered_once = true
	# Platforms clearing with the music resets the per-round claim tracking.
	if platforms.is_empty():
		_claims_seen.clear()


func _shake_on_new_downs() -> void:
	var fallen_count := 0
	for group: Array in fallen:
		fallen_count += group.size()
	if _fallen_seen >= 0 and fallen_count > _fallen_seen:
		request_shake(9.0)
		play_sfx(&"error")
	_fallen_seen = fallen_count
