class_name HatCatalog
extends RefCounted
## The hat wardrobe (#935): persistent cosmetics bought with lifetime coins
## and worn on the rig's head bone in every game, the lobby, and the podium.
## Hats are pipeline-generated models (MDL-019/020/021) instanced per id —
## the primitive seed hats served until these landed, catalog contract
## unchanged. Pure/static: ids, prices, and a Node3D builder per hat — no
## scene state.
##
## `none` is the free default everyone owns. Every other hat costs its price
## in banked coins (StatsStore wallet) and, once bought, is owned forever
## (SettingsStore). The chosen hat id rides the appearance payload next to
## color/character (#581 funnel), so everyone sees everyone's hat.

const NONE := &"none"
## The head bone every KayKit rig shares (probed #935); the hat rides it so it
## tracks head bob through every animation.
const HEAD_BONE := "head"
## Fallback lift above the head-bone origin when a rig's meshes can't be
## measured. Chibi rigs carry huge heads — the head-bone origin sits ~0.7u
## BELOW the top of a KayKit head/helmet, so anything smaller buries the hat
## inside the head (measured on the Knight: bone at y 1.24, helmet top 1.96;
## the seed primitive hats were invisible for exactly this reason).
const HEAD_OFFSET := Vector3(0.0, 0.7, 0.0)
## Sink the brim slightly into the crown so hats read as worn, not floating.
const BRIM_SINK := 0.05

## id -> {name, price, scale}. Order is the wardrobe's display order.
## `scale` is the wear scale: the GLBs are built at real-world prop size
## (~0.4u, docs/MODEL_REQUESTS.md), but a hat on a ~1u-wide chibi head must
## be blown up to head proportions or it reads as a doll hat.
const HATS := {
	NONE: {"name": "No Hat", "price": 0},
	&"party_cone": {"name": "Party Cone", "price": 150, "scale": 2.1},
	&"top_hat": {"name": "Top Hat", "price": 400, "scale": 1.9},
	&"crown": {"name": "Gold Crown", "price": 1000, "scale": 2.2},
}

## Generated hat models (docs/MODEL_REQUESTS.md MDL-019/020/021), pivot at the
## brim base so a lift places the brim exactly at the head top.
const HAT_SCENES := {
	&"party_cone": preload("res://assets/generated/models/hat-party-cone.glb"),
	&"top_hat": preload("res://assets/generated/models/hat-top-hat.glb"),
	&"crown": preload("res://assets/generated/models/hat-crown.glb"),
}


static func ids() -> Array:
	return HATS.keys()


static func is_valid(id: StringName) -> bool:
	return HATS.has(id)


static func display_name(id: StringName) -> String:
	return String(HATS.get(id, HATS[NONE]).name)


static func price(id: StringName) -> int:
	return int(HATS.get(id, HATS[NONE]).price)


## A fresh Node3D wrapping the hat's generated model at wear scale, or null
## for `none` / an unknown id. The caller parents it to a head
## BoneAttachment3D and seats it with head_top_lift() (CharacterRig.set_hat).
static func build(id: StringName) -> Node3D:
	if id == NONE or not HAT_SCENES.has(id):
		return null
	var root := Node3D.new()
	root.name = "Hat"
	root.position = HEAD_OFFSET
	var scene: PackedScene = HAT_SCENES[id]
	var model: Node3D = scene.instantiate()
	model.scale = Vector3.ONE * float(HATS[id].get("scale", 1.0))
	root.add_child(model)
	return root


## How far above the head-bone origin this character's head actually ends —
## measured from its visible meshes at rest, so the brim seats on the Knight's
## tall helmet and the Dog's low fur alike. Falls back to HEAD_OFFSET.y when
## nothing is measurable. `model_root` is the character scene containing
## `skeleton`; both must share the scene (transforms are accumulated up to
## `model_root`, no tree access needed).
static func head_top_lift(model_root: Node3D, skeleton: Skeleton3D) -> float:
	var head := skeleton.find_bone(HEAD_BONE)
	if head == -1:
		return HEAD_OFFSET.y
	var head_y := (_xf_to(skeleton, model_root) * skeleton.get_bone_global_rest(head)).origin.y
	var top := head_y
	for node in model_root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if not mi.visible:
			continue
		var aabb := _xf_to(mi, model_root) * mi.get_aabb()
		top = maxf(top, aabb.end.y)
	if top <= head_y:
		return HEAD_OFFSET.y
	return top - head_y - BRIM_SINK


## Accumulated transform of `node` relative to `ancestor` by walking parents —
## works before the scene enters the tree (no global_transform).
static func _xf_to(node: Node3D, ancestor: Node) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var walker: Node = node
	while walker != null and walker != ancestor:
		if walker is Node3D:
			xf = (walker as Node3D).transform * xf
		walker = walker.get_parent()
	return xf
