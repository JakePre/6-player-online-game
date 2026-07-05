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
| **M16-01** design system 2.0 (L) | Pure taste + system thinking: typography, palette, motion standards. Every other M16 task inherits its choices — a weak foundation costs all 12 downstream surfaces. Writes STYLE_GUIDE.md. |
| **M16-13** consistency audit (S) | Small but judgment-dense: spotting "this reads wrong" across every surface with no checklist to follow is exactly what the tier is for. |

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
| **M16-02** screen-transition framework (M) | One shared mechanism wired through every app-shell screen change; interacts with reduced-motion. Build once, carefully. |
| **M16-03** title screen & main menu (M) | The flagship surface — this PR *is* the visual bar the other surfaces copy. Do it right after M16-01, before the Sonnet fan-out. |
| **M16-08** in-match HUD (M) | Legibility judgment under 24-player chaos, not just styling; every game's readability rides on it. |
| **M16-07** match chrome · **M16-09** results & celebration · **M16-11** finale chrome (M) | Multi-state presentation flows (intro→countdown→play→results) with motion; real assembly against the M16-01/03 bar. |

## Sonnet 5 — mechanical, pattern-following

Everything below the M15/M12-02 rows is **done** — kept as a record, not a
work queue. Live availability as of 2026-07-05: **none**. M14-05 (the one
open Sonnet-tier new game) is claimed; the M16 Sonnet surfaces are blocked on
M16-01/03/07 landing first (see Structural notes). Next agent: check here
before re-deriving this from scratch.

| Task | Status |
|---|---|
| ~~M15 8-caps~~ (10): Sumo Smash, Rumble Ring, Shock Tag, Hot Potato, Cart Push, Wall Builders, Bomb Courier, Heist Night, Trap Corridor, Fish Frenzy | ✅ done — all at `max_players: 8` |
| ~~M15 simple 24-caps~~ (8): Beat Bounce, Bullseye Bowl, Count Quick, Hurdle Dash, Memory Match, Quick Draw, Simon Stomp, Tug of War | ✅ done — all at `max_players: 24` |
| ~~M15 remaining 12-caps~~ (8): King of the Hill, Meteor Shower, Musical Platforms, Poison Feast, Relay Sprint, Snake Chain, Thin Ice, Treasure Divers | ✅ done — all at `max_players: 12` |
| ~~M12-02~~ `play_sfx` adoption sweep | ✅ done (#482) |
| **M14-05** Ro-Sham-Bo Royale (S) | ◐ **claimed** (#507) — do not duplicate |
| **M16-04** lobby · **M16-05** character select · **M16-06** settings+credits · **M16-10** error/edge chrome (S/M) | ⛔ blocked — needs M16-01 (design system); M16-04/05/06/10 also want the M16-03 exemplar first |
| **M16-12** per-minigame key art (M) | ⛔ blocked — needs M16-07's card slot |
| ~~Epic #256~~ (M13 tracking issue) | ✅ closed |
| ~~#467~~ cache per-tick alive set | ✅ closed |

## Project review findings (2026-07-05)

From the full audit in [PROJECT_REVIEW.md](PROJECT_REVIEW.md). These are the
concrete follow-ups the review surfaced; classified here like any other task.

All seven review findings are closed — the full audit's follow-ups are done.

| Task | Issue | Model | Status |
|---|---|---|---|
| ~~Finale: wire grudge + real sabotage targeting~~ | #462 | Opus 4.8 | ✅ done (PR #476) |
| ~~Measure content-heavy match snapshots at 24~~ | #463 | Opus 4.8 | ✅ done |
| ~~Color Clash grid delta (keyframe + changed-tiles)~~ | #479 | Opus 4.8 | ✅ done |
| ~~Decide + document caps for the 4 post-ADR games~~ | #464 | Owner → Sonnet/Opus | ✅ done |
| ~~Add `--check-only` to the local dev gate~~ | #465 | Sonnet 5 | ✅ done |
| ~~Nightly 12/24-player playtest variant~~ | #466 | Opus 4.8 | ✅ done |
| ~~Cache per-tick alive set~~ | #467 | Sonnet 5 | ✅ done |

## Structural notes

- **M14 is open** (v0.6.0 shipped at the boundary 2026-07-05; the release hold
  is lifted) — Genre Hop games are claimable under normal rules. As of
  2026-07-05: M14-05 (#507) and M14-06 (#505) are claimed; M14-01/02/03/04/
  08/09/10 are unclaimed.
- **M16 sequencing**: M16-01 (Fable) gates everything; M16-03 (Opus) is the
  exemplar surface to do second; then the Sonnet surfaces fan out in parallel.
  M16-13 audits last. Image needs go through IMAGE_REQUESTS.md — never block
  on art. As of 2026-07-05, M16-01 is filed (#503) but not yet claimed —
  nothing else in M16 can start until it lands.
- **M15 is fully done** — every per-game cap task landed; the section above is
  historical. The live remaining pool is M14 (Genre Hop) + M16 (Beautiful
  UI/UX), both gated at the top (M14-01..10 mostly Fable/Opus; M16 gated on
  M16-01).
