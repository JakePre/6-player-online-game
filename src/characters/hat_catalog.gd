class_name HatCatalog
extends RefCounted
## The hat wardrobe (#935): persistent cosmetics bought with lifetime coins
## and worn on the rig's head bone in every game, the lobby, and the podium.
## Ships primitive-built hats so the feature lands before the owner's model
## pipeline queues real ones (generated hats swap the builder per id later,
## the catalog contract unchanged). Pure/static: ids, prices, and a Node3D
## builder per hat — no scene state.
##
## `none` is the free default everyone owns. Every other hat costs its price
## in banked coins (StatsStore wallet) and, once bought, is owned forever
## (SettingsStore). The chosen hat id rides the appearance payload next to
## color/character (#581 funnel), so everyone sees everyone's hat.

const NONE := &"none"
## The head bone every KayKit rig shares (probed #935); the hat rides it so it
## tracks head bob through every animation.
const HEAD_BONE := "head"
## Lift off the head-bone origin so a hat sits ON the head, not inside it.
const HEAD_OFFSET := Vector3(0.0, 0.12, 0.0)

## id -> {name, price}. Order is the wardrobe's display order. Builders live in
## _build() keyed by the same id.
const HATS := {
	NONE: {"name": "No Hat", "price": 0},
	&"party_cone": {"name": "Party Cone", "price": 150},
	&"top_hat": {"name": "Top Hat", "price": 400},
	&"crown": {"name": "Gold Crown", "price": 1000},
}


static func ids() -> Array:
	return HATS.keys()


static func is_valid(id: StringName) -> bool:
	return HATS.has(id)


static func display_name(id: StringName) -> String:
	return String(HATS.get(id, HATS[NONE]).name)


static func price(id: StringName) -> int:
	return int(HATS.get(id, HATS[NONE]).price)


## A fresh Node3D of the hat's primitive geometry, seated at HEAD_OFFSET, or
## null for `none` / an unknown id. The caller parents it to a head
## BoneAttachment3D (CharacterRig.set_hat).
static func build(id: StringName) -> Node3D:
	if id == NONE or not HATS.has(id):
		return null
	var root := Node3D.new()
	root.name = "Hat"
	root.position = HEAD_OFFSET
	match id:
		&"party_cone":
			_add_mesh(root, _cone(0.16, 0.42), Color(0.95, 0.3, 0.5), Vector3.ZERO)
		&"top_hat":
			_add_mesh(root, _cylinder(0.03, 0.24, 0.02), Color(0.1, 0.1, 0.12), Vector3.ZERO)
			_add_mesh(
				root, _cylinder(0.15, 0.15, 0.34), Color(0.1, 0.1, 0.12), Vector3(0.0, 0.18, 0.0)
			)
			_add_mesh(
				root, _cylinder(0.155, 0.155, 0.04), Color(0.85, 0.2, 0.3), Vector3(0.0, 0.06, 0.0)
			)
		&"crown":
			_add_mesh(root, _cylinder(0.19, 0.17, 0.2), Color(0.98, 0.82, 0.2), Vector3.ZERO)
	return root


static func _add_mesh(root: Node3D, mesh: Mesh, color: Color, offset: Vector3) -> void:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	mesh.surface_set_material(0, material)
	node.position = offset
	root.add_child(node)


static func _cone(radius: float, height: float) -> CylinderMesh:
	return _cylinder(0.02, radius, height)


static func _cylinder(top: float, bottom: float, height: float) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	return mesh
