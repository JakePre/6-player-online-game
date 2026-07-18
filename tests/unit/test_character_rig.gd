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


# --- Cluster nameplate declutter (#923) --------------------------------------


## Two rigs piled together: the leader (higher nameplate_priority — the local
## player, #216) keeps a full plate; the one ranked behind is decluttered —
## shrunk, faded, and reduced to just its number badge.
func test_clustered_plates_declutter_all_but_the_leader() -> void:
	var leader := _rig()
	leader.display_name = "P1 Alice"
	leader.nameplate_priority = 1  # the local player keeps the readable spot
	leader.global_position = Vector3(10.0, 0.0, 0.0)
	var piled := _rig()
	piled.display_name = "P2 Bob  42 pts  (3 balls)"
	piled.nameplate_priority = 0
	piled.global_position = Vector3(10.0, 0.0, 0.0)  # same spot = one cluster

	leader._update_plate_stack()
	piled._update_plate_stack()

	var leader_plate: Label3D = leader.get_node("Nameplate")
	var piled_plate: Label3D = piled.get_node("Nameplate")
	assert_false(leader._decluttered, "the leader is never decluttered")
	assert_eq(leader_plate.text, "P1 Alice", "leader shows its full plate")
	assert_true(piled._decluttered, "the piled plate declutters behind the leader")
	assert_eq(piled_plate.text, "P2", "and collapses to just its badge")
	assert_lt(piled_plate.modulate.a, 0.9, "faded")
	assert_lt(piled_plate.font_size, leader_plate.font_size, "and smaller than the leader")


## A lone rig with no cluster mates keeps its full, opaque plate.
func test_a_solo_plate_is_never_decluttered() -> void:
	var rig := _rig()
	rig.display_name = "P3 Carol"
	rig.global_position = Vector3(-20.0, 0.0, 0.0)
	rig._update_plate_stack()
	assert_false(rig._decluttered, "no cluster -> full plate")
	assert_eq((rig.get_node("Nameplate") as Label3D).text, "P3 Carol")


## Declutter is reversible: once the pile breaks up, the plate restores its
## full name, size and opacity.
func test_declutter_restores_when_the_cluster_breaks_up() -> void:
	var leader := _rig()
	leader.nameplate_priority = 1
	leader.global_position = Vector3(5.0, 0.0, 0.0)
	var mover := _rig()
	mover.display_name = "P2 Bob"
	mover.global_position = Vector3(5.0, 0.0, 0.0)
	mover._update_plate_stack()
	assert_true(mover._decluttered, "piled at first")
	mover.global_position = Vector3(5.0, 0.0, 20.0)  # walked off
	mover._update_plate_stack()
	assert_false(mover._decluttered, "restored once clear")
	assert_eq((mover.get_node("Nameplate") as Label3D).text, "P2 Bob")
	assert_almost_eq(
		(mover.get_node("Nameplate") as Label3D).modulate.a, 1.0, 0.001, "opaque again"
	)
