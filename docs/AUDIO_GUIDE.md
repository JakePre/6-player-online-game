# Audio Guide — the Party Rush sound vocabulary (M20-01, #711)

Visuals got M16, animation got M13 — this is audio's pass. One shared,
semantic vocabulary lives in `AudioManager.SFX`; games fire cues through the
existing `play_sfx(&"name")` hook (M12-02 put the call sites everywhere).
The M20-02 fan-out is **re-pointing names, not new wiring**: each game swaps
its generic `confirm`/`error`/`coin` calls for 2–4 signature cues below.

## The rules

1. **Shared meanings stay shared.** A cue in the *shared* table means the same
   thing in every game, always. The #591 incident (a "game over"-sounding
   jingle on round *start*) is the failure class this prevents. Never repurpose
   `ko` for a score, or `coin` for damage.
2. **2–4 signature cues per game.** Pick from the vocabulary; don't invent
   names ad hoc. If a game genuinely needs a sound with no fitting name, add it
   here first (see "Adding sounds") so the next game with the same need reuses
   it.
3. **Respect the 30 Hz reality.** Cues fire from snapshot diffs; a cue that can
   trigger every snapshot (movement, holding, channeling) will machine-gun.
   Fire on *edges* (state changes, count changes) — the M13 FX-diff sets
   (`_last_*_keys`) are the right trigger points.
4. **Unknown names are silently ignored** by `play_sfx`, so views may call
   speculatively — but a typo'd name is silent forever. The GUT vocabulary test
   pins every registered path to a real file; keep it green.
5. **`my_slot` louder than the room.** Prefer firing personal cues (your hit,
   your pickup) only for `slot == my_slot`, and world cues (explosion, shatter)
   for everyone — the established pattern in coin_scramble.

## Shared vocabulary (same meaning in every game — do not repurpose)

| Name | Meaning | Source |
|---|---|---|
| `click` / `confirm` / `error` / `tick` | UI press · accepted · rejected/hurt-generic · countdown or timer beat | Kenney Interface |
| `coin` | currency gained | Kenney Interface |
| `round_start` / `round_win` / `round_lose` | round stingers (chrome fires these — games don't) | Kenney Jingles |
| `leaderboard` / `podium` | standings stingers (chrome) | Kenney Jingles |
| `ko` | a player is eliminated / knocked out, terminally for the round | Impact `impactMetal_heavy_004` |
| `powerup` | item / buff / weapon gained | Digital `powerUp7` |
| `powerdown` | debuff: stagger, poison, slow, stun | Digital `phaserDown1` |
| `alarm` | danger telegraph: exposure, suspicion, fuse about to blow | Digital `lowThreeTone` |

## Signature vocabulary (pick per game)

| Name | Feel / use for | Source |
|---|---|---|
| `hit` | a landed blow, jab, tag | Impact `impactPunch_medium_000` |
| `hit_heavy` | charged smash, critical, big launch | Impact `impactPunch_heavy_004` |
| `thud` | heavy object lands: boulder, meteor, axe, dropped block | Impact `impactSoft_heavy_000` |
| `bump` | non-damaging body contact: shove, bounce-off, block knocked loose | Impact `impactSoft_medium_002` |
| `clang` | metal: weapons crossing, gate battering, armor | Impact `impactMetal_medium_000` |
| `bell` | bright positive target hit: bullseye, basket, checkpoint | Impact `impactBell_heavy_002` |
| `break_wood` | crate / soft wall / plank gives way | Impact `impactPlank_medium_004` |
| `crack` | first warning fracture: ice under you, tile about to drop | Impact `impactGlass_light_001` |
| `shatter` | the fracture completing: tile drops, glass gone | Impact `impactGlass_heavy_001` |
| `explosion` | bomb / blast / meteor impact | synth (`scripts/synth_sfx.py`) |
| `splash` | water entry: dive, ball in the drink | synth (`scripts/synth_sfx.py`) |
| `jump` | player jump | Digital `phaseJump1` |
| `dash` | dash / lunge / swap-dash whoosh | Digital `phaserUp4` |
| `zap` | electric: shock tag, live wire, trap zap | Digital `zap1` |
| `laser` | beam fire / sweep | Digital `laser4` |
| `pop` | small consume: dish eaten, graze coin, bubble | Digital `pepSound1` |

## Suggested cues by archetype (fan-out starting points, not law)

| Archetype (games) | Signature cues |
|---|---|
| Brawlers (rumble_ring, knock_off, bey_brawl) | `hit`, `hit_heavy`, `bump`, `ko` |
| Bombs (blast_grid, bomb_courier, meteor_shower) | `explosion`, `break_wood`/`thud`, `alarm` |
| Ice / tiles (thin_ice, memory_match, musical_platforms) | `crack`, `shatter`, `ko` on the drop |
| Water (treasure_divers, fish_frenzy, putt_panic hazards) | `splash`, `pop`, `coin` |
| Electric (shock_tag, faulty_wiring, laser_limbo, trap_corridor) | `zap`, `laser`, `alarm` |
| Aim / targets (target_range, bullseye_bowl, quick_draw, basket_brawl) | `bell`, `laser`/`hit`, `error` on miss |
| Platformers (tumble_run, loadout_duel, hurdle_dash, gauntlet) | `jump`, `thud`, `clang`/`laser`, `dash` |
| Collect / feast (coin_scramble, nom_arena, poison_feast, heist_night) | `coin`/`pop`, `powerdown` (poison), `alarm` (heist lights) |
| Team objects (wall_builders, cart_push, fort_siege, tug_of_war, relay_sprint) | `bump`, `clang` (gate), `break_wood`, `bell` (delivery) |

## Music

`AudioManager.MUSIC` maps channel names to **pools**: `menu` and `finale` are
single loops; `round` holds four and rotates. `play_music(&"round")` starts the
pool's current track; the match screen calls `advance_round_music()` on every
round intro after the first, so consecutive rounds get different loops (and the
rotation position carries across matches). Volume stays owned by the
settings-store bus sliders — the manager only crossfades its own player.

All four round loops + menu + finale are Kevin MacLeod (incompetech, CC-BY 4.0
— every track needs its CREDITS.md row with the title).

## Adding sounds

- **Kenney packs** (CC0): the zip URL is embedded in each
  `kenney.nl/assets/<slug>` page's HTML (`grep` for `.zip` — the download
  button is JS-only). Copy the chosen file into the pack's
  `assets/audio/kenney_*/` dir **renamed to its semantic name**, and record the
  source-file fingerprint in the CREDITS.md row (precedent: the #591 row).
- **Nothing fits?** `scripts/synth_sfx.py` — deterministic (fixed seed),
  stdlib-only — is the pattern for original one-shots (splash, explosion).
  Extend it, commit the generator change with the WAV, credit as
  "Party Rush project, CC0 (original)".
- Register the name in `AudioManager.SFX`, add the meaning to a table above,
  and the vocabulary GUT test keeps the path honest.
