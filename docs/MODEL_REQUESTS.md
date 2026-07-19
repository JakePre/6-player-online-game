# Model Requests — owner-run 3D generation ledger

The owner is standing up a 3D-model generation pipeline (#817, 2026-07-10) and
batch-generates on request, same flow as `IMAGE_REQUESTS.md`. Agents **never**
generate, scrape, or download models themselves — this file is the queue.
Quality is unproven; every row ships its primitive/Kenney fallback first.

## Workflow

1. **Request:** append a row to the table below (append-only, like
   `assets/CREDITS.md` — never edit or reorder another task's rows). Describe
   the object as you'd brief a modeler: what it is, the silhouette that must
   read at iso-camera distance, style anchors, and the target size in game
   units (a character rig stands ~1.8u).
2. **Generate:** the owner batches pending rows through the pipeline, does the
   cleanup pass (see checklist below), and commits the GLB to the listed
   destination (or attaches it to the requesting issue). The owner may
   regenerate or restyle — the prompt is a starting point, not a contract.
3. **Land:** the requesting task imports the delivered GLB, logs it in
   `assets/CREDITS.md` (author: owner-generated), flips the row's status to
   `landed`, and wires it in.

**Never block on a model.** Ship the primitive/Kenney-kit fallback first; the
model slots in when it arrives. A `requested` row is a follow-up, not a
dependency. If generation quality disappoints, rows simply stay `requested`
and the fallbacks remain shipped — nothing breaks.

## Conventions

- **Format:** `.glb` (single binary file, not `.gltf`+`.bin`), one object per
  file, transforms applied, pivot at the base center (floor contact point)
  unless the row says otherwise.
- **Budget:** chunky low-poly to match the Kenney kits — target **< 5k tris**
  for props, < 10k for hero/centerpiece objects. Flat-shaded or single-albedo
  looks right; PBR realism fights the art style.
- **Materials:** ONE material per model — vertex colors or a single albedo
  texture. No baked lighting/AO in the texture (the engine lights the scene,
  and per-game tints multiply over albedo, #589).
- **Orientation/scale:** Y-up, -Z forward (Godot convention). State the
  intended in-game size in the row; the landing agent scales on import, but a
  model exported near-correct avoids 100× surprises.
- **Rigging & animation support:** Static props are the default. However, rigged/animated requests (e.g. characters, enemies, dynamic hazards) can now also be filed. If requesting an animated asset, specify the required animation loops (e.g. walk, jump, attack, idle) in the prompt so they can be processed through the local Puppeteer rigging and animation pipeline.
- **Destination:** `assets/generated/models/<kebab-name>.glb`.
- **Row must name its consumer** (which game/issue) so the landing agent knows
  what to wire and can flip the row to `landed`.
- **Status values:** `requested` → `generated` (delivered, not yet wired) →
  `landed`. Withdrawn requests get `withdrawn`, not deleted.

### Owner cleanup checklist (before committing a generated GLB)

Image-to-3D output is rarely game-ready. Before a model lands in the repo:

- [ ] Decimate to the tri budget; delete interior/floating junk geometry.
- [ ] One material; bake or collapse to a single albedo (no normal/roughness —
      they won't survive the art style anyway).
- [ ] Remove baked-in lighting/shadows from the texture if present.
- [ ] Apply transforms; pivot at base center; sane real-size export.
- [ ] Test-import into Godot 4.4.1 and eyeball it next to a character rig
      before committing — a 30-second check that catches 90% of surprises.

## Requests

| ID | Task / issue | Prompt | Target size | Destination | Status |
|---|---|---|---|---|---|
| MDL-001 | #803 Basket Brawl 3D | Basketball hoop assembly: pole, backboard, orange rim with a simple low-poly net (solid geometry, not cloth). Chunky low-poly party-game style matching Kenney kits, readable silhouette from an isometric camera. Pivot at pole base. | ~3.5u tall, rim at ~2.6u | `assets/generated/models/basketball-hoop.glb` | landed |
| MDL-002 | #803 Basket Brawl 3D | Basketball: classic orange ball with black seam lines (painted-on albedo, not grooves). Low-poly sphere, reads as a basketball at distance. | ~0.35u diameter | `assets/generated/models/basketball.glb` | landed |
| MDL-003 | #791 Dodgeball | Dodgeball: soft rubber playground ball, two-tone (red with a pale equator band). Low-poly, distinct from MDL-002 at a glance. | ~0.4u diameter | `assets/generated/models/dodgeball.glb` | landed |
| MDL-004 | #808 Readable Siege | Castle gate: wooden double door with iron banding set in a stone arch frame, closed. Chunky low-poly, damage states handled in-engine (don't model cracks). Pivot at base center. | ~2.5u wide, ~3u tall | `assets/generated/models/castle-gate.glb` | landed |
| MDL-005 | #808 Readable Siege | Castle wall segment: straight stone wall with crenellated top, tileable end-to-end (flat square ends, no returns). Chunky low-poly, mid-tone stone. | ~4u long, ~2.5u tall | `assets/generated/models/castle-wall-segment.glb` | landed |
| MDL-006 | #785 Turbo Lap real course | Start/finish arch: checkered banner arch spanning a track, two simple pylons. Chunky low-poly, coin-gold + white checker accents. | ~8u span, ~3u tall | `assets/generated/models/finish-arch.glb` | landed |
| MDL-007 | #785 Turbo Lap real course | Track barrier: low red-and-white striped crash barrier segment, tileable end-to-end. Chunky low-poly. | ~2u long, ~0.6u tall | `assets/generated/models/track-barrier.glb` | landed |
| MDL-008 | #793 Putt Panic random course | Golf flagstick: thin pole with a triangular flag, small cup ring at the base. Chunky low-poly, coin-gold flag. | ~1.5u tall | `assets/generated/models/golf-flagstick.glb` | landed |
| MDL-009 | #918 Meteor Shower | Meteor: a craggy molten space rock, dark scorched crust with glowing orange-red fissures (painted-on albedo, not emissive geometry). Chunky low-poly, reads as danger falling from an isometric camera; roughly spherical silhouette so any spin looks right. Pivot at center. | ~1.2u diameter | `assets/generated/models/meteor.glb` | landed |
| MDL-010 | #919 King of the Hill | Hill crest: a low grassy mound/podium with a flat circular crest and gently sloped skirt — the zone players fight to hold. LOW profile (the zone drifts across the arena, so it must read fine sliding around); no roots, rocks, or overhangs past the base circle. Pivot at base center. | ~3u diameter, ~0.4u tall | `assets/generated/models/hill-crest.glb` | landed |
| MDL-011 | #919 King of the Hill | Shove horn: a chunky party air-horn / blast-horn pickup — canister with a flared bell, bold warning-orange body. Reads as "knockback item" at iso distance. Pivot at base center. | ~0.6u tall | `assets/generated/models/shove-horn.glb` | landed |
| MDL-012 | #919 King of the Hill | Anchor: a classic stylized ship anchor pickup — crossbar, curved flukes, thick shank, deep navy-blue with a lighter worn edge. Reads as "hold your ground" at iso distance. Pivot at base center. | ~0.7u tall | `assets/generated/models/anchor.glb` | landed |
| MDL-013 | #929 Cart Push | Mine cart: a classic wooden-slat mining cart with iron banding and four spoked wheels, heaped with glowing gold ore. The game's namesake object — must dominate its silhouette at iso distance (render audit: the current box cart is invisible). Pivot at base center, wheels touching ground. | ~1.8u long, ~1.2u tall | `assets/generated/models/mine-cart.glb` | landed |
| MDL-014 | #929 Bullet Waltz | Bullet emitter: an ornate music-box turret — a cylindrical brass music box with a rotating crank and small radial nozzles around its crown, elegant not military (the game is a waltz). Reads as "the danger source" at arena center. Pivot at base center. | ~1.2u tall | `assets/generated/models/music-box-emitter.glb` | landed |
| MDL-015 | #956 Turbo Lap | Go-kart: a chunky low-poly go-kart — open cockpit sized for a Kaykit rig to sit in, four fat wheels, a low spoiler. NEUTRAL grey/white body (the view tints panels per player color at runtime, so avoid baked-in saturated colors). Pivot at base center, wheels touching ground. | ~1.4u long, ~0.7u tall, seat at ~0.35u | `assets/generated/models/go-kart.glb` | landed |
| MDL-016 | #949 Blast Grid | Cursed skull token: a cartoonish purple-black skull pickup with faint emissive eye sockets — mischievous, not horror (it's a 50/50 gamble powerup). Reads as "risky" next to the plain powerups at iso distance. Pivot at base center. | ~0.5u tall | `assets/generated/models/skull-token.glb` | generated |
| MDL-017 | #954 Nom Arena | Power pellet: an oversized glowing orb pickup — warm white-gold core with a soft halo band, unmistakably "the special one" beside ordinary pellets. Simple sphere silhouette (the view pulses its scale/emission). Pivot at center. | ~0.6u diameter | `assets/generated/models/power-pellet.glb` | generated |
| MDL-018 | #817 owner request (consumers: Blast Grid soft walls #533, Wall Builders blocks) | Wooden crate: a classic square wooden shipping crate — light pine plank sides with a simple frame border and four corner posts, painted-on plank seams and nail heads (albedo only, no grooves). Must read as one clean cube crate at iso distance; upgrades the flat crate-face BoxMesh (IMG-059). Pivot at base center. | ~1u cube | `assets/generated/models/wooden-crate.glb` | landed |
| MDL-019 | #935 Hat Shop | Party cone hat: a classic conical birthday party hat — bright candy stripes (pink/white), a small pom-pom at the tip, a thin chin-elastic hint. Sits on a Kaykit rig's head bone. Reads as "party!" at iso distance. Replaces the primitive cone placeholder. Pivot at the brim base (head-bone origin). | ~0.4u tall | `assets/generated/models/hat-party-cone.glb` | landed |
| MDL-020 | #935 Hat Shop | Top hat: a tall stylized black top hat with a red band and a subtle satin sheen, slightly cartoon-proportioned (a touch wide-brimmed) so it reads at iso distance. Sits on a Kaykit rig's head bone. Replaces the primitive cylinder placeholder. Pivot at the brim base (head-bone origin). | ~0.4u tall, ~0.35u brim | `assets/generated/models/hat-top-hat.glb` | landed |
| MDL-021 | #935 Hat Shop | Gold crown: a chunky low-poly royal crown — five points tipped with tiny gem nubs, warm gold body with a jeweled band, worn-edge highlights. Sits on a Kaykit rig's head bone; the priciest wardrobe unlock, must read "champion." Replaces the primitive band placeholder. Pivot at the band base (head-bone origin). | ~0.25u tall, ~0.38u diameter | `assets/generated/models/hat-crown.glb` | landed |
