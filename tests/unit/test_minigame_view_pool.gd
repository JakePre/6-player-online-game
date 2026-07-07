extends GutTest
## Pooled transient-node reconciliation (#709): MinigameView3D.reconcile_pool
## grows the pool on demand, HIDES (never frees) the surplus, and reuses node
## identity across frames — the pool math the 13-view adoption fan-out (stage 2)
## relies on, tested without standing up a whole arena view.

var _parent: Node3D
var _factory_calls := 0
var _updates: Array = []


func before_each() -> void:
	_parent = Node3D.new()
	add_child_autofree(_parent)
	_factory_calls = 0
	_updates = []


func _make() -> Node3D:
	_factory_calls += 1
	return Node3D.new()


func _record(_node: Node3D, index: int) -> void:
	_updates.append(index)


func test_grows_to_count_parents_and_shows() -> void:
	var pool: Array = []
	MinigameView3D.reconcile_pool(pool, 3, _make, _record, _parent)
	assert_eq(pool.size(), 3, "pool grew to the requested count")
	assert_eq(_factory_calls, 3, "one factory call per new node")
	assert_eq(_parent.get_child_count(), 3, "new nodes parented under the host")
	for node: Node3D in pool:
		assert_true(node.visible, "active nodes are shown")
	assert_eq(_updates, [0, 1, 2], "update ran once per active index")


func test_shrink_hides_surplus_without_freeing() -> void:
	var pool: Array = []
	MinigameView3D.reconcile_pool(pool, 3, _make, _record, _parent)
	_updates = []
	MinigameView3D.reconcile_pool(pool, 1, _make, _record, _parent)
	assert_eq(pool.size(), 3, "surplus is kept, not freed")
	assert_eq(_parent.get_child_count(), 3, "surplus stays in the tree")
	assert_eq(_factory_calls, 3, "shrinking builds nothing new")
	assert_true(pool[0].visible, "the one active node shows")
	assert_false(pool[1].visible, "surplus is hidden")
	assert_false(pool[2].visible)
	assert_eq(_updates, [0], "only the active node updates")


func test_reuses_node_identity_across_regrow() -> void:
	var pool: Array = []
	MinigameView3D.reconcile_pool(pool, 3, _make, _record, _parent)
	var originals := pool.duplicate()
	MinigameView3D.reconcile_pool(pool, 1, _make, _record, _parent)  # shrink
	MinigameView3D.reconcile_pool(pool, 2, _make, _record, _parent)  # regrow
	assert_eq(_factory_calls, 3, "regrow within the high-water mark makes no new nodes")
	assert_true(pool[0] == originals[0], "reused the same instance at index 0")
	assert_true(pool[1] == originals[1], "reused the same instance at index 1")
	assert_true((pool[0] as Node3D).visible)
	assert_true((pool[1] as Node3D).visible)
	assert_false((pool[2] as Node3D).visible, "still-surplus node stays hidden")


func test_zero_count_hides_everything() -> void:
	var pool: Array = []
	MinigameView3D.reconcile_pool(pool, 2, _make, _record, _parent)
	MinigameView3D.reconcile_pool(pool, 0, _make, _record, _parent)
	assert_eq(pool.size(), 2, "nodes retained for the next wave")
	for node: Node3D in pool:
		assert_false(node.visible, "count 0 -> all hidden")
