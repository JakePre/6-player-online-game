# Party Rush — Implementation Plan

**Companion to [SPEC.md](SPEC.md)** (the source of truth for game design). This document tells contributing agents *how* the project is built, *in what order*, and *which tasks are safe to work in parallel*.

---

## 1. How agents should work in this repo

1. **Read SPEC.md first.** Locked decisions in SPEC §2 are not negotiable; deviations need an explicit note in the PR description.
2. **Follow [AGENT_COORDINATION.md](AGENT_COORDINATION.md).** It is the binding procedure for claiming tasks, path ownership, hotspot files, and the serialized merge protocol that keeps parallel agents conflict-free.
3. **Claim a task** by opening a GitHub issue (or commenting on an existing one) named after the task ID below (e.g. `M4-07 Sumo Smash`), then branch as `feat/<task-id>-<slug>`.
4. **One task = one PR.** Keep PRs reviewable; link the task ID. Update the checkbox in this file in the same PR.
5. **Never break `main`.** `main` must always open in the Godot editor without errors and pass CI. Milestone M0/M1 land first; everything else builds on their interfaces.
6. **Minigames are the parallel workhorse.** After M3 merges, all 17 minigame tasks (M4) are independent and can be built concurrently by different agents against the Minigame Contract.
7. Assets: CC0/CC-BY only, log every import in `assets/CREDITS.md` (see SPEC §10).

## 2. Tech baseline

- **Godot 4.4.x stable**, GDScript, typed GDScript everywhere (`--warnings-as-errors` in CI).
- Single Godot project at repo root serving both client and dedicated server (feature tag `dedicated_server` for the headless export).
- Formatting/lint: `gdformat` + `gdlint` (gdtoolkit) enforced in CI.
- Unit tests: **GUT** (Godot Unit Test) for pure logic (economy, ranking, room codes, minigame result math).
- CI: GitHub Actions — lint, GUT tests, and export builds (Win/Linux/macOS client + Linux server) on every PR.

## 3. Repository layout (target)

```
project.godot
addons/gut/
src/
  core/            # match state machine, economy, rng, room model
  net/             # transport, session/rejoin, replication helpers, rpc conventions
  server/          # room manager, headless entrypoint, minigame result authority
  client/          # app shell, scene routing, settings, connection UI
  lobby/           # lobby scene, character select, ready-up
  match/           # HUD, intro cards, results, leaderboard interstitial, podium
  minigames/
    _api/          # MinigameBase, contract resources, shared arena helpers
    coin_scramble/ # one folder per minigame: scene + script + local assets
    ...
  finale/          # The Gauntlet + buy-in shop
  characters/      # roster resources, color/outline shader, animation proxy
  ui/              # theme, shared widgets, emote wheel
assets/            # imported third-party packs + CREDITS.md
server/deploy/     # Dockerfile, compose, systemd notes
tests/             # GUT tests
docs/
```

## 4. Core interfaces (build once, in M1–M3, everything depends on them)

### Minigame Contract (`src/minigames/_api/`)
Every minigame is a scene whose root script extends `MinigameBase` and provides:

```gdscript
class_name MinigameMeta extends Resource
@export var id: StringName            # "coin_scramble"
@export var display_name: String
@export var category: Category        # FFA | SKILL | TEAM | SABOTAGE
@export var min_players: int          # per SPEC §7
@export var max_players: int = 6
@export var duration_sec: float
@export var rules_text: String        # one-liner for the intro card
@export var controls_diagram: Texture2D
@export var team_layouts: Array       # e.g. [[3,3],[2,2,2]] or [] for FFA
```

`MinigameBase` (server-authoritative) lifecycle: `setup(players, rng_seed)` → `countdown()` → `play()` → emits `finished(results: MinigameResults)` where `MinigameResults = { placements: Array[Array[peer_id]], pickup_coins: Dictionary }` (placements support ties; economy applies SPEC §5). The framework — not the minigame — handles intro card, timer HUD, results screen, and coin awards.

### Match state machine (`src/core/`)
`LOBBY → ROUND_INTRO → ROUND_PLAY → ROUND_RESULTS → (LEADERBOARD) → … → FINALE_SHOP → FINALE_PLAY → PODIUM → LOBBY`. Server drives transitions; clients render. Deterministic minigame selection from a server RNG seed, respecting player count + category variety rules (SPEC §4).

### Net conventions (`src/net/`)
- Server authoritative; clients send `input_intent` unreliable-ordered, server replicates snapshots at 30 Hz with `MultiplayerSynchronizer` or custom delta sync (decided in M1-03 spike).
- Session token issuance + rejoin flow per SPEC §9.
- All RPCs live in clearly named `*_rpc.gd` files; no gameplay mutation outside the server.

## 5. Milestones & task board

Sizes: S (≲half day), M (≈1 day), L (multi-day). `⛓` = depends on. Every remaining task also carries a recommended model tier (complexity signal, not an assignment) in [MODEL_ROUTING.md](MODEL_ROUTING.md).

### M0 — Repo & toolchain bootstrap
- [x] **M0-01** (M) Godot 4.4 project scaffold at repo root, folder layout §3, project settings (window, physics tick 30 Hz, input map for WASD/gamepad/mouse)
- [x] **M0-02** (S) gdtoolkit config + pre-commit; `.editorconfig`; `.gitignore`/`.gitattributes` for Godot
- [x] **M0-03** (M) GitHub Actions CI: lint + GUT + export presets (Win/Linux/macOS client, Linux `dedicated_server`) ⛓ M0-01
- [x] **M0-04** (S) `assets/CREDITS.md` template + first asset import: 2 KayKit character packs (9 rigged+animated characters); Kenney kits deferred to first arena work (M3) ⛓ M0-01
- [x] **M0-05** (S) Issue/PR templates referencing this plan's task IDs

### M1 — Networking core (the risk milestone — do first, keep small)
- [x] **M1-01** (L) ENet server/client bootstrap: headless entrypoint, connect/disconnect, peer registry, `--server` flag ⛓ M0-01
- [x] **M1-02** (M) Room manager: create/join by 6-char code, host role, room lifecycle + 5-min expiry ⛓ M1-01
- [x] **M1-03** (L) Replication decision: custom room-scoped snapshots (rationale + revisit trigger in `docs/adr/001-replication.md`); validated by the M1-05 soak rather than a separate spike ⛓ M1-01
- [x] **M1-04** (M) Session tokens + rejoin flow (rejoin restores slot/score, sits out current round) ⛓ M1-02
- [x] **M1-05** (M) Fake-lag/loss test harness + 6-client headless soak script (`tests/soak/run_soak.py`, runs in CI) ⛓ M1-03

### M2 — Lobby & app shell
- [x] **M2-01** (M) Client app shell: main menu (Host / Join code / Settings), scene router, connection status UI ⛓ M1-02
- [x] **M2-02** (M) Lobby scene: player list, ready-up, round-count setting (8/12/15), start gating ⛓ M2-01
- [x] **M2-03** (M) Character select: 8-character roster resources, color assignment, duplicate handling ⛓ M2-01, M0-04
- [x] **M2-04** (M) Character rendering kit: orthographic camera rig, outline/nameplate-through-walls shader, shared animation proxy ⛓ M0-04
- [x] **M2-05** (S) Settings screen: audio, window mode, server address override

### M3 — Match framework (unblocks all minigames)
- [x] **M3-01** (L) Match state machine + server-side minigame selector (variety + player-count rules) ⛓ M1-03
- [x] **M3-02** (M) Minigame Contract: `MinigameMeta`, `MinigameBase`, `MinigameResults`, arena helpers, template minigame folder ⛓ M3-01
- [x] **M3-03** (M) Economy: placement tables, team awards, pickup caps, tie handling — pure logic + GUT tests (SPEC §5) ⛓ M3-01
- [x] **M3-04** (M) Round chrome: intro card (rules/controls/skip), countdown, results screen, running-total HUD ⛓ M3-02
- [x] **M3-05** (S) Leaderboard interstitial every 5 rounds + podium/match-summary scene ⛓ M3-04
- [x] **M3-06** (M) **Reference minigame: Coin Scramble (#1)** — proves the whole contract end-to-end; template for all M4 work ⛓ M3-02, M3-03, M3-04
- [x] **M3-07** (S) Quick-emote wheel (6 emotes, replicated) ⛓ M3-02

### M4 — Minigame production (all parallel after M3-06; each task: scene, server logic, 2/4/6-player balance pass, SFX hooks)
FFA — [x] **M4-01** King of the Hill (M) · [x] **M4-02** Hot Potato (M) · [x] **M4-03** Thin Ice (M) · [x] **M4-04** Sumo Smash (M)
Skill — [x] **M4-05** Simon Stomp (M) · [x] **M4-06** Quick Draw (S) · [x] **M4-07** Hurdle Dash (L) · [x] **M4-08** Target Range (M, mouse+stick aim) · [x] **M4-09** Beat Bounce (M)
Team — [x] **M4-10** Tug of War (S) · [x] **M4-11** Relay Sprint (M) · [x] **M4-12** Cart Push (L) · [x] **M4-13** Color Clash (M)
Sabotage — [x] **M4-14** Poison Feast (M) · [x] **M4-15** Trap Corridor (L) · [x] **M4-16** Heist Night (M)

### M5 — Finale
- [x] **M5-01** (M) Buy-in shop: 30 s timer, four purchasables, coin math + GUT tests (SPEC §6) ⛓ M3-03
- [x] **M5-02** (L) The Gauntlet arena: shrinking platform, escalating hazards, lives/respawns, sabotage-token + grudge-vote hooks ⛓ M3-02
- [x] **M5-03** (S) Final ranking: elimination order → placement, coin tiebreaks; feeds podium ⛓ M5-02, M3-05

### M6 — Polish & feel
- [x] **M6-01** (M) Audio pass: music loops (menu/round/finale), SFX for all shared chrome + per-minigame hooks
- [x] **M6-02** (M) Juice pass: coin fly-to-HUD, screen shake, KO ragdolls, victory dances
- [x] **M6-03** (S) Reconnect overlay + graceful error toasts (room full, bad code, version mismatch)
- [x] **M6-04** (M) UI theme unification + intro-card control diagrams for all 17 games

### M8 — 3D iso-arena visual overhaul (closes the SPEC §2 visual gap; see `docs/adr/002-iso-arena-rendering.md`)
Audit finding motivating this milestone: `CharacterRig`/`IsoCameraRig` (M2-04)
are unused anywhere in `src/` today; every shipped minigame view instead
paints flat 2D `Control._draw()` shapes on a grey background, and the finale
has no client view yet. M8-01/02 are the prerequisite framework + assets;
M8-03..11 (one per shipped minigame) then become independent and
parallelizable exactly like the original M4 fan-out — claim/branch/PR the
same way (§1, `AGENT_COORDINATION.md` §2).
- [x] **M8-01** (L) `MinigameView3D` base: `SubViewportContainer`/`SubViewport` hosting a `Node3D` arena (IsoCameraRig instance, fixed light rig, floor helper) + a per-slot `CharacterRig` pool sourced from `CharacterRoster`/`PlayerPalette`/`NetManager.my_room_state`; `MinigameView`'s `setup`/`render` contract is unchanged. Owns `src/minigames/_api/`, additive-only changes in `src/characters/` ⛓ none
- [x] **M8-02** (S) Kenney CC0 kit import pass #1 — done ahead of the framework task: `platformer-kit` (153 GLB, floor/platform/ramp pieces), `food-kit` (200 GLB, Poison Feast dishes), `nature-kit` (329 GLB, vertex-colored dressing), `city-kit-commercial` (41 GLB, Heist Night buildings) imported to `assets/environment/kenney_*/` with `.import` sidecars generated and logged in `assets/CREDITS.md` ⛓ none
- [x] **M8-03** (S) Migrate Coin Scramble view to `MinigameView3D` ⛓ M8-01, M8-02
- [x] **M8-04** (S) Migrate King of the Hill view to `MinigameView3D` ⛓ M8-01, M8-02
- [x] **M8-05** (S) Migrate Hot Potato view to `MinigameView3D` ⛓ M8-01, M8-02
- [x] **M8-06** (S) Migrate Thin Ice view to `MinigameView3D` ⛓ M8-01, M8-02
- [x] **M8-07** (S) Migrate Sumo Smash view to `MinigameView3D` ⛓ M8-01, M8-02
- [x] **M8-08** (S) Migrate Quick Draw view to `MinigameView3D` ⛓ M8-01, M8-02
- [x] **M8-09** (S) Migrate Tug of War view to `MinigameView3D` ⛓ M8-01, M8-02
- [x] **M8-10** (S) Migrate Color Clash view to `MinigameView3D` ⛓ M8-01, M8-02
- [x] **M8-11** (S) Migrate Poison Feast view to `MinigameView3D` ⛓ M8-01, M8-02
- [x] **M8-12** (M) Finale Gauntlet client view — **new build, not a migration**: `gauntlet.gd` has server logic only today ⛓ M8-01, M5-02
- [x] **M8-13** (S) Audit + wire `CharacterRig` into the lobby character-select screen if not already live (M2-03/M2-04 built the pieces; confirm they're actually mounted) ⛓ M8-01
- Any minigame task still unbuilt in M4 below should target `MinigameView3D` directly rather than the old `_draw()` pattern.

### M7 — Deployment & release
- [x] **M7-01** (M) Dockerfile + compose for the dedicated server; VPS deploy doc; version handshake (client/server protocol version) ⛓ M1-01
- [x] **M7-02** (M) Release pipeline: tagged builds → GitHub Releases artifacts for Win/Linux/macOS ⛓ M0-03
- [x] **M7-03** (M) Playtest checklist automation: 6 headless bot clients complete a full 12-round match nightly in CI ⛓ M1-05, M3-01
- [x] **M7-04** (S) In-game credits screen generated from `assets/CREDITS.md`

### M9 — Mutators (Phase 2, [PHASE2.md](PHASE2.md) §3 — framework knobs only, host curates + rounds roll)
- [x] **M9-01** (M) Mutator framework: `Mutator` resource + `MutatorCatalog`, framework knobs (award multiplier, pickup-cap scale, duration scale, server-side input transform, view flags, round-end coin transfer), GUT tests ⛓ none
- [x] **M9-02** (S) Lobby mutator pool: host-only toggles replicated like round count; PROTOCOL_VERSION bump ⛓ M9-01
- [x] **M9-03** (S) Per-round roll (~40% of rounds, no repeats back-to-back, never the finale) + intro-card announcement ⛓ M9-01, M9-02
- [x] **M9-04** (M) Mutator pack A: Double Coins, Golden Round, Short Fuse, Overdrive (economy/duration/speed knobs) ⛓ M9-03
- [x] **M9-05** (M) Mutator pack B: Mirror Mode, Blackout, Masquerade, Robin Hood (input/view/transfer knobs) ⛓ M9-03
- [x] **M9-06** (S) Nightly soak variant: full match with random mutators enabled ⛓ M9-04, M9-05, M7-03

### M10 — Roster wave 2 (Phase 2, PHASE2.md §4 — 16 games, parallel after M9-01; per game: sim + MinigameView3D view + tests + one catalog line)
FFA — [x] **M10-01** Meteor Shower (M) · [x] **M10-02** Musical Platforms (M) · [x] **M10-03** Shock Tag (M) · [x] **M10-04** Treasure Divers (M)
Skill — [x] **M10-05** Memory Match (M) · [x] **M10-06** Laser Limbo (M) · [x] **M10-07** Bullseye Bowl (M) · [x] **M10-08** Count Quick (S)
Team — [x] **M10-09** Basket Brawl (L) · [x] **M10-10** Wall Builders (M) · [x] **M10-11** Snake Chain (M) · [x] **M10-12** Fort Siege (L)
Sabotage — [x] **M10-13** The Mole (M) · [ ] **M10-14** Pickpocket Plaza (M) · [x] **M10-15** Bomb Courier (M) · [x] **M10-16** Faulty Wiring (M)
Action — [x] **M10-17** Rumble Ring (M, arena brawler: swing/charge/block, KO scoring) · [x] **M10-18** Bullet Waltz (M, bullet-hell survival: seeded patterns, graze coins)

### M11 — Series mode (Phase 2, PHASE2.md §5 — best-of-N, ephemeral)
- [x] **M11-01** (M) Series controller wrapping match flow: Single/Bo3/Bo5 lobby setting, 10/7/5/4/3/2 series points with SPEC §5 tie sharing, champion decision + coin tiebreak ⛓ none
- [x] **M11-02** (S) Series scoreboard interstitial between matches + champion podium variant (StandingsPanel reuse) ⛓ M11-01, M3-05
- [x] **M11-03** (S) Rejoin-across-matches semantics + soak coverage; PROTOCOL_VERSION bump if the series setting adds RPCs ⛓ M11-01, M7-03

### M12 — Feel & fairness (Phase 2, PHASE2.md §6 — after the roster completes)
- [ ] **M12-01** (M) Balance pass across all 33 games at 2/4/6 players, driven by nightly-run data; tuning-only PRs ⛓ M10 complete
- [ ] **M12-02** (S) `play_sfx` hook adoption in every minigame view (pickups/hits/KOs) ⛓ M6-01, M10 complete
- [x] **M12-03** (M) Accessibility: colorblind-safe palette variant, input remapping UI, reduced-motion toggle ⛓ M6-02
- [x] **M12-04** (M) Latency feel: client-side snapshot interpolation in `MinigameView3D` (30 Hz snapshots → smooth 60+ fps motion) ⛓ M8-01
- [ ] **M12-05** (S) Input parity audit: every minigame playable gamepad-only and keyboard/mouse-only; add a stick-driven tile cursor to Trap Corridor's trap placement ⛓ M10 complete

### M13 — Animation & asset pass (PHASE2.md §9 — owner directive #262: "if an asset or animation would improve the experience, add it")
View-only, one game per PR, respect the §7 presentation tiers (Hurdle Dash / Relay Sprint / Heist Night get 2D juice, never a 3D upgrade). CC0/CC-BY only, log every import in `assets/CREDITS.md`. All per-game tasks are parallel after M13-01.
- [x] **M13-01** (M) Shared FX helpers: one-shot self-freeing impact bursts, pickup sparkles, splash + dust puffs (`src/minigames/_api/`), plus MinigameView3D convenience wrappers ⛓ none
FFA — [x] **M13-02** Coin Scramble (S, coin pickup sparkle + spawn drop-in) · [x] **M13-03** King of the Hill (S, zone shimmer + contest FX; pairs with #266) · [x] **M13-04** Hot Potato (S, bomb trail + blast; builds on #219) · [x] **M13-05** Thin Ice (S, crack decals + splash on falls) · [x] **M13-06** Sumo Smash (S, shove impact + ring-out splash) · [x] **M13-07** Meteor Shower (S, FALLING METEOR models: streak, impact burst, crater flash) · [x] **M13-08** Musical Platforms (S, platform pulse on the beat + claim flash) · [x] **M13-09** Shock Tag (S, zap arc on tags + crackle ring) · [x] **M13-10** Treasure Divers (S, bubbles, dive splash, surface gasp)
Skill — [x] **M13-11** Quick Draw (S, muzzle flash + holster anims) · [x] **M13-12** Memory Match (S, tile flip/reveal animation) · [x] **M13-13** Laser Limbo (S, beam hum shimmer + hit spark) · [x] **M13-14** Bullseye Bowl (S, ball spin, ring hit flash, pin wobble) · [x] **M13-15** Count Quick (S, swarm props as animated critters) · [x] **M13-16** Simon Stomp (S, stomp ripples; pairs with #267) · [x] **M13-17** Target Range (S, tracer + target break; pairs with #214) · [x] **M13-18** Beat Bounce (S, beat-synced bounce FX; pairs with #264) · [x] **M13-19** Fish Frenzy (S, SWIMMING FISH: lane fish that actually swim)
Team — [x] **M13-20** Tug of War (S, rope strain + heave dust; builds on #223) · [x] **M13-21** Color Clash (S, paint splats + coverage shimmer) · [x] **M13-22** Relay Sprint (S, 2D: speed lines + baton flash) · [x] **M13-23** Cart Push (S, wheel dust + strain anims — coordinate with #175 rework) · [x] **M13-24** Bomb Courier (S, fuse spark trail + handoff flash)
Sabotage — [x] **M13-25** Poison Feast (S — coordinate with #174 rework) · [x] **M13-26** Trap Corridor (S, trap arm/spring animations) · [x] **M13-27** Heist Night (S, 2D: blueprint scanline sweep + steal pulse)
Action & finale — [x] **M13-28** Rumble Ring (S, swing arc FX; pairs with #263) · [x] **M13-29** Bullet Waltz (S, bullet tracers + graze sparks) · [x] **M13-30** Hurdle Dash (S, 2D: speed lines, hurdle clip spark) · [x] **M13-31** Gauntlet finale (S, hazard telegraphs + platform crumble)

### M14 — Genre Hop (PHASE2.md §8) — ⛔ GATED: claimable only when every M10/M12/M13 box above is checked
Owner-requested — [ ] **M14-01** Loadout Duel (L) · [ ] **M14-02** Turbo Lap (L) · [ ] **M14-03** Knock-Off (L) · [ ] **M14-04** Shred Session (M) · [ ] **M14-05** Ro-Sham-Bo Royale (S)
Approved — [ ] **M14-06** Blast Grid (M) · [ ] **M14-08** Putt Panic (M) · [ ] **M14-09** Tumble Run (L) · [ ] **M14-10** Nom Arena (M, 60 s hard cap — owner wants it QUICK) · ~~M14-07 cut by owner~~

### M15 — 24-player scaling (owner directive 2026-07-04; full matrix in [docs/adr/003-player-count-24.md](adr/003-player-count-24.md)) — ⛔ per-game caps GATED on the framework tasks landing first
Framework (unblocks everything; do first) — [x] **M15-01** room/net cap 6→24 + verify 30 Hz snapshot cost at 24 · [x] **M15-02** identity beyond 6 colours (expand palette + always-on nameplate numbers) · [x] **M15-03** placement-scoring formula for N≤24 + N-team award tables · [x] **M15-04** arena/economy scale-with-player-count helper · [x] **M15-05** spawn-layout helper (multi-ring/grid for dense counts) · [x] **M15-06** large-room lobby + results + coin-fly UI (≤24 rows) · [x] **M15-07** many-player view layouts (arc/multi-column lanes)
Per-game caps — one task per game to raise `max_players` to its ADR 003 target (**24**: Beat Bounce, Bullseye Bowl, Color Clash, Count Quick, Hurdle Dash, Memory Match, Quick Draw, Simon Stomp, Tug of War, Bullet Waltz†, Laser Limbo†, Target Range† · **12**: Coin Scramble, King of the Hill, Meteor Shower, Musical Platforms, Poison Feast, Relay Sprint, Snake Chain, Thin Ice, Treasure Divers · **8 by design**: Sumo Smash, Rumble Ring, Shock Tag, Hot Potato, Cart Push, Wall Builders, Bomb Courier, Heist Night, Trap Corridor, Fish Frenzy). Finale (Gauntlet) → 24. Games capped at 6–8 need only M15-01..03; †-marked 24s depend on M15-04. Claim per game from the ADR matrix.

## 6. Suggested build order / critical path

```
M0 → M1 (risk first: networking) → M3-01..06 (framework + reference minigame)
                     ↘ M2 (lobby, parallel with M3)
M3-06 done → fan out M4 minigames (parallel) + M5 finale
                     ↘ M8-01/02 (iso-arena framework + assets) → fan out M8-03..13 (parallel)
→ M6 polish → M7 release
```

The critical path is **M0 → M1 → M3 → M4**. M2 and M5 can proceed in parallel once their dependencies land. Get one full playable loop (menu → lobby → 3 rounds of Coin Scramble → podium) working end-to-end before mass-producing minigames — this is the **vertical slice** gate. M8 can start any time after M2-04/M3-02 (both already done) — it does not block M4/M5/M6/M7, but M6-02's "juice pass" and M6-04's "control diagrams for all 17 games" will land on top of whatever presentation tier each minigame is on at the time, so finishing M8's fan-out before M6 starts is strongly preferred.

## 7. Testing strategy

- **Unit (GUT):** economy math, ranking/tiebreaks, room-code generation, minigame selector rules, shop math.
- **Integration:** headless server + N scripted bot clients (M1-05 harness); nightly full-match soak (M7-03).
- **Manual matrix per minigame PR:** 2, 4, and 6 players; one forced disconnect+rejoin; keyboard + gamepad.
- **Latency:** every movement-based minigame must be tested with the fake-lag harness at 80 ms / 5% loss and remain fair.

## 8. Risks & mitigations

| Risk | Mitigation |
|---|---|
| Godot high-level sync insufficient for fast minigames | M1-03 spike decides early; custom snapshot fallback documented in ADR |
| 17 minigames balloon scope | Contract makes each one small; vertical-slice gate before fan-out; cut list order if needed: M4-12, M4-15, M4-07 (the L-sized ones) |
| Rejoin edge cases corrupt match state | Rejoiners always wait for next round boundary (SPEC §9); soak test covers it |
| Asset style clash | Single source rule (KayKit + Kenney only) keeps everything cohesive |
| macOS export signing friction | v1 ships unsigned with documented "right-click → open" instructions; signing deferred |
