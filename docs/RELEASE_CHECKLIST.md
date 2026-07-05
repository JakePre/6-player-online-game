# Release Checklist — the M14 boundary cut

> ## ✅ SHIPPED — [v0.6.0](https://github.com/JakePre/6-player-online-game/releases/tag/v0.6.0) (2026-07-05)
> All six blockers landed, `main` was green (1106/1106), the tag built all five
> platform presets, and the release published as Latest. The M14 RELEASE HOLD is
> **lifted** — Genre Hop is open. This file is retained as the record of the
> base-game release boundary; the checklist below is historical.

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
| M15: The Mole → 8 (‡ — owner override: capped at 8, not 12; plain bump) | #483 | ✅ merged | Sonnet |
| M15: Faulty Wiring → 12 (‡ — plain bump) | #474 | ✅ merged | Sonnet |
| M15: Fort Siege → 12 (‡ — plain bump) | #461 | ✅ merged | Sonnet |
| M10-14: Pickpocket Plaza (last M10 game — genuine hidden guard, owner call #359) | #491 | ✅ merged | Opus |
| M12-02: `play_sfx` adoption in every view | #482 | ✅ merged | Sonnet |
| M12-05: input parity audit (gamepad-only / kb-only) | #490 | ✅ merged | Sonnet/Opus |

**All six blockers have landed (2026-07-05).** The M14 dependency gate is open
and the boundary is reached — **this is the moment to tag.** Tagging is an
owner action (see "Release hygiene" below and AGENT_COORDINATION.md §8): agents
now HOLD on M14 until the owner cuts the release and lifts the hold.

## Quality decision — owner call before tagging

- ✅ **#462 — finale grudge/sabotage — FIXED** (PR #476). Sabotage now aims at
  the nearest living rival; eliminated players can aim + strike their grudge.
  The one hard quality question mark on the finale is resolved.

## Recommended but not blocking

- **M12-01 — balance pass** across all games at 2/4/6 (and now 12/24). Tuning
  only; the games are playable without it. Ship "good enough," iterate post-release.
- **#479 — Color Clash grid delta.** #463 measured the 24-player snapshot cost:
  the one outlier is **Color Clash @24 ≈ 4.4 MB/s/room** (full 576-tile grid
  every tick); everything else is ≤ ~1 MB/s. Fine on a dedicated server, a strain
  for self-hosted 24-player rooms. A targeted grid-delta (#479, Opus) cuts it to
  ~0.5 MB/s. **Should-fix, not a hard blocker** — owner call on pre- vs
  post-release. A general net-layer delta protocol was assessed and is **not**
  warranted (one outlier, not systemic).
- **#466 — nightly 12/24-player playtest** for standing large-lobby regression
  coverage. The harness exists (`run_playtest.py --players`); this wires it into
  CI. Worth having before *advertising* 24-player.

## Release hygiene (at tag time — AGENT_COORDINATION §8) — done for v0.6.0

- [x] `main` green; tag only from a freshly-pulled green tip. *(1106/1106, tagged from `7a7418a`.)*
- [x] `git fetch --tags && gh release list` — pick the next number after the true latest. *(v0.5.2 → v0.6.0.)*
- [x] Bump the version constant / handshake if the release changes the protocol surface. *(`AppVersion.VERSION` → 0.6.0 in #498; `PROTOCOL_VERSION` unchanged at 7 — no RPC break this cycle. Source drift now self-heals via #499.)*
- [x] Run `run_playtest.py` (6-bot) — and ideally `--players 12` / `--players 24` (#454) — as a final smoke. *(6-bot multiplayer soak green in CI on the tagged commit; nightly 12/24 variant now wired via #496.)*
- [x] Update the in-game credits screen from `assets/CREDITS.md` (M7-04). *(Auto-generated from the ledger at runtime — can't drift.)*
- [x] Write release notes; announce on the release. *(Workflow publishes the standard notes + auto-generated changelog.)*
- [x] After tagging: **lift the M14 hold** (banner in IMPLEMENTATION_PLAN.md §5 and the note in AGENT_COORDINATION.md §8) so Genre Hop can begin. *(This PR.)*

## Bottom line

You can cut the release **as soon as the six blockers land** (all small /
in-flight — days of fleet work, not weeks), with the **#462 finale bug** being
the one quality call I'd make first. The hold guarantees nobody starts the
nine new M14 games in the meantime, so the boundary stays clean for you to tag.
