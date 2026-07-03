extends MinigameView3D
## Poison Feast client view (M8-11): renders the shared table in the 2.5D
## iso-arena (M8-01, MinigameView3D) — players as CharacterRig instances with
## name + score, dishes as identical Kenney food-kit bowls (M8-02). Every
## dish uses the same model on purpose: nothing may indicate which are
## poisoned, that hiddenness is the whole mechanic. Presentation-tier swap
## only: state storage and the render contract are unchanged from the 2D
## pass (M4-14).

const DISH_SCENE := preload("res://assets/environment/kenney_food_kit/bowl-soup.glb")
const DISH_SCALE := 2.0

## Latest replicated state, straight from PoisonFeast.get_snapshot().
var players := {}
var dishes: Array = []

var _dish_pool: Array[Node3D] = []


func _physics_process(_delta: float) -> void:
	send_move_intent()


func _arena_half() -> float:
	return PoisonFeast.ARENA_HALF


## Dishes are pooled up front (the sim caps concurrent dishes) and shown per
## snapshot, so no GLB instancing happens mid-round.
func _setup_3d() -> void:
	for i in PoisonFeast.MAX_ACTIVE_DISHES:
		var dish: Node3D = DISH_SCENE.instantiate()
		dish.name = "Dish%d" % i
		dish.scale = Vector3.ONE * DISH_SCALE
		dish.visible = false
		arena.add_child(dish)
		_dish_pool.append(dish)


func _render_3d(game: Dictionary) -> void:
	players = game.get("players", {})
	dishes = game.get("dishes", [])
	_update_players()
	_update_dishes()


func _update_players() -> void:
	for slot: int in players:
		var state: Array = players[slot]
		var rig := rig_for_slot(slot)
		if rig == null:
			continue
		update_rig(slot, Vector2(state[0], state[1]))
		rig.display_name = "%s  %d" % [player_name(slot), int(state[2])]


func _update_dishes() -> void:
	for i in _dish_pool.size():
		var dish := _dish_pool[i]
		dish.visible = i < dishes.size()
		if dish.visible:
			var state: Array = dishes[i]
			dish.position = to_arena(Vector2(state[0], state[1]))
