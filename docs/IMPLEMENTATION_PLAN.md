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

Sizes: S (≲half day), M (≈1 day), L (multi-day). `⛓` = depends on.

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
Skill — [ ] **M4-05** Simon Stomp (M) · [x] **M4-06** Quick Draw (S) · [x] **M4-07** Hurdle Dash (L) · [ ] **M4-08** Target Range (M, mouse+stick aim) · [ ] **M4-09** Beat Bounce (M)
Team — [x] **M4-10** Tug of War (S) · [x] **M4-11** Relay Sprint (M) · [x] **M4-12** Cart Push (L) · [x] **M4-13** Color Clash (M)
Sabotage — [x] **M4-14** Poison Feast (M) · [x] **M4-15** Trap Corridor (L) · [x] **M4-16** Heist Night (M)

### M5 — Finale
- [x] **M5-01** (M) Buy-in shop: 30 s timer, four purchasables, coin math + GUT tests (SPEC §6) ⛓ M3-03
- [x] **M5-02** (L) The Gauntlet arena: shrinking platform, escalating hazards, lives/respawns, sabotage-token + grudge-vote hooks ⛓ M3-02
- [x] **M5-03** (S) Final ranking: elimination order → placement, coin tiebreaks; feeds podium ⛓ M5-02, M3-05

### M6 — Polish & feel
- [ ] **M6-01** (M) Audio pass: music loops (menu/round/finale), SFX for all shared chrome + per-minigame hooks
- [ ] **M6-02** (M) Juice pass: coin fly-to-HUD, screen shake, KO ragdolls, victory dances
- [x] **M6-03** (S) Reconnect overlay + graceful error toasts (room full, bad code, version mismatch)
- [ ] **M6-04** (M) UI theme unification + intro-card control diagrams for all 17 games

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
- [ ] **M8-08** (S) Migrate Quick Draw view to `MinigameView3D` ⛓ M8-01, M8-02
- [x] **M8-09** (S) Migrate Tug of War view to `MinigameView3D` ⛓ M8-01, M8-02
- [ ] **M8-10** (S) Migrate Color Clash view to `MinigameView3D` ⛓ M8-01, M8-02
- [ ] **M8-11** (S) Migrate Poison Feast view to `MinigameView3D` ⛓ M8-01, M8-02
- [x] **M8-12** (M) Finale Gauntlet client view — **new build, not a migration**: `gauntlet.gd` has server logic only today ⛓ M8-01, M5-02
- [ ] **M8-13** (S) Audit + wire `CharacterRig` into the lobby character-select screen if not already live (M2-03/M2-04 built the pieces; confirm they're actually mounted) ⛓ M8-01
- Any minigame task still unbuilt in M4 below should target `MinigameView3D` directly rather than the old `_draw()` pattern.

### M7 — Deployment & release
- [x] **M7-01** (M) Dockerfile + compose for the dedicated server; VPS deploy doc; version handshake (client/server protocol version) ⛓ M1-01
- [x] **M7-02** (M) Release pipeline: tagged builds → GitHub Releases artifacts for Win/Linux/macOS ⛓ M0-03
- [x] **M7-03** (M) Playtest checklist automation: 6 headless bot clients complete a full 12-round match nightly in CI ⛓ M1-05, M3-01
- [x] **M7-04** (S) In-game credits screen generated from `assets/CREDITS.md`

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
