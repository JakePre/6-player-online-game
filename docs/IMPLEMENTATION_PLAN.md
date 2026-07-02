# Party Rush — Implementation Plan

**Companion to [SPEC.md](SPEC.md)** (the source of truth for game design). This document tells contributing agents *how* the project is built, *in what order*, and *which tasks are safe to work in parallel*.

---

## 1. How agents should work in this repo

1. **Read SPEC.md first.** Locked decisions in SPEC §2 are not negotiable; deviations need an explicit note in the PR description.
2. **Claim a task** by opening a GitHub issue (or commenting on an existing one) named after the task ID below (e.g. `M4-07 Sumo Smash`), then branch as `feat/<task-id>-<slug>`.
3. **One task = one PR.** Keep PRs reviewable; link the task ID. Update the checkbox in this file in the same PR.
4. **Never break `main`.** `main` must always open in the Godot editor without errors and pass CI. Milestone M0/M1 land first; everything else builds on their interfaces.
5. **Minigames are the parallel workhorse.** After M3 merges, all 17 minigame tasks (M4) are independent and can be built concurrently by different agents against the Minigame Contract.
6. Assets: CC0/CC-BY only, log every import in `assets/CREDITS.md` (see SPEC §10).

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
- [ ] **M0-01** (M) Godot 4.4 project scaffold at repo root, folder layout §3, project settings (window, physics tick 30 Hz, input map for WASD/gamepad/mouse)
- [ ] **M0-02** (S) gdtoolkit config + pre-commit; `.editorconfig`; `.gitignore`/`.gitattributes` for Godot
- [ ] **M0-03** (M) GitHub Actions CI: lint + GUT + export presets (Win/Linux/macOS client, Linux `dedicated_server`) ⛓ M0-01
- [ ] **M0-04** (S) `assets/CREDITS.md` template + first asset import: 2 KayKit character packs + Kenney prototype kit ⛓ M0-01
- [ ] **M0-05** (S) Issue/PR templates referencing this plan's task IDs

### M1 — Networking core (the risk milestone — do first, keep small)
- [ ] **M1-01** (L) ENet server/client bootstrap: headless entrypoint, connect/disconnect, peer registry, `--server` flag ⛓ M0-01
- [ ] **M1-02** (M) Room manager: create/join by 6-char code, host role, room lifecycle + 5-min expiry ⛓ M1-01
- [ ] **M1-03** (L) Replication spike: pick MultiplayerSynchronizer vs custom snapshots with 6 moving players; document decision in `docs/adr/001-replication.md` ⛓ M1-01
- [ ] **M1-04** (M) Session tokens + rejoin flow (rejoin restores slot/score, sits out current round) ⛓ M1-02
- [ ] **M1-05** (M) Fake-lag/loss test harness + 6-client headless soak script ⛓ M1-03

### M2 — Lobby & app shell
- [ ] **M2-01** (M) Client app shell: main menu (Host / Join code / Settings), scene router, connection status UI ⛓ M1-02
- [ ] **M2-02** (M) Lobby scene: player list, ready-up, round-count setting (8/12/15), start gating ⛓ M2-01
- [ ] **M2-03** (M) Character select: 8-character roster resources, color assignment, duplicate handling ⛓ M2-01, M0-04
- [ ] **M2-04** (M) Character rendering kit: orthographic camera rig, outline/nameplate-through-walls shader, shared animation proxy ⛓ M0-04
- [ ] **M2-05** (S) Settings screen: audio, window mode, server address override

### M3 — Match framework (unblocks all minigames)
- [ ] **M3-01** (L) Match state machine + server-side minigame selector (variety + player-count rules) ⛓ M1-03
- [ ] **M3-02** (M) Minigame Contract: `MinigameMeta`, `MinigameBase`, `MinigameResults`, arena helpers, template minigame folder ⛓ M3-01
- [ ] **M3-03** (M) Economy: placement tables, team awards, pickup caps, tie handling — pure logic + GUT tests (SPEC §5) ⛓ M3-01
- [ ] **M3-04** (M) Round chrome: intro card (rules/controls/skip), countdown, results screen, running-total HUD ⛓ M3-02
- [ ] **M3-05** (S) Leaderboard interstitial every 5 rounds + podium/match-summary scene ⛓ M3-04
- [ ] **M3-06** (M) **Reference minigame: Coin Scramble (#1)** — proves the whole contract end-to-end; template for all M4 work ⛓ M3-02, M3-03, M3-04
- [ ] **M3-07** (S) Quick-emote wheel (6 emotes, replicated) ⛓ M3-02

### M4 — Minigame production (all parallel after M3-06; each task: scene, server logic, 2/4/6-player balance pass, SFX hooks)
FFA — [ ] **M4-01** King of the Hill (M) · [ ] **M4-02** Hot Potato (M) · [ ] **M4-03** Thin Ice (M) · [ ] **M4-04** Sumo Smash (M)
Skill — [ ] **M4-05** Simon Stomp (M) · [ ] **M4-06** Quick Draw (S) · [ ] **M4-07** Hurdle Dash (L) · [ ] **M4-08** Target Range (M, mouse+stick aim) · [ ] **M4-09** Beat Bounce (M)
Team — [ ] **M4-10** Tug of War (S) · [ ] **M4-11** Relay Sprint (M) · [ ] **M4-12** Cart Push (L) · [ ] **M4-13** Color Clash (M)
Sabotage — [ ] **M4-14** Poison Feast (M) · [ ] **M4-15** Trap Corridor (L) · [ ] **M4-16** Heist Night (M)

### M5 — Finale
- [ ] **M5-01** (M) Buy-in shop: 30 s timer, four purchasables, coin math + GUT tests (SPEC §6) ⛓ M3-03
- [ ] **M5-02** (L) The Gauntlet arena: shrinking platform, escalating hazards, lives/respawns, sabotage-token + grudge-vote hooks ⛓ M3-02
- [ ] **M5-03** (S) Final ranking: elimination order → placement, coin tiebreaks; feeds podium ⛓ M5-02, M3-05

### M6 — Polish & feel
- [ ] **M6-01** (M) Audio pass: music loops (menu/round/finale), SFX for all shared chrome + per-minigame hooks
- [ ] **M6-02** (M) Juice pass: coin fly-to-HUD, screen shake, KO ragdolls, victory dances
- [ ] **M6-03** (S) Reconnect overlay + graceful error toasts (room full, bad code, version mismatch)
- [ ] **M6-04** (M) UI theme unification + intro-card control diagrams for all 17 games

### M7 — Deployment & release
- [ ] **M7-01** (M) Dockerfile + compose for the dedicated server; VPS deploy doc; version handshake (client/server protocol version) ⛓ M1-01
- [ ] **M7-02** (M) Release pipeline: tagged builds → GitHub Releases artifacts for Win/Linux/macOS ⛓ M0-03
- [ ] **M7-03** (M) Playtest checklist automation: 6 headless bot clients complete a full 12-round match nightly in CI ⛓ M1-05, M3-01
- [ ] **M7-04** (S) In-game credits screen generated from `assets/CREDITS.md`

## 6. Suggested build order / critical path

```
M0 → M1 (risk first: networking) → M3-01..06 (framework + reference minigame)
                     ↘ M2 (lobby, parallel with M3)
M3-06 done → fan out M4 minigames (parallel) + M5 finale
→ M6 polish → M7 release
```

The critical path is **M0 → M1 → M3 → M4**. M2 and M5 can proceed in parallel once their dependencies land. Get one full playable loop (menu → lobby → 3 rounds of Coin Scramble → podium) working end-to-end before mass-producing minigames — this is the **vertical slice** gate.

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
