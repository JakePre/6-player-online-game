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
| **M12-01** balance pass, all 35 games at 2/4/6 | The riskiest remaining task — and **the only open task in the plan**. ⛔ Blocked on data: the pre-#560 telemetry was tie-noise (idle bots, 0.4 s rounds); the fixed `balance-telemetry-{2,4,6}` artifacts (#560, nightly `balance` job) need a few nights to accumulate first. Then: interpret the data, make fairness judgments per game, and know which designs are intentional (§7 tiers, #174/#175). A wrong "fix" here has been reverted before. |
| ~~**M14-00** side-view platformer framework (L)~~ | ✅ done — `SideScrollSim`/`SideScrollView` landed; M14-01/-03/-09 built on it. |
| ~~**M14-02** Turbo Lap (L)~~ | ✅ done |
| ~~**M14-09** Tumble Run (L)~~ | ✅ done |
| ~~**M16-01** design system 2.0 (L)~~ | ✅ done (#506) — `PartyTheme` rebuilt, `docs/STYLE_GUIDE.md` written. Gates the rest of M16. |
| ~~**M16-13** consistency audit (S)~~ | ✅ done (#553/PR #556). Its biggest find was out-of-scope: the finale was unreachable (#554). |
| ~~**#554** wire The Gauntlet finale into the match flow~~ | ✅ done (PR #558) — FINALE_SHOP/FINALE_PLAY states, shop UI, PROTOCOL_VERSION 8, playtest bots assert the finale runs. |

## Opus 4.8 — real engineering, clear precedent

Everything in this tier is **done** — kept as a record, not a work queue.
The M10/M14 roster, M12 feel-and-fairness pieces (except the data-blocked
M12-01 above), every M15 cap, and all M16 surfaces (M16-02/03/07/08/09/11)
shipped; the finale wiring follow-ups (#554/#560) closed the last gaps.

## Sonnet 5 — mechanical, pattern-following

Everything below is **done** — kept as a record, not a work queue. Live
availability as of 2026-07-05 (evening): **none at any tier** except the
data-gated M12-01 (see Structural notes). Next agent: check here before
re-deriving this from scratch.

| Task | Status |
|---|---|
| ~~M15 8-caps~~ (10): Sumo Smash, Rumble Ring, Shock Tag, Hot Potato, Cart Push, Wall Builders, Bomb Courier, Heist Night, Trap Corridor, Fish Frenzy | ✅ done — all at `max_players: 8` |
| ~~M15 simple 24-caps~~ (8): Beat Bounce, Bullseye Bowl, Count Quick, Hurdle Dash, Memory Match, Quick Draw, Simon Stomp, Tug of War | ✅ done — all at `max_players: 24` |
| ~~M15 remaining 12-caps~~ (8): King of the Hill, Meteor Shower, Musical Platforms, Poison Feast, Relay Sprint, Snake Chain, Thin Ice, Treasure Divers | ✅ done — all at `max_players: 12` |
| ~~M12-02~~ `play_sfx` adoption sweep | ✅ done (#482) |
| ~~M14-05~~ Ro-Sham-Bo Royale (S) | ✅ done (#507) |
| ~~M16-10~~ error/edge chrome (S) | ✅ done (#534) |
| ~~M16-04 + M16-05~~ lobby + character select (M) | ✅ done together (#529) — the roster carousel lives inside lobby.tscn, not a separate screen |
| ~~M16-06~~ settings+credits (S) | ✅ done (#524) |
| ~~M16-12~~ per-minigame key art (M) | ✅ done (#533) — 39 intro-card key-art requests filed in IMAGE_REQUESTS.md; loader shipped in M16-07 |
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

- **The plan board is complete except M12-01** (as of 2026-07-05 evening):
  M14 Genre Hop, M15 caps, and all of M16 shipped; the M16-13 closing audit
  merged as PR #556. The finale — built across M5/M8/M13/M16 but never
  reachable — was wired into the live match flow by #554 (PR #558,
  PROTOCOL_VERSION 8).
- **M12-01 is the only open task and it is data-gated, not claim-gated.**
  #560 (PR #561) fixed why: the old playtest telemetry was idle-bot tie-noise.
  The nightly now runs a `balance` job (2/4/6 players, real durations, bots
  sending random inputs) uploading `balance-telemetry-<n>.json`. Claim M12-01
  once several nights of those artifacts exist; `workflow_dispatch` the
  Nightly playtest to accumulate faster. Tuning-only PRs; respect the
  PHASE2.md §7 intentional-design tiers (#174/#175 precedent).
- Housekeeping: #557 removed 153 accidentally-committed `*.TMP` files and
  gitignored the pattern (PR #559).
