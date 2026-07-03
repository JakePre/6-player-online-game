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


## The M9-04 (pack A) and M9-05 (pack B) PRs add one register line each here.
static func register_builtins() -> void:
	pass


static func mutator_of(id: StringName) -> Mutator:
	return _registry.get(id)


static func is_registered(id: StringName) -> bool:
	return _registry.has(id)


static func registered_ids() -> Array:
	var ids := _registry.keys()
	ids.sort()
	return ids
