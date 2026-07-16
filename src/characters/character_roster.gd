class_name CharacterRoster
extends RefCounted
## The fixed selectable character roster (SPEC $8): distinct silhouettes,
## shared humanoid rig/animations via CharacterRig. Player color
## (PlayerPalette) is the primary identity channel, character is flavor —
## duplicate picks across players are allowed and disambiguated by color.

const ENTRIES: Array[Dictionary] = [
	{
		"id": &"barbarian",
		"display_name": "Barbarian",
		"scene_path": "res://assets/characters/kaykit_adventurers/Barbarian.glb",
	},
	{
		"id": &"knight",
		"display_name": "Knight",
		"scene_path": "res://assets/characters/kaykit_adventurers/Knight.glb",
	},
	{
		"id": &"mage",
		"display_name": "Mage",
		"scene_path": "res://assets/characters/kaykit_adventurers/Mage.glb",
	},
	{
		"id": &"rogue",
		"display_name": "Rogue",
		"scene_path": "res://assets/characters/kaykit_adventurers/Rogue.glb",
	},
	{
		"id": &"rogue_hooded",
		"display_name": "Hooded Rogue",
		"scene_path": "res://assets/characters/kaykit_adventurers/Rogue_Hooded.glb",
	},
	{
		"id": &"skeleton_mage",
		"display_name": "Skeleton Mage",
		"scene_path": "res://assets/characters/kaykit_skeletons/Skeleton_Mage.glb",
	},
	{
		"id": &"skeleton_rogue",
		"display_name": "Skeleton Rogue",
		"scene_path": "res://assets/characters/kaykit_skeletons/Skeleton_Rogue.glb",
	},
	{
		"id": &"skeleton_warrior",
		"display_name": "Skeleton Warrior",
		"scene_path": "res://assets/characters/kaykit_skeletons/Skeleton_Warrior.glb",
	},
	{
		# First pipeline-generated character (generating-assets workspace):
		# Trellis mesh skinned onto the shared KayKit skeleton, so it runs the
		# same 77-animation set as every other roster entry.
		"id": &"dog",
		"display_name": "Dog",
		"scene_path": "res://assets/characters/generated/Dog.glb",
	},
	{
		# Pipeline-generated, first fully-autonomous character build: screened
		# FLUX concepts, voxel-solidified Trellis mesh, bone-heat weights,
		# concept-projected texture — same skeleton, all 77 animations.
		"id": &"fox",
		"display_name": "Fox",
		"scene_path": "res://assets/characters/generated/Fox.glb",
	},
	{
		# First FULLY-LOCAL sovereign build (no external services end to end):
		# Qwen-Image GGUF concepts (front+back auto-generated), local-VLM
		# T-pose screens and clip reviews, Trellis mesh, transfer weights,
		# concept-projected texture — same skeleton, all 77 animations.
		"id": &"rhino",
		"display_name": "Rhino",
		"scene_path": "res://assets/characters/generated/Rhino.glb",
	},
]

## SPEC $8 calls for a roster of 8; Skeleton_Minion is held back as the first
## bench pick for a future roster expansion (still credited, unused for now).
const DEFAULT_ID: StringName = &"barbarian"


static func ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for entry in ENTRIES:
		out.append(entry.id)
	return out


static func is_valid(id: StringName) -> bool:
	return _index_of(id) >= 0


static func display_name_for(id: StringName) -> String:
	var index := _index_of(id)
	return ENTRIES[index].display_name if index >= 0 else ""


static func scene_for(id: StringName) -> PackedScene:
	var index := _index_of(id)
	if index < 0:
		return null
	return load(ENTRIES[index].scene_path)


static func _index_of(id: StringName) -> int:
	for i in ENTRIES.size():
		if ENTRIES[i].id == id:
			return i
	return -1
