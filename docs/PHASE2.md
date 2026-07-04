# Party Rush — Phase 2: Deeper, Not Wider

**Companion to [SPEC.md](SPEC.md) (v1 design, still the source of truth for everything it covers) and [IMPLEMENTATION_PLAN.md](IMPLEMENTATION_PLAN.md) (the task board — Phase 2 adds milestones M9–M12 there).** Process is unchanged: [AGENT_COORDINATION.md](AGENT_COORDINATION.md) remains binding.

Phase 1 shipped the complete v1 loop: 17 minigames, the coin economy, the Gauntlet finale, the 2.5D iso-arena presentation, audio, deploy, and release pipelines. Phase 2 makes that loop deeper instead of adding new pillars.

---

## 1. Locked decisions (owner, 2026-07-03)

| # | Decision | Choice |
|---|---|---|
| P2-1 | Direction | **Deepen the current loop** — no board mode, no matchmaking, no progression systems |
| P2-2 | Platforms | **Desktop only** (Win/Linux/macOS) — effort goes to quality, not reach |
| P2-3 | Persistence | **Nothing persists** — identity stays name + character per session; no accounts, no server-side stats |
| P2-4 | Session size | **2–6 players**, unchanged |
| P2-5 | Mutators | **Both modes**: the host curates an enabled pool in the lobby; enabled mutators then roll randomly per round |
| P2-6 | Roster growth | **+18 minigames → 35 total** — minigames stay the content engine (amended +2 per owner feedback, 2026-07-03: more action verbs, fewer walk/stand/collect loops) |
| P2-7 | Tournament | **Best-of-N series**: 3 or 5 chained matches with a series scoreboard and a grand champion |
| P2-8 | Bots | **None.** Humans only; the soak bot stays a test tool |

## 2. Non-goals (declined explicitly — do not re-litigate in PRs)

Board/campaign modes · public matchmaking or server browsers · accounts, friends, global leaderboards · web/mobile/Steam ports · lobbies above 6 players · fill-in bot players or practice AI.

## 3. Mutators (M9)

A **mutator** is a round modifier that works on *framework knobs*, never on per-minigame bespoke code — that is what keeps 33 games × 8 mutators from becoming 264 codepaths.

### Rules
1. **Host curates, rounds roll.** The lobby exposes the mutator pool as host-only toggles (replicated like the round-count setting). At each round's selection, the server rolls: ~40% of rounds get one mutator drawn from the enabled pool (never the same one twice in a row); the finale is never mutated.
2. **Announced on the intro card.** The rolled mutator's name and one-liner appear with the minigame rules; no hidden modifiers.
3. **Framework knobs only.** A mutator may set: an **award multiplier** (applied by the economy step), a **duration scale** (applied via the existing `duration_override` path), an **input transform** (applied server-side in the input relay), **view flags** (applied by `MinigameView`/`MinigameView3D`), and a **round-end coin transfer** rule. Anything a mutator needs beyond these knobs is a framework PR first.

### Launch catalog (8)

| Mutator | Knob | Effect |
|---|---|---|
| Double Coins | award ×2 | All placement awards doubled this round |
| Golden Round | pickup cap ×2 | Pickup-coin cap raised 30 → 60 |
| Short Fuse | duration ×0.6 | The round runs at 60% length |
| Overdrive | speed ×1.25 | Server tick delta scaled — everything moves faster |
| Mirror Mode | input mirror | Left is right and right is left (server-side flip, so it is fair and cheat-proof) |
| Blackout | view flag | Periodic lights-out sweeps (reuses the Heist Night dark cadence) |
| Masquerade | view flag | Nameplates hidden — who's who is the puzzle |
| Robin Hood | end transfer | At round end, last place takes 10 coins from first place |

## 4. Roster wave 2 (M10): 17 → 35

Same contract, same bar as Phase 1: server-authoritative sim + `MinigameView3D` view + GUT tests + catalog registration, one game per PR. The scaling rule from SPEC §7 still applies (≥10 eligible games at any player count — wave 2 keeps every category playable at 2–3 where the design allows).

### Chaotic free-for-all
| # | Name | One-liner | Players |
|---|---|---|---|
| 18 | Meteor Shower | Telegraphed meteors rain down on a shrinking safe zone; last one standing | 2–6 |
| 19 | Musical Platforms | When the music stops, claim a platform — there's one fewer than there are players | 3–6 |
| 20 | Shock Tag | One player is electrified and drains coins from whoever they tag; zap passes on touch | 3–6 |
| 21 | Treasure Divers | Dive for sunken coins while your air meter drains; surface to breathe or black out | 2–6 |

### Skill / precision
| # | Name | One-liner | Players |
|---|---|---|---|
| 22 | Memory Match | Tiles flash a pattern, then go dark — step only on the safe ones | 2–6 |
| 23 | Laser Limbo | Duck, dodge and jump timed laser walls sweeping the arena | 2–6 |
| 24 | Bullseye Bowl | Roll your ball down a moving lane at ring targets; best total wins | 2–6 |
| 25 | Count Quick | A swarm of objects flashes on screen — first to lock in the right count | 2–6 |

### Team-based
| # | Name | One-liner | Players |
|---|---|---|---|
| 26 | Basket Brawl | Team ball game: carry, pass, dunk — carriers are slower and shovable | 4–6 |
| 27 | Wall Builders | Build your wall higher than theirs while raiders steal blocks | 4–6 |
| 28 | Snake Chain | Each team is a conga chain collecting pellets; grow long, don't collide | 2–6 |
| 29 | Fort Siege | One team defends the fort, one storms it; swap and compare times | 4–6 |

### Action (new category — owner feedback: games about fighting and dodging, not walking and standing)
| # | Name | One-liner | Players |
|---|---|---|---|
| 34 | Rumble Ring | Arena brawler: swing (quick), charge smash (slow, big knockback), block; KOs score, victims drop coins; respawns keep everyone swinging | 2–6 |
| 35 | Bullet Waltz | Bullet-hell survival: turrets fire seeded spiral/wall/aimed patterns that escalate; last standing wins, near-miss grazing earns pickup coins | 2–6 |

Both are FFA-category in the catalog (the selector has no ACTION category and doesn't need one), must run pad-only and mouse/keyboard-only (see M12-05), and take the standard mutator knobs — Overdrive on Bullet Waltz is the intended nightmare.

### Sabotage / betrayal
| # | Name | One-liner | Players |
|---|---|---|---|
| 30 | The Mole | Co-op objective, but one player is secretly paid to fail it; vote afterward | 4–6 |
| 31 | Pickpocket Plaza | Lift coins from a wandering crowd; one player is the disguised guard | 3–6 |
| 32 | Bomb Courier | Deliver packages across the arena — the saboteur keeps swapping in ticking ones | 3–6 |
| 33 | Faulty Wiring | Repair the circuit together in the dark; someone keeps cutting wires | 4–6 |

## 5. Series mode (M11): a night of Party Rush

- **Best-of-N**: the host picks Single Match (default, unchanged), Best of 3, or Best of 5 in the lobby.
- **Series points**: match placements convert to series points **10 / 7 / 5 / 4 / 3 / 2** (1st → 6th, ties share the higher value, consistent with SPEC §5 tie handling).
- **Between matches**: a series scoreboard interstitial (StandingsPanel reuse) shows running totals, then the room returns to the lobby with picks and settings intact; the next match starts on the usual ready-up.
- **Champion**: after the final match, a champion podium (podium variant) crowns the series winner; series ties break by total match coins earned across the series.
- **Sessions stay ephemeral**: a series lives and dies with the room; disconnect/rejoin keeps series points exactly like match coins (SPEC §9 semantics).

## 6. Feel & fairness pass (M12)

- **Balance**: play data from the M7-03 nightly full-match runs plus targeted 2/4/6 sims for every wave-2 game; tuning-only PRs.
- **Sound adoption**: every minigame wires the M6-01 `play_sfx` hook (pickups, hits, KOs) — the hook shipped, adoption is per-game.
- **Latency feel**: client-side snapshot interpolation in `MinigameView3D` so 30 Hz snapshots read as smooth motion at 60+ fps.
- **Input parity**: every minigame certified playable with a gamepad alone *and* keyboard/mouse alone. Known offender: Trap Corridor's trap placement is mouse-click-only — it gains a stick-driven tile cursor.
- **Accessibility**: colorblind-safe palette variant (player identity must survive deuteranopia), input remapping UI, reduced-motion toggle (disables screen shake from M6-02).

## 7. Presentation tiers: 3D iso is the default, 2D arcade is a choice

Owner direction (2026-07-03): some games are **deliberately 2D** — the flat
arcade look is part of their identity, not a missing migration. Do not
"upgrade" them to `MinigameView3D`; polish them as 2D.

| Intentionally 2D | Why |
|---|---|
| Hurdle Dash | Side-view lane race — Track & Field arcade timing reads best flat |
| Relay Sprint | Parallel lanes + sweeping hazards *are* the visual |
| Heist Night | Top-down blueprint reads like a security feed; the blackout is stronger as a flat map going dark |

Everything about spatial jockeying (Sumo, KotH, Thin Ice, Color Clash,
Rumble Ring, Bullet Waltz, the Gauntlet, ...) stays on the 3D iso tier.
Candidates may move between tiers only with an owner-approved issue.

## 9. Animation & asset pass (M13)

Owner directive (playtest, 2026-07-03, #262): **add animations and assets
everywhere they'd improve the experience — the whole shebang.** Falling
meteors, swimming fish, pickup sparkles, impact bursts. The standing rule
for the whole milestone:

> If an asset or animation would improve the experience, add it.

Rules of engagement:
1. **View-only.** M13 tasks never touch sims, snapshots, or the protocol —
   presentation exclusively. A task that needs sim data the snapshot lacks
   files a framework issue first.
2. **Respect §7 tiers.** The intentionally-2D games (Hurdle Dash, Relay
   Sprint, Heist Night) get 2D-appropriate juice — better linework, flashes,
   screen-space effects — never a 3D "upgrade".
3. **Assets:** CC0/CC-BY only, every import logged in `assets/CREDITS.md`
   (SPEC §10). Prefer the already-imported Kenney kits and KayKit rig
   actions (`hit`, `ko`, `cheer`, `interact`, `pickup`, the jump set) before
   importing anything new.
4. **M13-01 first.** Shared FX helpers (one-shot impact bursts, pickup
   sparkles, splash/dust puffs, self-freeing) land as one small framework PR
   so every per-game task stays a one-file view change. The fan-out is
   parallel after it, same claim rules as M8/M10.

## 8. Sequencing

```
M9 (mutator framework first — wave-2 games ship mutator-clean against it)
   ↘ M10 fan-out (16 games, fully parallel, the Phase 2 workhorse)
M11 series mode (independent of M9/M10 — touches match flow, not minigames)
→ M12 feel & fairness (last: needs the roster complete to balance and wire)
```

Prerequisite stragglers from Phase 1 (M4-05/08/09, M6-04) finish under their existing claims; wave-2 numbering starts at #18 regardless.
