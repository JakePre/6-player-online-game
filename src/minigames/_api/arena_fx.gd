class_name ArenaFX
extends RefCounted
## Shared one-shot arena effects (M13-01, PHASE2.md $9): impact bursts,
## pickup sparkles, splashes and dust puffs. Every effect is a self-freeing
## CPUParticles3D — spawn it and forget it — so per-game M13 tasks stay
## one-file view changes. CPUParticles3D (not GPU) keeps effects working on
## every export target and headless-safe in tests.

const DEFAULT_BURST_COLOR := Color(1.0, 0.85, 0.4)
const WATER_COLOR := Color(0.5, 0.75, 0.95)
const DUST_COLOR := Color(0.65, 0.6, 0.55)


## Radial impact burst: KOs, shoves, meteor hits.
static func burst(
	parent: Node,
	position: Vector3,
	color: Color = DEFAULT_BURST_COLOR,
	amount: int = 16,
	speed: float = 5.0,
	lifetime: float = 0.5
) -> CPUParticles3D:
	var particles := _one_shot(parent, position, color, amount, lifetime)
	particles.direction = Vector3.UP
	particles.spread = 180.0
	particles.initial_velocity_min = speed * 0.6
	particles.initial_velocity_max = speed
	particles.gravity = Vector3(0.0, -9.0, 0.0)
	return particles


## Small rising twinkle: pickups, banked coins, claims.
static func sparkle(
	parent: Node, position: Vector3, color: Color = DEFAULT_BURST_COLOR
) -> CPUParticles3D:
	var particles := _one_shot(parent, position, color, 10, 0.4)
	particles.direction = Vector3.UP
	particles.spread = 35.0
	particles.initial_velocity_min = 2.0
	particles.initial_velocity_max = 3.5
	particles.gravity = Vector3(0.0, 2.0, 0.0)
	particles.scale_amount_min = 0.5
	return particles


## Flat outward splash ring: water entries, ring-outs, falls.
static func splash(parent: Node, position: Vector3, color: Color = WATER_COLOR) -> CPUParticles3D:
	var particles := _one_shot(parent, position, color, 20, 0.45)
	particles.direction = Vector3.UP
	particles.spread = 85.0
	particles.flatness = 0.8
	particles.initial_velocity_min = 3.0
	particles.initial_velocity_max = 4.5
	particles.gravity = Vector3(0.0, -12.0, 0.0)
	return particles


## Low billowy puff: landings, skids, crumbles.
static func dust(parent: Node, position: Vector3, color: Color = DUST_COLOR) -> CPUParticles3D:
	var particles := _one_shot(parent, position, color, 12, 0.6)
	particles.direction = Vector3.UP
	particles.spread = 80.0
	particles.initial_velocity_min = 0.8
	particles.initial_velocity_max = 1.6
	particles.gravity = Vector3(0.0, 0.5, 0.0)
	particles.scale_amount_max = 2.0
	return particles


static func _one_shot(
	parent: Node, position: Vector3, color: Color, amount: int, lifetime: float
) -> CPUParticles3D:
	var particles := CPUParticles3D.new()
	particles.one_shot = true
	particles.emitting = true
	particles.explosiveness = 1.0
	particles.amount = amount
	particles.lifetime = lifetime
	particles.color = color
	var mesh := SphereMesh.new()
	mesh.radius = 0.07
	mesh.height = 0.14
	particles.mesh = mesh
	particles.position = position
	# Fire and forget: the node frees itself when the last particle dies.
	particles.finished.connect(particles.queue_free)
	parent.add_child(particles)
	return particles
