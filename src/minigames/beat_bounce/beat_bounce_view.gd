extends MinigameView3D
## Beat Bounce client view (M4-09, on the M8-01 MinigameView3D tier): players
## stand in a ring of bounce pads around a central beat lamp that pulses on
## every beat. A shrinking ring above the lamp telegraphs the next beat so the
## rhythm is readable ahead of time. Rigs bounce (jump pose) when their hit
## registers, flinch on strikes, and slump to KO when eliminated. Strike
## tallies ride the nameplates.

const PAD_RING_RADIUS := 4.0
const PAD_RADIUS := 0.9
const LAMP_HEIGHT := 2.8
const LAMP_RADIUS := 0.5
## The telegraph ring shrinks from this scale down to 1.0 at the beat instant.
const TELEGRAPH_MAX_SCALE := 3.0
const PULSE_COLOR := Color(0.95, 0.85, 0.3)
const IDLE_COLOR := Color(0.35, 0.3, 0.5)
## The lamp glows for this long after each beat.
const PULSE_SEC := 0.15

var _beat := 0
var _next_in := 0.0
var _interval := BeatBounce.START_INTERVAL_SEC
var _strikes := {}
var _alive := {}
var _last_hit := {}
var _bounced_on := {}  # slot (int) -> last beat we played the jump pose for
var _flinched := {}  # slot (int) -> strike count already flinched at

var _lamp_material: StandardMaterial3D
var _telegraph: MeshInstance3D
var _snapshot_at := 0.0


func _arena_half() -> float:
	return 7.0


func _setup_3d() -> void:
	_ring_up_rigs()
	_build_pads()
	_build_lamp()
	_build_telegraph()


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed(&"action_primary"):
		NetManager.send_match_input({"press": true})
	_animate_beat()


func _render_3d(game: Dictionary) -> void:
	_beat = int(game.get("beat", 0))
	_next_in = float(game.get("next_in", 0.0))
	_interval = maxf(float(game.get("interval", _interval)), 0.01)
	_strikes = game.get("strikes", {})
	_alive = game.get("alive", {})
	_last_hit = game.get("last_hit", {})
	_snapshot_at = _now_sec()
	_update_rigs()


## Players stand on pads in a circle facing the central lamp.
func _ring_up_rigs() -> void:
	var sorted: Array = names.keys()
	sorted.sort()
	for i in sorted.size():
		var rig := rig_for_slot(sorted[i])
		if rig == null:
			continue
		var angle := TAU * i / sorted.size()
		var pos := Vector2(cos(angle), sin(angle)) * PAD_RING_RADIUS
		rig.position = to_arena(pos)
		rig.rotation.y = atan2(-pos.x, -pos.y)  # face the lamp


func _build_pads() -> void:
	var sorted: Array = names.keys()
	sorted.sort()
	for i in sorted.size():
		var slot: int = sorted[i]
		var angle := TAU * i / sorted.size()
		var mesh := CylinderMesh.new()
		mesh.top_radius = PAD_RADIUS
		mesh.bottom_radius = PAD_RADIUS
		mesh.height = 0.1
		var material := StandardMaterial3D.new()
		material.albedo_color = player_color(slot)
		mesh.material = material
		var pad := MeshInstance3D.new()
		pad.name = "Pad%d" % slot
		pad.mesh = mesh
		pad.position = to_arena(Vector2(cos(angle), sin(angle)) * PAD_RING_RADIUS, 0.05)
		arena.add_child(pad)


func _build_lamp() -> void:
	var mesh := SphereMesh.new()
	mesh.radius = LAMP_RADIUS
	mesh.height = LAMP_RADIUS * 2.0
	_lamp_material = StandardMaterial3D.new()
	_lamp_material.emission_enabled = true
	mesh.material = _lamp_material
	var lamp := MeshInstance3D.new()
	lamp.name = "BeatLamp"
	lamp.mesh = mesh
	lamp.position = Vector3(0.0, LAMP_HEIGHT, 0.0)
	arena.add_child(lamp)


func _build_telegraph() -> void:
	var mesh := TorusMesh.new()
	mesh.inner_radius = LAMP_RADIUS + 0.15
	mesh.outer_radius = LAMP_RADIUS + 0.3
	var material := StandardMaterial3D.new()
	material.albedo_color = PULSE_COLOR
	material.emission_enabled = true
	material.emission = PULSE_COLOR
	mesh.material = material
	_telegraph = MeshInstance3D.new()
	_telegraph.name = "Telegraph"
	_telegraph.mesh = mesh
	_telegraph.position = Vector3(0.0, LAMP_HEIGHT, 0.0)
	arena.add_child(_telegraph)


## Lamp pulse + telegraph shrink run every frame, extrapolating the beat
## clock from the last snapshot so the rhythm reads smoothly at any fps.
func _animate_beat() -> void:
	if _lamp_material == null:
		return
	var remaining := _next_in - (_now_sec() - _snapshot_at)
	var phase := clampf(remaining / _interval, 0.0, 1.0)
	var pulsing := remaining < PULSE_SEC or _interval - remaining < PULSE_SEC
	var color := PULSE_COLOR if pulsing else IDLE_COLOR
	_lamp_material.albedo_color = color
	_lamp_material.emission = color
	var telegraph_scale := 1.0 + (TELEGRAPH_MAX_SCALE - 1.0) * phase
	_telegraph.scale = Vector3(telegraph_scale, 1.0, telegraph_scale)


## Bounce on registered hits, KO on elimination, flinch while carrying a
## strike; play() is guarded so poses are not restarted every snapshot.
func _update_rigs() -> void:
	for slot: int in names:
		var rig := rig_for_slot(slot)
		if rig == null:
			continue
		var slot_strikes := int(_strikes.get(slot, 0))
		var caption := player_name(slot)
		if slot_strikes > 0:
			caption += "  %s" % "✕".repeat(slot_strikes)
		rig.display_name = caption
		var desired: StringName = &"idle"
		if not _alive.get(slot, true):
			desired = &"ko"
		elif slot_strikes > int(_flinched.get(slot, 0)):
			_flinched[slot] = slot_strikes
			rig.play(&"hit")
			continue
		elif int(_last_hit.get(slot, -1)) >= _beat and _bounced_on.get(slot, -1) != _beat:
			_bounced_on[slot] = _beat
			rig.play(&"jump_start")
			continue
		if rig.current_action() in [&"jump_start", &"hit"]:
			continue  # let one-shot poses finish before returning to idle
		if rig.current_action() != desired:
			rig.play(desired)
