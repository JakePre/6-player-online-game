# Project Review — 2026-07-05

A high-level audit of the whole project (architecture, correctness, scaling, QA,
process), performed while the build fleet was idle. Read the core layers (net,
match controller, economy, room, minigame contract), sampled sims/views across
the 35 minigames, measured real behavior at 24 players, and traced the finale
end to end.

Each actionable finding has a tracking issue and a recommended model tier
(complexity signal, per [MODEL_ROUTING.md](MODEL_ROUTING.md) — not an
assignment).

## Overall health: strong

~20.6K LOC source / ~13.4K LOC tests (a ~0.65 test ratio that is real —
behavioral, edge-triggered tests, not coverage theater). Clean
server-authoritative architecture; a well-designed Minigame Contract that let 35
games and a full 24-player scaling pass land without structural strain; almost
no `TODO/FIXME/HACK` debt; a coordination protocol that demonstrably kept a
parallel agent fleet conflict-free. The items below are what to fix, not signs
of trouble.

## Findings

| # | Severity | Finding | Issue | Model | Status |
|---|---|---|---|---|---|
| 1 | 🔴 High | Finale grudge mechanic unreachable; sabotage tokens center-only | [#462](https://github.com/JakePre/6-player-online-game/issues/462) | Opus 4.8 | ✅ **fixed** (PR #476) |
| 2 | 🟠 Med-High | Match snapshots at 24 unmeasured; no delta/AOI compression | [#463](https://github.com/JakePre/6-player-online-game/issues/463) | Opus 4.8 | ✅ **measured** → follow-up [#479](https://github.com/JakePre/6-player-online-game/issues/479) |
| 3 | 🟡 Med | 4 post-ADR games have no documented cap decision | [#464](https://github.com/JakePre/6-player-online-game/issues/464) | Owner decision → Sonnet/Opus | ✅ **fixed** (Basket Brawl→8 PR #460, Fort Siege→12 PR #478, The Mole→8 PR #485, Faulty Wiring→12 PR #475) |
| 4 | 🟢 Low | `--check-only` missing from the local gate → recurring CI-only parse failures | [#465](https://github.com/JakePre/6-player-online-game/issues/465) | Sonnet 5 | ✅ **fixed** (PR #472) |
| 5 | 🟡 Med | No nightly 12/24-player full-match verification | [#466](https://github.com/JakePre/6-player-online-game/issues/466) | Opus 4.8 | ☐ open |
| 6 | 🟢 Low | Repeated per-tick `slots.filter(_is_in)` allocations | [#467](https://github.com/JakePre/6-player-online-game/issues/467) | Sonnet 5 | ✅ **fixed** (PR #477) |

*(Status column updated 2026-07-05 as findings are worked. The measurement in
#463 quantified the one real bandwidth outlier — **Color Clash @24 ≈ 4.4 MB/s/room**
from full-grid replication — and concluded a general net-layer delta protocol is
**not** warranted; a targeted, self-contained Color Clash grid-delta ([#479](https://github.com/JakePre/6-player-online-game/issues/479),
Opus) is the proportionate fix. Everything else measured ≤ ~1 MB/s.)*

## Detail

### 1. 🔴 Finale grudge + sabotage are non-functional ([#462](https://github.com/JakePre/6-player-online-game/issues/462))

The standout. The Gauntlet sim ([gauntlet.gd](../src/finale/gauntlet.gd)) fully
implements and unit-tests two SPEC §6 pillars that don't work in the client:

- **Grudge** (eliminated player's one revenge hazard): `"grudge"` appears *only*
  in the sim's handler — a grep of all of `src/` finds **no client that sends
  it**. Unreachable in real play.
- **Sabotage tokens** (a coin-purchased shop item): the only client wiring
  hardcodes the target to center — [gauntlet_view.gd:42](../src/finale/gauntlet_view.gd)
  sends `{"sabotage": [0.0, 0.0]}`. Players buy a token they can't aim.

Flagged in-code as a deferred "finale HUD targeting pass" that never landed.
Dangerous because it is **invisible to CI** — all tests pass, yet a shop
purchase and a headline mechanic don't function.

### 2. 🟠 Replication cost at 24 is unmeasured ([#463](https://github.com/JakePre/6-player-online-game/issues/463))

`NetManager._broadcast_snapshots` sends the full match snapshot to each of up to
24 players at 30 Hz — no delta compression, no area-of-interest culling.
Content-heavy games send whole state uncompressed: **Color Clash** replicates a
576-int grid (`grid.duplicate()`, [color_clash.gd:135](../src/minigames/color_clash/color_clash.gd))
to all 24 recipients every tick (~2 MB/s per room for one game); Snake Chain and
The Mole grow the same way. The M15-01 decision deferred AOI "until measurement
demands it," but that measurement was never done — the debug telemetry only
sampled a 184-byte *between-rounds* frame. **No content-heavy PLAY snapshot at 24
has been measured.** Measure first; a delta protocol (Fable-tier, net-layer,
`PROTOCOL_VERSION` bump) only if warranted.

### 3. 🟡 Undocumented caps for the newest games ([#464](https://github.com/JakePre/6-player-online-game/issues/464))

Basket Brawl, Fort Siege, The Mole, Faulty Wiring postdate ADR 003, are absent
from its matrix, and sit at `max_players: 6` — the only games silently excluded
from large lobbies with no rationale. Several *should* stay small (hidden-role /
contact games), but that's a design call to document, not omit. Owner decision,
then per-game impl.

### 4. 🟢 CI-only parse failures ([#465](https://github.com/JakePre/6-player-online-game/issues/465))

CI's Godot rejects `var x := dict.member` (Variant inference) as a parse error;
local `--import`/GUT tolerate it, so scripts pass locally and fail CI. Cost
multiple agents a rebase cycle each. `godot --check-only --script <file>`
reproduces the class locally — document it in the AGENT_COORDINATION §5 gate.

### 5. 🟡 No large-lobby full-match coverage ([#466](https://github.com/JakePre/6-player-online-game/issues/466))

The whole cap milestone was unit-tested at 2-4 players; nothing verified a 12/24
match *composes* until `run_playtest.py --players` landed (#454). Wire a nightly
12/24 variant (modeled on the M9-06 mutator soak) into CI.

### 6. 🟢 Per-tick alive-set churn ([#467](https://github.com/JakePre/6-player-online-game/issues/467))

~8 last-standing games recompute `slots.filter(_is_in)` several times per tick.
Negligible at 24, but worth caching once per tick. Low-priority batch cleanup.

## Strengths worth preserving

- **Test discipline** — behavioral, edge-triggered, ~0.65 test ratio.
- **Scaling consistency** — 32 files route through the shared `MinigameScaling` /
  `LaneLayout` / `SpawnLayout` helpers; the parallel fleet did *not* fragment the
  approach.
- **Server authority is clean** — clients send intent keyed to their own
  peer→slot; no slot spoofing, positions computed and clamped server-side.
- **The coordination protocol works** — [AGENT_COORDINATION.md](AGENT_COORDINATION.md)
  encodes real incidents as checked steps and kept a fast fleet conflict-free.

## Process observations (not filed as tasks)

- **Claim-vs-build race window.** Tasks were built then found claimed ~20 s
  earlier (Color Clash #394/#395). The protocol resolves it correctly
  (earliest-wins) but wastes work. A lighter "intent to claim" faster than
  opening an issue would shrink the window — a coordination-protocol change for
  the owner to weigh.
- **24-player support is "green in CI" but not "load-verified."** ~15 cap PRs
  merged in ~2 hours; the structure is sound and unit-tested, but integration at
  scale (bandwidth, tick budget, fairness) is only now getting coverage (#463,
  #466). Honest headline: structurally done, not yet proven under load.
