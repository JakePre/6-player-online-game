extends GutTest
## Target Range client view: renders replicated targets/aims in the iso arena
## without local simulation, and (M13-17) breaks shot targets with a burst.

const VIEW_SCENE: PackedScene = preload("res://src/minigames/target_range/target_range_view.tscn")

var view: MinigameView3D


func before_each() -> void:
	view = VIEW_SCENE.instantiate()
	add_child_autofree(view)
	view.setup({0: "Alice", 1: "Bob"}, 0)


func _burst_count() -> int:
	var count := 0
	for child in view.arena.get_children():
		if child is CPUParticles3D:
			count += 1
	return count


func test_render_tolerates_missing_keys() -> void:
	view.render({})
	assert_not_null(view.arena.get_node("Crosshair0"))


## A target present one snapshot and gone the next, while on-screen, was shot —
## it pops a break burst where it stood.
func test_shooting_a_target_breaks_it_with_a_burst() -> void:
	view.render({"targets": [[1, 0.0, 3.0, 0.5, TargetRange.Kind.STANDARD]]})
	assert_eq(_burst_count(), 0, "no burst while the target is alive")
	view.render({"targets": []})
	assert_gt(_burst_count(), 0, "the broken target pops a burst")


## A target recycled off the far edge (sim drift, not a hit) leaves from beyond
## the arena and pops nothing.
func test_drifted_off_target_does_not_burst() -> void:
	var off_x := TargetRange.ARENA_HALF + 5.0
	view.render({"targets": [[2, off_x, 3.0, 0.5, TargetRange.Kind.STANDARD]]})
	view.render({"targets": []})
	assert_eq(_burst_count(), 0, "an off-screen recycle is silent")


## M15-07: a 24-shooter crowd wraps into ranks stepping toward the gallery,
## all staying clear of the target band (BAND_NEAR is -1).
func test_crowd_wraps_toward_the_gallery() -> void:
	var crowd := {}
	for slot in 24:
		crowd[slot] = "P%d" % (slot + 1)
	var big: MinigameView3D = VIEW_SCENE.instantiate()
	add_child_autofree(big)
	big.setup(crowd, 0)
	var depths := {}
	for slot in 24:
		var rig: CharacterRig = big.rig_for_slot(slot)
		depths[snappedf(rig.position.z, 0.01)] = true
		assert_lte(rig.position.z, big.FIRING_LINE + 0.001, "no rank behind the firing line")
		assert_gt(rig.position.z, 2.0, "every rank stays clear of the target band")
	assert_eq(depths.size(), 3, "24 shooters stand in three ranks")
