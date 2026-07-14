# Task routing — recommended model tier, live queue only

Owner-requested (2026-07-04): every task carries a recommended model tier as a
**complexity signal** for whichever agent picks it up — not an assignment.
This file is an INDEX of open work; the issue is the source of truth for
scope. Archived/superseded routing history (dominated by ✅-done rows that
kept getting mistaken for live work — the reason this file was split out,
#953) lives in [docs/history/MODEL_ROUTING.md](history/MODEL_ROUTING.md).

Rubric:

- **Fable 5** — design-judgment-heavy, cross-cutting, or technically novel;
  ambiguity that a wrong guess makes expensive (precedent: reverted "fixes" of
  intentional designs, PHASE2.md §7 / issue #174/#175).
- **Opus 4.8** — real engineering with an established pattern in the repo to
  follow; self-contained builds.
- **Sonnet 5** — mechanical, template-following changes with the hard
  decisions already made upstream.

> **Fable 5 tier retirement (2026-07-07).** Fable was slated to go away —
> tasks routed to Fable were meant to fall back to **Opus 4.8 + a mandatory
> owner checkpoint** (post the proposal, get an owner go-ahead before
> building). In practice Fable sessions have continued to run design/audit
> work since; treat this note as historical context for *why* some rows below
> carry "Opus + owner checkpoint" phrasing rather than a live policy.

**Keep this file current:** when you claim a task, delete or strike its row
here (the issue itself is still the record). When new tasks are filed in a
batch, classify them in the same PR/comment, not here — this file only
tracks the routing tier, never re-derive scope from it.

## Fable 5 — judgment-heavy, cross-cutting, or technically novel

| Issue | Task |
|---|---|
| #971 | Sim/view derived-value desync audit — Fable finishes the bug-class classification (first pass done) → Opus/Sonnet for the bucket-3 conversions |

## Opus 4.8 — real engineering, clear precedent

| Issue | Task |
|---|---|
| #759 | M12-01 balance — stage 1 (classification) done; stage 2 is per-game tuning through #961/#962, each with owner sign-off |
| #918 | Meteor Shower — staged circle shrink (Gauntlet pattern) + meteor model |
| #920 | Gauntlet — swing-while-walking teleport fix (root-caused) + range telegraph |
| #923 | Framework: nameplate declutter in crowds |
| #925 | Side-scroll tier (knock_off/loadout_duel/tumble_run) presentation pass (L) |
| #926 | Bot degeneracies: corner-camping, tilt_deck stalemate, meteor dodge-into-danger — coordinate with #715/#962 before claiming |
| #927 | Sumo Smash — 2-second bot rounds + ring-render regression (do first — smells live) |
| #928 | Laser Limbo — beam height readability |
| #932 | Cart Push → Payload Race rework, owner-approved concept locked (M-L) |
| #933 | Nightly render contact sheet + fast-round telemetry flag |
| #934 | End-of-match superlatives |
| #935 | Hat shop — persistent cosmetics (L) |
| #936 | Finale variety — Storm Court/Kingslayer/Magma Ascent locked; Storm Court buildable now |
| #939 | Stage shell — themed backdrop replacing the grey void (L) |
| #941 | EdgeTracker helper (Opus) → Sonnet fan-out across 11 views |
| #942 | CharacterRig.play_protected() — unify 4 animation-hold idioms |
| #943 | Split match_screen.gd (928 lines) |
| #945 | SimGeometry + cooldown-ring helpers (Opus) → Sonnet call-site fan-out |
| #946 | Snapshot schema tripwire — design done, Sonnet fan-out in progress (batches 1-3 merged) |
| #947 | Declarative INPUT_MAP on view bases (Opus) → Sonnet fan-out |
| #948 | Extract arena-dressing from minigame_view_3d.gd (601 lines) |
| #944 | [EPIC] Homage wave — 8 child issues, parallel claims: #949 Blast Grid, #950 Snake Chain, #954 Nom Arena, #955 Color Clash, #956 Turbo Lap, #957 Shred Session, #958 The Mole, #959 Bullet Waltz |
| #961 | Round-length collapse cluster — 8 games, diagnose-then-tune, per-game claims |
| #962 | fort_siege brain orphaned by #808 rework + perfect-memory tie walls (simon_stomp/memory_match) |
| #963 | [EPIC] M21 Steam distribution — 6 phased sub-issues (#964-969), **⛔ gated on owner go-ahead** |

## Sonnet 5 — mechanical, pattern-following

| Issue | Task |
|---|---|
| #715 | Brain quality pass — data gate lifted; overlaps #926/#962, coordinate before claiming |
| #929 | Art dressing batch: cart/court/powerups/zones/water/rocks/rim |
