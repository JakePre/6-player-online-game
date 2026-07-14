> **Archived (2026-07-13, #953).** A dated snapshot audit — every finding
> below has a tracking issue, and all of them closed. Kept as a historical
> record only. Live task routing lives in [docs/ROUTING.md](../ROUTING.md).

# Project Review — 2026-07-07 (Fable exit review)

A full-project audit performed as the Fable tier retires: architecture, net
layer, all 45 sims/views/brains, the finale, testing, security seams, process
docs, and product-level gaps. Supersedes the 2026-07-05 review (whose findings
all closed: #462 fixed, #463 measured→#479 fixed, #464 capped, #465 gated).

Every actionable finding below has a tracking issue and a model tier
(complexity signal per [ROUTING.md](../ROUTING.md), not an
assignment). Jobs are filed as **unclaimed backlog specs** — claim per
[AGENT_COORDINATION.md](../AGENT_COORDINATION.md) §2 before starting.

## Where the project stands

~34K LOC source (21K minigames) / ~23K LOC tests · 45 minigames + Gauntlet
finale · 2–24 players · protocol v11 · five releases (latest v0.6.2) · zero
TODO/FIXME markers · board clear except M17-06.

**Phase change:** the project is feature-complete and pre-tuning. The
architecture bet paid off — one server-authoritative Minigame Contract
absorbed 45 games, the 24-player scaling pass, a finale economy, weapons, and
a full bot-AI layer without a structural rewrite. The risk profile has
inverted: the danger is no longer "can we build it" but **"is it fun and
fair" — and the project currently has no data-driven way to know.** The top
jobs all close that loop.

## The headline finding

**M19's strategic payoff never shipped (#705).** The bot brains were wired
into the *server* practice-bot pump only; `tests/soak/playtest_bot.gd` — the
client bots that generate the nightly `balance-telemetry-{2,4,6}` artifacts —
still runs the random `BotInputDriver`. Every nightly balance run since M19
still measures noise, and M12-01 (the balance pass) is blocked on data that is
silently not being collected. One S–M Opus PR unblocks the whole tuning phase.

## Findings & jobs

| # | Severity | Finding | Issue | Model | Depends on |
|---|---|---|---|---|---|
| 1 | 🔴 High | Playtest bots still random — M19 telemetry payoff missing; M12-01 blocked on phantom data | [#705](https://github.com/JakePre/6-player-online-game/issues/705) | Opus | — |
| 2 | 🔴 High | Finale KOs untagged — #584 weapons tuning question unanswerable | [#706](https://github.com/JakePre/6-player-online-game/issues/706) | Sonnet | — |
| 3 | 🔴 High | `_rpc_match_input` has no rate limit (emotes do) — flood vector on the public server | [#707](https://github.com/JakePre/6-player-online-game/issues/707) | Opus | — |
| 4 | 🟠 Med | Snapshot contracts stringly-typed in 3 places per game (sim/view/brain magic indices) | [#708](https://github.com/JakePre/6-player-online-game/issues/708) | Sonnet fan-out | — |
| 5 | 🟠 Med | 13 views rebuild entity nodes every snapshot — alloc/render churn at 24 players | [#709](https://github.com/JakePre/6-player-online-game/issues/709) | Opus + Sonnet fan-out | stage 1 first |
| 6 | 🟠 Med | Multi-room server capacity unmeasured (all load evidence is 1 room) | [#710](https://github.com/JakePre/6-player-online-game/issues/710) | Opus | — |
| 7 | 🟡 Product | Audio identity absent — 13 files for 45 games; the missing M13/M16-equivalent pass | [#711](https://github.com/JakePre/6-player-online-game/issues/711) (M20) | Opus + Sonnet fan-out | M20-01 first |
| 8 | 🟡 Product | Nothing persists — local stats/match-history screen (v1 approved; unlocks are NOT) | [#712](https://github.com/JakePre/6-player-online-game/issues/712) | Sonnet | — |
| 9 | 🟡 Product | M17-06 needs physical pads no agent has — restructure into owner checklist + fix queue | [#713](https://github.com/JakePre/6-player-online-game/issues/713) | Sonnet + Owner | — |
| 10 | 🟢 Hygiene | 63 remote branches, mostly merged claim residue | [#714](https://github.com/JakePre/6-player-online-game/issues/714) | Sonnet + Owner setting | — |
| 11 | 🟢 Deferred | Cooldown-blind / self-harming brains (nom_arena pays mass to lunge-spam) | [#715](https://github.com/JakePre/6-player-online-game/issues/715) | Sonnet | #705 + ~4 nights of data |
| 12 | 🟢 Docs | This review + post-Fable model re-routing | [#716](https://github.com/JakePre/6-player-online-game/issues/716) | Fable (this PR) | — |

**Audited and fine:** session tokens (`Crypto.generate_random_bytes(16)`),
server-side name sanitation, snapshot bandwidth at 24 (≤ ~1 MB/s/room, the
Color Clash outlier was delta-fixed in #479), version-mismatch handling, CI
gate coverage (lint/GUT/soak required + exports + nightly playtest + per-PR
minigame renders via #626).

**Explicit non-recommendation:** do not attempt web/HTML5 export casually.
Godot's web export cannot do ENet — it means a WebSocket/WebRTC transport
under `NetManager`, the most dangerous seam in the codebase. If reach matters,
itch.io desktop distribution + the existing self-updater (#144) is the cheap
90%.

## Suggested sequence

```
Week 1:  #705 playtest brains → #706 finale telemetry → #707 rate limit → #714/#716 hygiene+docs
Week 2:  data accumulates → #710 multi-room soak · #708/#709 fan-outs in parallel
Week 3:  M12-01 balance pass (Opus + owner checkpoints, on real data) → v0.7.0
Then:    M20 audio (#711) · stats v1 (#712) · M17-06 owner pad session (#713) · #715 brain tuning
```

The through-line: **stop building width, start closing the loop** —
instrument, measure, tune, release. The game is built; nobody yet knows if
it's balanced, and for a party game, feel is the product.

## What to protect (for the post-Fable fleet)

Three load-bearing disciplines are easy to erode by accident:

1. **The fair-information boundary.** Bots and clients see `get_snapshot()`
   plus their own private snapshot — never raw sim state. Every future
   feature must pass through it, however inconvenient. (The one time it was
   violated by accident — bots' `peer_id = 0` broadcasting private payloads,
   #688 — it was a real leak class.)
2. **The intentional-design locks.** SPEC §2 and PHASE2 §7 mark deliberate
   designs; "fixing" them has been reverted before (#174/#175). If a design
   smells deliberate, it is — ask on the issue.
3. **The claim protocol.** §2's self-assign + marker branch turned would-be
   duplicate builds into cheap withdrawals repeatedly. Its two hard-won
   amendments: an unassigned task-ID issue is still a claim (the #684/#687
   incident), and spec-filings must say "backlog, unclaimed" explicitly —
   which is why every job above carries that footer.
