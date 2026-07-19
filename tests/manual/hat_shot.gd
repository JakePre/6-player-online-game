## Headless screenshot of a hat worn on a character's head — verifies the
## generated hat GLBs render through the game's own import pipeline, the
## BoneAttachment3D mechanism, and the measured head-top seating that
## CharacterRig._apply_hat uses (#935).
##
##   godot --path . --write-movie out/shot.png --fixed-fps 4 --quit-after 6 \
##         --resolution 768x768 --script tests/manual/hat_shot.gd \
##         ++ --hat party_cone [--character <res path to glb>] [--lift <y>]
extends SceneTree

const CHARACTER_DEFAULT := "res://assets/characters/kaykit_adventurers/Knight.glb"


func _initialize() -> void:
	var hat_id := "party_cone"
	var character := CHARACTER_DEFAULT
	var lift := -1.0
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		match args[i]:
			"--hat":
				i += 1
				hat_id = args[i]
			"--character":
				i += 1
				character = args[i]
			"--lift":
				i += 1
				lift = float(args[i])
		i += 1

	var char_scene: PackedScene = load(character)
	var model: Node3D = char_scene.instantiate()
	root.add_child(model)

	var hat := HatCatalog.build(StringName(hat_id))
	if hat == null:
		push_error("hat_shot: unknown hat id %s" % hat_id)
		quit(2)
		return
	var skels := model.find_children("*", "Skeleton3D", true, false)
	if skels.is_empty():
		push_error("hat_shot: no Skeleton3D in %s" % character)
		quit(2)
		return
	var skel: Skeleton3D = skels[0]
	# Same seating CharacterRig._apply_hat computes, overridable via --lift.
	if lift < 0.0:
		lift = HatCatalog.head_top_lift(model, skel)
	hat.position = Vector3(0.0, lift, 0.0)
	var att := BoneAttachment3D.new()
	skel.add_child(att)
	att.bone_name = HatCatalog.HEAD_BONE
	att.add_child(hat)
	print("hat_shot: %s on %s lift=%.3f" % [hat_id, character, lift])
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var aabb := HatCatalog._xf_to(mi, model) * mi.get_aabb()
		print("hat_shot: mesh %-28s vis=%s top=%.3f" % [mi.name, mi.visible, aabb.end.y])

	var players := model.find_children("*", "AnimationPlayer", true, false)
	if players.size() > 0:
		var ap: AnimationPlayer = players[0]
		for a in ap.get_animation_list():
			if String(a).ends_with("Idle"):
				ap.play(a)
				break

	var cam := Camera3D.new()
	var target := Vector3(0.0, 1.4, 0.0)
	cam.position = target + Vector3(0.0, 1.0, 4.2)
	root.add_child(cam)
	cam.look_at_from_position(cam.position, target)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45.0, -30.0, 0.0)
	root.add_child(light)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.16, 0.17, 0.20)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.7, 0.7, 0.75)
	e.ambient_light_energy = 0.8
	root.add_child(env)
	env.environment = e
