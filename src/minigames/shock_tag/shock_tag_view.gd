extends MinigameView3D
## Shock Tag client view (M10-03): renders the replicated arena in the shared
## 2.5D iso-arena — players as CharacterRigs with coin counts on nameplates,
## the electrified player marked by a crackling emissive ring underfoot. Tags
## (the zap changing hands) shake the screen.

const RING_COLOR := Color(1.0, 0.9, 0.25, 0.6)
const RING_HEIGHT := 0.05

## Latest replicated state, straight from ShockTag.get_snapshot().
var players := {}
var zapped := -1

var _ring: MeshInstance3D
## Snapshot counter driving the crackle-ring pulse (replicated cadence, no
## local clocks — M13-09).
var _pulse_ticks := 0
# -1 = unseeded, so a mid-match rejoin does not shake on its first snapshot.
var _zapped_seen := -1


func _physics_process(_delta: float) -> void:
	send_move_intent()


## Cool electric-blue floor for the shock arena (#589).
func _floor_tint() -> Color:
	return Color(0.82, 0.9, 1.0)


func _arena_half() -> float:
	return ShockTag.ARENA_HALF


func _setup_3d() -> void:
	var mesh := TorusMesh.new()
	mesh.inner_radius = ShockTag.PLAYER_RADIUS * 1.4
	mesh.outer_radius = ShockTag.PLAYER_RADIUS * 2.0
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = RING_COLOR
	material.emission_enabled = true
	material.emission = Color(RING_COLOR, 1.0)
	material.emission_energy_multiplier = 0.8
	mesh.material = material
	_ring = MeshInstance3D.new()
	_ring.name = "ZapRing"
	_ring.mesh = mesh
	_ring.visible = false
	arena.add_child(_ring)


func _render_3d(game: Dictionary) -> void:
	players = game.get("players", {})
	zapped = int(game.get("zapped", -1))
	_update_players()
	_update_ring()
	if _zapped_seen >= 0 and zapped != _zapped_seen:
		request_shake(9.0)
		_zap_arc(_zapped_seen, zapped)
		# Personal read on the hand-off (M12-02): stuck with it stings, passing
		# it off relieves. `zap` (#728, docs/AUDIO_GUIDE.md) is this game's own
		# literal namesake in the vocabulary.
		if zapped == my_slot:
			play_sfx(&"zap")
		elif _zapped_seen == my_slot:
			play_sfx(&"confirm")
	_zapped_seen = zapped


## The tag reads as electricity (M13-09): a yellow-white burst at both ends
## of the hand-off — the old carrier discharging, the new one lighting up.
func _zap_arc(from_slot: int, to_slot: int) -> void:
	for slot in [from_slot, to_slot]:
		var state: Array = players.get(slot, [])
		if state.size() > ShockTag.PS_Y:
			fx_burst(Vector2(state[ShockTag.PS_X], state[ShockTag.PS_Y]), RING_COLOR, 1.0)


func _update_players() -> void:
	for slot: int in players:
		var state: Array = players[slot]
		var rig := rig_for_slot(slot)
		if rig == null:
			continue
		update_rig(slot, Vector2(state[ShockTag.PS_X], state[ShockTag.PS_Y]))
		var caption := "%s  %d" % [player_name(slot), int(state[ShockTag.PS_COINS])]
		if slot == zapped:
			caption += "  ZAP!"
		rig.display_name = caption


func _update_ring() -> void:
	var state: Array = players.get(zapped, [])
	_ring.visible = state.size() > ShockTag.PS_Y
	if _ring.visible:
		_ring.position = to_arena(Vector2(state[ShockTag.PS_X], state[ShockTag.PS_Y]), RING_HEIGHT)
		# Crackle pulse (M13-09): a throb every few snapshots, so it animates
		# identically on every client.
		_pulse_ticks += 1
		var throb := 1.0 + 0.18 * sin(_pulse_ticks * TAU / 12.0)
		_ring.scale = Vector3(throb, 1.0, throb)
