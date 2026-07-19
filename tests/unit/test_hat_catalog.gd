extends GutTest
## The hat wardrobe catalog (#935): ids, prices, validation, and primitive
## Node3D builders for the seed hats.


func test_none_is_free_and_valid() -> void:
	assert_true(HatCatalog.is_valid(HatCatalog.NONE))
	assert_eq(HatCatalog.price(HatCatalog.NONE), 0)
	assert_null(HatCatalog.build(HatCatalog.NONE), "no hat builds nothing")


func test_seed_hats_are_priced_and_buildable() -> void:
	for id: StringName in HatCatalog.ids():
		if id == HatCatalog.NONE:
			continue
		assert_gt(HatCatalog.price(id), 0, "%s costs coins" % id)
		var node := HatCatalog.build(id)
		assert_not_null(node, "%s builds a node" % id)
		assert_gt(node.get_child_count(), 0, "%s has geometry" % id)
		node.free()


func test_unknown_id_is_invalid_and_builds_nothing() -> void:
	assert_false(HatCatalog.is_valid(&"sombrero"))
	assert_null(HatCatalog.build(&"sombrero"))
	assert_eq(HatCatalog.price(&"sombrero"), 0, "unknown falls back to free")


func test_hats_are_named() -> void:
	assert_eq(HatCatalog.display_name(&"top_hat"), "Top Hat")
	assert_false(HatCatalog.display_name(HatCatalog.NONE).is_empty())
