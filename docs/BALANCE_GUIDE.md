# Balance Guide — interpreting telemetry without breaking designs (M12-01, #730)

The M12-01 balance pass tunes games from nightly telemetry. Its one
catastrophic failure mode has already happened once: an agent reads a number,
calls a *design* an *imbalance*, and "fixes" it — reverted at owner cost
(#174/#175, Poison Feast). This guide is the layer between
`scripts/analyze_balance.py`'s review prompts and any tuning PR.

## Procedure (post-Fable routing: Opus + mandatory owner checkpoint)

1. **Collect**: download every `balance-telemetry-{2,4,6}` artifact since the
   last pass (nightly `balance` job; backfill runs via `workflow_dispatch`).
2. **Analyze**: `python scripts/analyze_balance.py *.json`. Treat `review:`
   lines as questions, never as verdicts. Ignore any cell under n≈10.
3. **Classify each flag** with the tables below: *intentional design* (drop),
   *bot artifact* (route to #715, not a game change), or *candidate imbalance*.
4. **Owner checkpoint**: post the candidate list — per game: the numbers, your
   reading, the proposed tuning-only change — on the claim issue and get an
   explicit go-ahead **before** touching a sim. One game = one commit;
   tuning-only PRs (constants, weights, timers — never mechanics).
5. Re-run the analyzer after the next nights and verify the number moved.

## Reading the flags

**`timeout_rate` is only meaningful for games that CAN end early.**
Fixed-duration score games run to the cap *by design* — 100% timeout is not a
finding. First real sample (2026-07-07): `pickpocket_plaza @4p timeout 100%`
— correct behavior for a 60 s scoring window.

| Always run full duration (timeout by design) | Can end early (timeout_rate meaningful) |
|---|---|
| pickpocket_plaza, king_of_the_hill, coin_scramble, color_clash, heist_night, nom_arena, fish_frenzy, basket_brawl, cart_push (cap), beat_bounce/simon_stomp/count_quick/shred_session (sequence caps), target_range, poison_feast, treasure_divers, snake_chain (score cap variant) | elimination games (thin_ice, sumo_smash, rumble_ring KOs, bullet_waltz, blast_grid, laser_limbo, memory_match, meteor_shower, hot_potato, shock_tag), races (hurdle_dash, relay_sprint, turbo_lap, tumble_run), objective games (wall_builders height, fort_siege capture, bomb_courier, quick_draw, ro_sham_bo, knock_off/loadout_duel stocks, the_mole, faulty_wiring, trap_corridor, tug_of_war, putt_panic, bullseye_bowl) |

**Suspiciously-fast medians** in elimination games are usually *bot* behavior,
not game behavior — first sample: `sumo_smash @4p median 2s` (brains likely
rush center and mass ring-out; a human lobby lasts much longer). Check the
brain before the sim (#715), and prefer fixing the bot to nerfing the game.

**Full-tie rates** with homogeneous bots overstate real tie rates: every seat
runs the same policy at the same cadence. High but not-flagged tie rates in
mirror-strategy games are expected artifacts.

**Slot bias** (a seat winning far over uniform) IS worth chasing at n≥10 —
spawn rings are shared code, but per-game spawn layouts, first-mover item
spawns, or corner adjacency can leak real advantage. This is the flag least
likely to be intentional.

**Award economy** (`coins/rd`): cross-game equity matters at the match level —
a game paying 2× the catalog mean distorts every match containing it. Compare
against SPEC §5 award tables before judging; some categories pay intentionally
richer (finale buy-in feeds on it).

## Intentional-design map (do NOT "fix" these — the #174 list)

| Game | Expected telemetry signature | Why it's the design |
|---|---|---|
| poison_feast | High score variance, occasional negative scores, pot swings | Post-#174 rework IS push-your-luck: 25%/50% poison odds printed on the card. Variance is the fun. Tuning candidates: odds/points *ratios*, never removing the gamble. |
| ro_sham_bo | Heavy tie/luck signature, flat win shares | It is rock-paper-scissors. Luck-dominant by definition; sudden-death exists to force resolution, not to reward skill. |
| quick_draw | All-or-nothing placements, tiny durations per sub-round | Reaction duel — a 200 ms decide-everything window is the genre. |
| tug_of_war | Near-100% ties **with bots** | Identical mashing cadence = identical pull. Says nothing about human balance; the sim already handicaps uneven teams. |
| the_mole, faulty_wiring, pickpocket_plaza, trap_corridor | Role-holder win rates far from uniform at small n | One guard/mole vs many: per-round asymmetry is role luck. Judge only the *aggregate* role win rate over many rounds (mole should win a healthy minority, not half). |
| hot_potato, shock_tag | Last-second KO clustering, duration ≈ cap | Timer-pressure games — the cliff is the tension. |
| knock_off, loadout_duel | Long metas (79.5 s / 152 s incl. sub-rounds), stock-based swings | Multi-sub-round structures; don't read sub-round blowouts as imbalance. |
| gauntlet (finale) | Skewed placements toward shop spenders | Buy-in advantage is the finale's economy design (#554). KO-source questions route to #706 telemetry, not placement stats. |
| trap_corridor 150 s meta | Longest cap in the catalog | Deliberate slow-burn (owner "more teeth" pass); duration is not drift. |

## Bot artifacts vs balance signals (#715 overlap)

Telemetry measures **brains playing games**, not games. Known artifact
classes: cooldown-blind spam (nom_arena lunge mass-loss), mirror-policy ties,
center-rush pileups (sumo_smash above), brains that never use a mechanic
(nobody buys X in the shop ⇒ X looks worthless). Rule: **if a flag would
vanish with smarter/diverse bots, it's a #715 item.** When in doubt, watch one
round locally (`run_playtest.py --balance --players 4`) before proposing a
game change.

## Sample-size reality (#730)

At the original 12 rounds/run the catalog needed ~40 nights per 10-obs cell;
the nightly balance job now runs 48 rounds × 3 head-counts (~1 obs per cell
per night). Coarse red-flags: ~4 nights. Solid per-game reads: ~2 weeks, or
run the `balance` job repeatedly via `workflow_dispatch` for a weekend
backfill. `scripts/game_durations.json` feeds the analyzer's timeout math —
regenerate it when a game's `duration_sec` meta changes.
