# Release Checklist — the M14 boundary cut

**Owner directive (2026-07-05):** cut a release at the **M14 boundary** — after
the roster + 24-player scaling + series + mutators + animation pass are
complete, and *before* the M14 "Genre Hop" batch of new large games begins.
A **RELEASE HOLD** is in force on M14 (see IMPLEMENTATION_PLAN.md §5 and
AGENT_COORDINATION.md §8): finish the items below, then agents hold — no M14
work until the owner tags the release and lifts the hold.

## What ships at this boundary

The full base game: ~34 minigames + The Gauntlet finale, 2–24 player support,
Single/Bo3/Bo5 series mode, the mutator packs, the 3D iso-arena presentation,
and the full animation/FX pass. A coherent, feature-complete product.

## Blockers — must land before tagging

| Item | Issue/PR | Status | Model |
|---|---|---|---|
| M15: The Mole → 12 (‡ — needs M15-04 economy wiring) | — | ☐ open | Opus |
| M15: Faulty Wiring → 12 (‡ — plain bump) | — | ☐ open | Sonnet |
| M15: Fort Siege → 12 (‡ — plain bump) | #461 | ◐ in-flight | Sonnet |
| M10-14: Pickpocket Plaza (last M10 game) | #359 | ◐ claimed, stalled | Opus |
| M12-02: `play_sfx` adoption in every view | — | ☐ open | Sonnet |
| M12-05: input parity audit (gamepad-only / kb-only) | — | ☐ open | Sonnet/Opus |

When all six are checked, **the M14 dependency gate opens and the boundary is
reached** — that is the moment to tag.

## Quality decision — owner call before tagging

- **#462 — finale grudge is unreachable + sabotage tokens are center-only.**
  Two SPEC §6 pillars are non-functional in the shipped client (invisible to
  CI). **Recommendation: fix before release** (a coin-purchased shop item that
  can't be aimed and a dead mechanic are a poor first-release impression), or
  make a deliberate call to ship with it and note it in the release. Model: Opus.

## Recommended but not blocking

- **M12-01 — balance pass** across all games at 2/4/6 (and now 12/24). Tuning
  only; the games are playable without it. Ship "good enough," iterate post-release.
- **#463 / #466 — measure + verify 24-player match cost** and add a nightly
  large-lobby playtest. The 24-player support is structurally done and
  unit-tested but not load-verified; worth doing before *advertising* 24-player,
  even if the tag ships first.

## Release hygiene (at tag time — AGENT_COORDINATION §8)

- [ ] `main` green; tag only from a freshly-pulled green tip.
- [ ] `git fetch --tags && gh release list` — pick the next number after the true latest.
- [ ] Bump the version constant / handshake if the release changes the protocol surface.
- [ ] Run `run_playtest.py` (6-bot) — and ideally `--players 12` / `--players 24` (#454) — as a final smoke.
- [ ] Update the in-game credits screen from `assets/CREDITS.md` (M7-04).
- [ ] Write release notes; announce on the release.
- [ ] After tagging: **lift the M14 hold** (remove the banner in IMPLEMENTATION_PLAN.md §5 and the note in AGENT_COORDINATION.md §8) so Genre Hop can begin.

## Bottom line

You can cut the release **as soon as the six blockers land** (all small /
in-flight — days of fleet work, not weeks), with the **#462 finale bug** being
the one quality call I'd make first. The hold guarantees nobody starts the
nine new M14 games in the meantime, so the boundary stays clean for you to tag.
