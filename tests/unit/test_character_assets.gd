extends GutTest
## Character asset contract (asset pipeline): every roster entry must import
## as a valid scene whose AnimationPlayer carries every animation that
## CharacterRig.ACTIONS maps to. This is the CI-level guard that a generated
## or re-exported GLB (new character, injected animation, texture swap)
## actually works in-engine — the asset workspace's own renderer validates
## the GLTF math, but only Godot's importer validates Godot's import.


func test_every_roster_entry_loads() -> void:
	for entry: Dictionary in CharacterRoster.ENTRIES:
		var scene := load(entry.scene_path) as PackedScene
		assert_not_null(scene, "%s: scene failed to load (%s)" % [entry.id, entry.scene_path])


func test_every_roster_entry_has_every_action_animation() -> void:
	for entry: Dictionary in CharacterRoster.ENTRIES:
		var scene := load(entry.scene_path) as PackedScene
		if scene == null:
			continue  # already failed above with a clearer message
		var root := scene.instantiate()
		add_child_autofree(root)
		var players := root.find_children("*", "AnimationPlayer", true, false)
		assert_gt(players.size(), 0, "%s: no AnimationPlayer" % entry.id)
		if players.is_empty():
			continue
		var anim_player: AnimationPlayer = players[0]
		for action: StringName in CharacterRig.ACTIONS:
			var anim_name: StringName = CharacterRig.ACTIONS[action].anim
			assert_true(
				anim_player.has_animation(anim_name),
				"%s: missing animation '%s' (action '%s')" % [entry.id, anim_name, action]
			)


func test_every_roster_entry_has_a_skeleton() -> void:
	for entry: Dictionary in CharacterRoster.ENTRIES:
		var scene := load(entry.scene_path) as PackedScene
		if scene == null:
			continue
		var root := scene.instantiate()
		add_child_autofree(root)
		var skeletons := root.find_children("*", "Skeleton3D", true, false)
		assert_gt(skeletons.size(), 0, "%s: no Skeleton3D" % entry.id)
		if skeletons.is_empty():
			continue
		var skeleton: Skeleton3D = skeletons[0]
		# The shared-rig contract: the weapon-hold bone must exist everywhere.
		assert_ne(
			skeleton.find_bone("handslot.r"),
			-1,
			"%s: missing handslot.r — not on the shared KayKit skeleton" % entry.id
		)
