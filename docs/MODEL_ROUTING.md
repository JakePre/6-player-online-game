# Model routing — recommended model tier per remaining task

Owner-requested (2026-07-04): every remaining task carries a recommended model
tier as a **complexity signal** for whichever agent picks it up. There is no
guarantee the recommended model handles the task — treat the tier as "how much
design judgment and technical novelty does this need", not an assignment.

Rubric:

- **Fable 5** — design-judgment-heavy, cross-cutting, or technically novel;
  ambiguity that a wrong guess makes expensive (precedent: reverted "fixes" of
  intentional designs, PHASE2.md §7 / issue #174/#175).
- **Opus 4.8** — real engineering with an established pattern in the repo to
  follow; self-contained builds.
- **Sonnet 5** — mechanical, template-following changes with the hard
  decisions already made upstream.

Keep this file current: when you claim a task, its row here is informational;
when tasks are added (new milestones, playtest waves), classify them in the
same PR that adds them, or a follow-up `[DOCS]` PR.

## Fable 5 — judgment-heavy, cross-cutting, or technically novel

| Task | Why |
|---|---|
| **M12-01** balance pass, all 33 games at 2/4/6 | The riskiest remaining task: interpret nightly-run data, make fairness judgments per game, and know which designs are intentional (§7 tiers, #174/#175). A wrong "fix" here has been reverted before. |
| **M14-01** Loadout Duel (L) | Owner-requested, genre-new loadout/weapon design from a one-line spec; needs the §10 proposal-comment flow before code. |
| **M14-02** Turbo Lap (L) | Racing handling under 30 Hz server-authoritative snapshots — latency feel, drift, track replication have no precedent in this codebase. |
| **M14-09** Tumble Run (L) | Physics-platformer obstacle gauntlet; server-side physics + tumble feel is new territory and judgment-heavy. |

## Opus 4.8 — real engineering, clear precedent

| Task | Why |
|---|---|
| **M10-16** Faulty Wiring (M) | Full minigame (sim + view + tests) against a 30-game template; sabotage role can lean on the private-snapshot hook (#254). |
| **M10-13** The Mole · **M10-14** Pickpocket Plaza | Claimed/in-flight — listed for §9 rescue purposes. Same profile as M10-16 (hidden-role mechanics, moderate). |
| **M14-03** Knock-Off (L) | Smash-like brawler, but Sumo Smash + Rumble Ring already prove the shove/KO mechanics — assembly more than invention. |
| **M14-04** Shred Session · **M14-06** Blast Grid · **M14-08** Putt Panic · **M14-10** Nom Arena (M) | Genre-hop games on the mature minigame contract. Nom Arena has a hard owner constraint: 60 s cap, keep it QUICK. |
| **M12-03** accessibility (M) | Wide-reaching (reduced-motion touches every FX site; colorblind palette touches identity; remapping needs new settings UI) but each piece is well-specified. |
| **M12-05** input parity audit (S) | Small, but the audit half means actually judging playability per game; the Trap Corridor stick-cursor is a real little feature. |
| **M15 †-caps**: Bullet Waltz, Laser Limbo, Target Range → 24 | Need `MinigameScaling` (F4) wired *into the sims* (arena density, gap scaling, target-band widen) + fairness verification — not just a number bump. |
| **M15**: Color Clash → 24 | The one cap task with a gameplay change: N-team mode + larger grid so tile counts stay meaningful. |
| **M15**: Gauntlet finale → 24 | Survival pacing, hazard density, and lives at 24 need verification beyond geometric spawn scaling. |
| **First M15 12-cap** (suggest Coin Scramble) | Sets the pattern for wiring `MinigameScaling`/`SpawnLayout` into a sim; do it once with a stronger model, then the rest is mechanical. |

## Sonnet 5 — mechanical, pattern-following

| Task | Why |
|---|---|
| **M15 8-caps** (10): Sumo Smash, Rumble Ring, Shock Tag, Hot Potato, Cart Push, Wall Builders, Bomb Courier, Heist Night, Trap Corridor, Fish Frenzy | Per ADR 003 these need only M15-01..03 (all landed): raise `max_players` 6→8, verify spawns. |
| **M15 simple 24-caps** (8): Beat Bounce, Bullseye Bowl, Count Quick, Hurdle Dash, Memory Match, Quick Draw, Simon Stomp, Tug of War | M15-07 layouts + M15-02 identity already carry the rendering; bump + 12/24-player test passes. |
| **M15 remaining 12-caps** (8, after the Opus exemplar): King of the Hill, Meteor Shower, Musical Platforms, Poison Feast, Relay Sprint, Snake Chain, Thin Ice, Treasure Divers | Copy the established scaling-wiring pattern per game. |
| **M12-02** `play_sfx` adoption sweep (S) | Mechanical sweep — hook calls at pickups/hits/KOs across views, 30 existing examples to follow. |
| **M14-05** Ro-Sham-Bo Royale (S) | Simplest new game left — round-based rock-paper-scissors on the mature contract. |
| **Epic #256** (M13 tracking issue) | All 31 boxes done — verify and close with a summary comment. |

## Structural notes

- **M14 is still gated**: it needs M10-13/14/16 and the three open M12 boxes
  before any of its nine games are claimable, regardless of model.
- Rough counts: **4 Fable-tier**, **~14 Opus-tier**, **~28 Sonnet-tier**. The
  long tail of M15 cap tasks is deliberately cheap because the framework work
  that made them cheap (M15-01..07) is already merged.
