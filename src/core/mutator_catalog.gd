class_name MutatorCatalog
extends RefCounted
## Static registry of all mutators (M9-01), mirroring MinigameCatalog: the
## M9-04/05 pack PRs each add one register line to register_builtins(), the
## lobby pool (M9-02) and per-round roll (M9-03) read from here.

static var _registry := {}


static func register(mutator: Mutator) -> void:
	assert(not _registry.has(mutator.id), "Duplicate mutator id: %s" % mutator.id)
	_registry[mutator.id] = mutator


static func clear() -> void:
	_registry.clear()


## Pack A (M9-04) below; pack B (M9-05) adds its four register lines here.
static func register_builtins() -> void:
	if not _registry.is_empty():
		return
	register(
		(
			Mutator
			. create(
				{
					"id": &"double_coins",
					"name": "Double Coins",
					"blurb": "All placement awards doubled this round.",
					"award_multiplier": 2.0,
				}
			)
		)
	)
	register(
		(
			Mutator
			. create(
				{
					"id": &"golden_round",
					"name": "Golden Round",
					"blurb": "Pickup-coin cap raised 30 to 60.",
					"pickup_cap_scale": 2.0,
				}
			)
		)
	)
	register(
		(
			Mutator
			. create(
				{
					"id": &"short_fuse",
					"name": "Short Fuse",
					"blurb": "The round runs at 60% length.",
					"duration_scale": 0.6,
				}
			)
		)
	)
	register(
		(
			Mutator
			. create(
				{
					"id": &"overdrive",
					"name": "Overdrive",
					"blurb": "Everything moves 25% faster.",
					"speed_scale": 1.25,
				}
			)
		)
	)


static func mutator_of(id: StringName) -> Mutator:
	return _registry.get(id)


static func is_registered(id: StringName) -> bool:
	return _registry.has(id)


static func registered_ids() -> Array:
	var ids := _registry.keys()
	# Explicit String comparison: StringName sort order is lexicographic on
	# Godot 4.6 but creation-ordered on the 4.4 CI runner.
	ids.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	return ids
