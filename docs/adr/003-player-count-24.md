# ADR 003: Raise supported player count to 24 (scale the games that make sense)

**Status:** Accepted (owner directive, JakePre) — supersedes the locked "2–6 players" decision (SPEC §2, PHASE2 P2-4, and the PHASE2 §2 non-goal "lobbies above 6 players")
**Date:** 2026-07-04

## Context

The game was designed and built for **2–6 players**. That cap is baked in at three
levels:

- **Room/network:** `NetConfig.MAX_PLAYERS_PER_ROOM = 6` is the hard ceiling.
- **Identity:** `PlayerPalette` has exactly **6 colors** and wraps with `posmod`, so a
  7th player reuses P1's color. SPEC §8 makes color the *primary* identity channel — it
  stops working past 6.
- **Scoring:** `Economy.PLACEMENT_AWARDS = [30, 20, 15, 10, 5, 3]` covers 6 places and
  clamps every rank past 6th to a flat 3 coins — it "runs" at any N but stops being a
  fair graduated curve.

Per game, `MinigameMeta.max_players` (default 6) gates catalog eligibility
(`MinigameCatalog.build_playlist` skips games whose `max_players < player_count`).

The owner has decided to support **matches of up to 24 players**. The explicit guidance:
*not every game needs to scale* — "it doesn't make sense for 24 people to play smash bros
or mario kart" — but *enough games should scale that a 24-person party is genuinely
playable*, and every game should support "as many people as makes logical sense."

Each of the 31 minigames was analysed against its own code (spawn geometry, arena size,
resource economy, scoring, and what physically happens between players) to set an honest
per-game cap.

## Decision

**Raise the supported player count to 24.** Classify every minigame by what its mechanics
can actually sustain:

- **Physical-contact games** (shove/melee/tag/cart-brawl/tight-ring/musical-chairs dash)
  and **fixed-topology games** (single narrow corridor, 3 fixed lanes, serial one-turn-per-
  player loops) **stay small (6–8).** A crowd makes these unfair or unreadable — this is
  the smash/kart class the owner named. They are capped *by design*, not by omission.
- **Parallel, no-contact games** (reaction, rhythm, aiming galleries, memory/dodge
  survival, territory paint, independent-lane races, alternating-mash tug) **scale to 24.**
  Players act independently against a shared cue or their own lane; adding players never
  changes anyone's fairness. Only presentation (rig layout, colors, scoring curve) needs
  work.
- **Shared-resource FFA** (collect-a-thons, zone control, snake trails) sit in the
  **middle at 12** — fair and readable with a dozen, but a fixed arena and fixed resource
  supply turn a full crowd into a luck-driven scramble.

### Per-game player-cap matrix

Reconciled from a per-game code analysis of all 31 minigames. "New cap" is the target
`max_players`.

#### Crowd scale — 24 players (12 games)
| Game | Cat | New cap | Why it scales |
|---|---|---|---|
| Beat Bounce | SKILL | 24 | Rhythm/memory on shared pads; every player reproduces the sequence independently, no contact. |
| Bullseye Bowl | SKILL | 24 | Each player rolls at a private lane and phased target; zero interaction — pure layout/camera work. |
| Color Clash | TEAM | 24 | Territory paint with no collision; scale via team mode + a larger grid so tile counts stay meaningful. |
| Count Quick | SKILL | 24 | Perception/reaction to a shared swarm; accumulation scoring is tie-safe, pads don't multiply with players. |
| Hurdle Dash | SKILL | 24 | Fully independent lanes, identical hurdles, zero interaction — the archetypal parallel racer. |
| Memory Match | SKILL | 24 | Memorise-and-stand survival with no player physics; players share tiles freely. |
| Quick Draw | SKILL | 24 | Reaction to one shared DRAW! cue; hinges on a universal signal, not tracking 24 actors. |
| Simon Stomp | SKILL | 24 | Simon-says on 4 shared pads via each player's own inputs; targets are shared, input independent. |
| Tug of War | TEAM | 24 | Alternating-mash tug; pull is already normalised by team size, one shared HUD bar reads at any count. |
| Bullet Waltz | SKILL | 24† | Parallel bullet-dodge; storm is player-count-independent. †24 needs the arena-scale helper (F4); 16 without it. |
| Laser Limbo | SKILL | 24† | Parallel wall-dodge; only limiter is arena density + one gap. †24 needs F4 (arena/gap scaling); 16 without. |
| Target Range | SKILL | 24† | Aim gallery, target count already scales with players. †24 needs the target-band/firing-line widen (F4/F7); 16 without. |

#### Mid scale — 12 players (9 games)
| Game | Cat | New cap | Why it caps here |
|---|---|---|---|
| Coin Scramble | FFA | 12 | Bump-to-scatter contention on a fixed arena + fixed coin supply; a full crowd starves and moshes. |
| King of the Hill | FFA | 12 | One shrinking zone; past a dozen it's a body-blocking scrum, not skill. |
| Meteor Shower | FFA | 12 | Parallel dodge, but the shrinking endgame zone crushes a crowd into coin-flips. |
| Musical Platforms | FFA | 12 | Musical-chairs dash; N−1 well-spaced pads can't fit the ring past ~12. |
| Poison Feast | SABOTAGE | 12 | Push-your-luck foraging; fixed dish supply + single global pot get swingy past a dozen. |
| Relay Sprint | TEAM | 12 | Independent team lanes (6 teams of 2); limited by stacked-lane readability. |
| Snake Chain | TEAM | 12 | Shared-arena trails tangle; 10 pellets starve and 24 snakes make an impassable lattice. |
| Thin Ice | FFA | 12 | Shared vanishing floor; a crowd strips the ice near-instantly into spawn-luck. |
| Treasure Divers | FFA | 12 | Air-management collect-a-thon; single shared coin pool starves a big crowd. |

#### Small / by-design — 6–8 players (10 games) — the smash/kart class
| Game | Cat | New cap | Why it stays small |
|---|---|---|---|
| Sumo Smash | FFA | 8 | Shove-brawler on one tiny disc; a crowd is a random ring-out pinball. |
| Rumble Ring | FFA | 8 | Melee shove-brawler in a fixed ring; KOs respawn dead-center into a spawn-camp pile. |
| Shock Tag | FFA | 8 | Physical chase, one zap, chaser barely faster; a crowd leaves 20 players idle. |
| Hot Potato | FFA | 8 | One bomb, one carrier, 3 blasts total; most of a crowd is idle bystanders. |
| Cart Push | TEAM | 8 | Tug-brawl on one rail with a hard 3-pushers-per-side cap; extra players are irrelevant. |
| Wall Builders | TEAM | 8 | Carry-brawl funnelled to two narrow zones; a fixed 6-block supply starves a crowd. |
| Bomb Courier | SABOTAGE | 8 | 4-package pile + single depot/defuse chokepoint + PvP dash-swap; starves and jams past ~8. |
| Heist Night | SABOTAGE | 8 | Physical steal-by-standing + single coin pool; vault ring overlaps into unreadable mush. |
| Trap Corridor | SABOTAGE | 8 | Serial one-trapper-per-player rounds (match length grows with N) in a 5-lane corridor. |
| Fish Frenzy | SKILL | 8 | Looks parallel but each beat spawns one fish in one of 3 lanes, first-in-lane wins — a crowd starves. |

#### Finale
| The Gauntlet | — | 24 | Last-player-standing survival; already spawns players on a circle (`TAU·i/n`), so it scales geometrically. Needs only the framework work (F1–F3). |

**Result:** a 24-player lobby has **12 eligible minigames** (plus the finale); a 12-player
lobby has 21; an 8-player lobby has all 31. Small lobbies (2–6) are unchanged.

### Framework changes required (gate the per-game caps)

Nothing above works until these land. They are the M15 milestone.

- **F1 — Room/network cap.** `NetConfig.MAX_PLAYERS_PER_ROOM` 6 → 24. Verify the 30 Hz
  authoritative snapshot (`MatchController.get_snapshot`, `NetManager`) stays within
  bandwidth/CPU at 24 players; add area-of-interest culling only if measurement demands it.
- **F2 — Identity beyond 6 colors.** `PlayerPalette` (6 colors, `posmod` wrap) must
  distinguish up to 24 players: expand the palette *and* add an always-on secondary channel
  (numbered nameplates and/or patterns). This is the widest-reaching change — it touches
  every view's rig/nameplate rendering. SPEC §8's "color is the primary identity channel"
  is amended: color + number.
- **F3 — Placement-scoring formula.** Replace the fixed `Economy.PLACEMENT_AWARDS`
  6-entry table with a graduated formula for N up to 24, and generalise the 2/3-team award
  tables to N teams (needed by Color Clash at scale).
- **F4 — Arena + economy scale-with-count helper.** A shared convention to scale
  `ARENA_HALF`, spawn-ring radius, and resource supply (coins/dishes/pellets/targets/blocks)
  with `slots.size()`. Unlocks the mid-tier games and the three †contingent 24-games.
- **F5 — Spawn-layout helper.** Multi-ring/grid distribution so dense counts don't overlap
  (most games already use a size-agnostic ring; it just gets tight past ~12).
- **F6 — Large-room UI.** Lobby member list, results/placement list, and coin-fly must
  handle up to 24 rows (grid/paginate).
- **F7 — Many-player view layouts.** Fit-to-viewport / multi-column / arc layouts for the
  games that line players up in rows or stacked lanes (Hurdle Dash, Relay Sprint, Bullseye
  Bowl, Quick Draw, Tug of War, Target Range).

### Non-goals (unchanged)

- **Not every game scales.** The 6–8 caps above are deliberate — forcing brawlers and
  racers to a crowd is exactly the unfairness the owner ruled out.
- **No matchmaking / public lobbies.** Still private-room-by-code only.
- **The 2–6 experience is untouched.** Small lobbies play identically; this is additive.

## Consequences

- SPEC §2 "Player count: Flexible 2–6" and PHASE2 P2-4 / the §2 "lobbies above 6 players"
  non-goal are superseded by this ADR. Amendment pointers are added there; this ADR is the
  source of truth for the cap.
- A full 24-player match draws from 12 games + the finale. Until more mid-tier games are
  promoted (F4), a 24-player match runs fewer distinct rounds or permits late repeats; the
  match-length target flexes accordingly.
- The per-game `max_players` bumps must not land before F1–F3, or the catalog will draft a
  game for a crowd it can't render/score. M15 sequences framework-first, then per-game.
- Testing matrix grows: the per-minigame manual matrix (currently 2/4/6) gains a
  large-count pass (e.g. 12 and 24) for games that scale.
