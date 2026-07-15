extends GutTest
## CharacterRig.play_protected / is_pose_protected (#942): the pose-hold the
## four one-shot-animation views (fort_siege / king_of_the_hill / memory_match
## / sumo_smash) used to each hand-roll with a private `_*_hold` dict.

const RIG_SCENE := preload("res://src/characters/character_rig.tscn")


func _rig() -> CharacterRig:
	var rig: CharacterRig = RIG_SCENE.instantiate()
	add_child_autofree(rig)
	# A real character loads the AnimationPlayer play() needs (views do this
	# via CharacterRoster.scene_for when building pooled rigs).
	rig.character_scene = CharacterRoster.scene_for(CharacterRoster.DEFAULT_ID)
	return rig


func test_a_fresh_rig_is_not_pose_protected() -> void:
	assert_false(_rig().is_pose_protected(), "nothing played -> no hold")


func test_play_protected_plays_the_action_and_holds() -> void:
	var rig := _rig()
	assert_true(rig.play_protected(&"attack", 10.0), "a known action plays")
	assert_eq(rig.current_action(), &"attack", "and becomes the current action")
	assert_true(rig.is_pose_protected(), "a positive hold protects the pose")


func test_a_zero_hold_protects_nothing() -> void:
	var rig := _rig()
	rig.play_protected(&"attack", 0.0)
	assert_false(rig.is_pose_protected(), "a 0s hold expires immediately")


func test_an_unknown_action_neither_plays_nor_holds() -> void:
	var rig := _rig()
	assert_false(rig.play_protected(&"not_a_real_action", 10.0), "unknown action returns false")
	assert_false(rig.is_pose_protected(), "and sets no hold")
