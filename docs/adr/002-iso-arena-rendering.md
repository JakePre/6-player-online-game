# ADR 002: 3D iso-arena rendering for minigame views (SubViewport-embedded)

**Status:** Accepted (M8-01 built; Coin Scramble migrated as the M8-03 validation case)
**Date:** 2026-07-02

## Context

SPEC §2 locks the visuals as **"2.5D isometric — 3D low-poly scenes rendered
with a fixed orthographic camera."** M2-04 delivered exactly the kit that
decision calls for: `CharacterRig` (KayKit GLB models behind a semantic
animation proxy, with the player-color outline/x-ray identity shader from
SPEC §3/§11) and `IsoCameraRig` (an orthographic `Camera3D`).

An audit for this ADR found **zero call sites for either class anywhere in
`src/`** — not in the lobby/character-select screen, not in any of the 9
shipped minigame views, not in the finale. Instead, every `MinigameView`
subclass (`extends MinigameView`, which `extends Control`) paints flat 2D
primitives straight onto a plain grey `Control` with `_draw()`
(`draw_rect`, `draw_circle`, `draw_arc`) — e.g. `thin_ice_view.gd`,
`sumo_smash_view.gd`. This is the "looks like shit, just 2D shapes and grey"
regression versus the locked decision: the M4 minigames were built on a
placeholder presentation tier that was never swapped for the real one.
The finale (`gauntlet.gd`) has no client view scene at all yet — M5-02/03
only built the server-side arena logic.

## Decision

Keep `MinigameView`'s contract exactly as-is (`extends Control`,
`setup(names, slot)`, `render(game)` — `match_screen.gd`'s `_mount_view`
does not change). Add a new base, `MinigameView3D extends MinigameView`,
that embeds a full-rect `SubViewportContainer` → `SubViewport` hosting a
`Node3D` arena world:

- one `IsoCameraRig` instance,
- a small fixed lighting rig (key/fill + environment),
- an arena floor/platform helper built from Kenney CC0 kit pieces (SPEC §10
  already names platformer/city/food kits; confirmed fetchable as
  ready-to-use CC0 GLB — see `assets/CREDITS.md` "Planned sources"),
- a pooled `CharacterRig` per player slot, built from
  `CharacterRoster.scene_for(member.character_id)` and
  `PlayerPalette.color_for_slot(slot)`.

Subclasses override a new `_render_3d(game)` instead of `_draw()`, mapping
each minigame's existing top-down world-unit coordinates (the sim already
works in world units — e.g. `ThinIce`'s `state[0], state[1]` — only the
*presentation* was 2D) onto the arena's X/Z plane. No coordinate-system
rewrite is needed in any `MinigameBase` subclass; this is a presentation-tier
swap only.

`character_id` is already replicated per room member
(`src/core/room_member.gd`), so the view can read
`NetManager.my_room_state.members` directly for the character-per-slot
mapping — no net/contract change required.

### Reasons

- Matches the locked SPEC decision instead of re-litigating it.
- Reuses the M2-04 investment instead of leaving it dead code.
- `SubViewport` keeps the 3D world fully inside the existing `Control` tree,
  so match chrome (`match_screen.gd`, intro/results panels, `%PlayArea`
  mount point) needs zero changes.
- Per-minigame server simulation files (`<id>.gd`) are untouched — only
  `<id>_view.gd`/`.tscn` change, preserving the M4 path-ownership rule
  (`src/minigames/<id>/` only, per `AGENT_COORDINATION.md` §3), so the
  migration stays parallelizable exactly like the original M4 build-out.

### Costs accepted

- One extra `SubViewport` render per mounted minigame (acceptable: only one
  minigame view is ever mounted at a time).
- Each minigame's view file grows (arena/prop setup, player-rig positioning)
  versus a `_draw()` one-liner; mitigated by putting shared boilerplate in
  `MinigameView3D`.
- New asset dependency (Kenney kits) needs the same CREDITS.md logging
  discipline as the character packs (SPEC §10 rule).

## Consequences

- New milestone **M8** (see `IMPLEMENTATION_PLAN.md`) tracks the shared
  framework, the asset import pass, and one migration task per shipped
  minigame + the (currently unbuilt) finale view.
- Any minigame still unbuilt (Simon Stomp, Hurdle Dash, Target Range, Beat
  Bounce, Relay Sprint, Cart Push, Trap Corridor, Heist Night) should build
  directly on `MinigameView3D`, not the old `_draw()` pattern — do not add
  new debt to the pile this ADR is paying down.
- Revisit trigger: if `SubViewport` compositing is too slow on modest
  integrated-GPU laptops (the desktop min-spec target, SPEC §2), consider
  rendering the 3D world directly in the main viewport instead of a
  SubViewport. Check this note before re-opening that debate.
