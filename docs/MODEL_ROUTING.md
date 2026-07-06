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
| **M12-01** balance pass, all 35 games at 2/4/6 | The riskiest remaining task. ⛔ Blocked on data: the pre-#560 telemetry was tie-noise (idle bots, 0.4 s rounds); the fixed `balance-telemetry-{2,4,6}` artifacts (#560, nightly `balance` job) need a few nights to accumulate first. Then: interpret the data, make fairness judgments per game, and know which designs are intentional (§7 tiers, #174/#175). A wrong "fix" here has been reverted before. |
| **M17-06** closing controller verification sweep (M) | Milestone-closing audit with no checklist: gamepad-only end-to-end across every surface and game on multiple pad layouts, judging "does this feel playable," fixing or routing what it finds. Same tier logic as M16-13. ⛓ M17-01..05. |
| ~~**M14-00** side-view platformer framework (L)~~ | ✅ done — `SideScrollSim`/`SideScrollView` landed; M14-01/-03/-09 built on it. |
| ~~**M14-02** Turbo Lap (L)~~ | ✅ done |
| ~~**M14-09** Tumble Run (L)~~ | ✅ done |
| ~~**M16-01** design system 2.0 (L)~~ | ✅ done (#506) — `PartyTheme` rebuilt, `docs/STYLE_GUIDE.md` written. Gates the rest of M16. |
| ~~**M16-13** consistency audit (S)~~ | ✅ done (#553/PR #556). Its biggest find was out-of-scope: the finale was unreachable (#554). |
| ~~**#554** wire The Gauntlet finale into the match flow~~ | ✅ done (PR #558) — FINALE_SHOP/FINALE_PLAY states, shop UI, PROTOCOL_VERSION 8, playtest bots assert the finale runs. |

## Opus 4.8 — real engineering, clear precedent

Live (M17, owner directive 2026-07-05 — full controller support):

| Task | Why |
|---|---|
| **M17-01** controller compatibility layer (M) | Bundle + boot-load the community SDL gamecontrollerdb, hot-plug handling, unknown-GUID logging. Well-trodden Godot pattern (`Input.add_joy_mapping`), real integration work. |
| **M17-02** post-M12-05 gamepad parity audit (M) | Re-run the M12-05 playbook over the 9 M14 games + finale shop/targeting. Clear precedent (#490), per-game judgment. |
| **M17-03** controller rebinding in the remap UI (M) | Extends the M12-03 settings pattern from key capture to pad button/axis capture + persistence. |
| **M17-04** menu/chrome controller navigation (M) | Focus chains + `ui_cancel` back across every screen; mechanical per screen but interaction design at the edges (dropdowns, shop, emote bar). |
| **#565** release self-heal vs branch protection (S) | Pick + implement one of the three listed mechanisms (PR-based sync is the likely winner). |

Everything else in this tier is **done** — the M10/M14 roster, M12
feel-and-fairness pieces (except data-blocked M12-01), every M15 cap, and all
M16 surfaces shipped; the finale wiring follow-ups (#554/#560) closed the
last gaps.

## Sonnet 5 — mechanical, pattern-following

Live: **M17-05** regression guards (S) — GUT tests locking in joypad+keyboard
coverage per action, pad mentions in every game's controls hint, and remap
round-tripping (⛓ M17-03). Plus **#564** landing owner-generated image
batches as they arrive (mechanical: files + CREDITS rows + status flips).

Everything below is **done** — kept as a record, not a work queue. Next
agent: check here before re-deriving this from scratch.

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

## Human playtest wave (2026-07-05 evening, 8-player lobby ×2)

Two human playtests (owner + #570) triaged by Fable into scoped issues.
**Suggested order:** #575 first (three games unplayable, root-caused), then
#577 (unblocks the owner testing everything else), then #576 (systemic
readability, root-caused, cheap). The rest are parallel.

| Issue | Task | Model |
|---|---|---|
| **#575** | [CRITICAL] side-scroll games broken in real matches — SideScrollView setup-before-ready null crash (root cause + fix sketch in the issue; tests were order-blind) | **Opus** |
| **#577** | [HIGH] practice mode — host adds bots in the lobby to test any game solo | **Opus** |
| **#576** | bottom banner text clipped in every game — `make_banner` grow direction (root-caused, two-line fix + sweep) | **Sonnet** |
| #578 | Thin Ice desync (died without ice breaking) | Opus |
| #579 | Target Range mouse aim + firing feedback | Opus |
| #586 | Memory Match objective unclear — classify bug vs UX | Opus |
| #581 | choosable player colors (PlayerPalette override funnel + lobby UI) | Opus |
| #585 | Shred Session device-aware control labels + lane arrows + drum SFX (coordinate with M17) | Opus |
| #584 | Gauntlet weapons-or-better-push | ⛔ owner design call, then Opus |
| #589 | per-game floor variation (shared MultiMesh tint hook, then per-game tints) | Opus → Sonnet |
| #580 | nameplates off by default + settings toggle | Sonnet |
| #582 | Trap Corridor: announce who is setting traps (⛓ #576) | Sonnet |
| #583 | Gauntlet ring-shrink telegraph | Sonnet (Opus if sim must expose timing) |
| #587 | juice batch 1: Coin Scramble bump-burst, KotH shove anim, Sumo dash FX, Rumble Ring SFX | Sonnet |
| #588 | juice batch 2: Simon Stomp start delay/flash, Bullseye Bowl lane colors, Treasure Divers pool dressing | Sonnet |
| #590 | replace remaining grey backgrounds with the animated backdrop | Sonnet |
| #591 | match-start jingle swap | Sonnet |
| #592 | emote rate-limit tuning | Sonnet |

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

- **M17 (full controller support) opened 2026-07-05 (late)** by owner
  directive alongside the v0.6.1 cut: M17-01..04 (Opus) are parallel and
  claimable now; M17-05 (Sonnet) ⛓ M17-03; M17-06 (Fable) closes the
  milestone ⛓ all. See IMPLEMENTATION_PLAN §M17.
- **The plan board is otherwise complete except M12-01** (as of 2026-07-05 evening):
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
