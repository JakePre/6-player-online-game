# Asset credits & licenses

Every third-party asset in this repository must be listed here **in the same PR
that adds it**, with its license and source. Only CC0 or CC-BY licensed assets
are allowed (SPEC §10). CC-BY entries must also appear in the in-game credits
screen (task M7-04).

| Asset | Path | Author | License | Source |
|---|---|---|---|---|
| KayKit Character Pack: Adventurers 1.0 (Barbarian, Knight, Mage, Rogue, Rogue Hooded — rigged + animated GLB) | `assets/characters/kaykit_adventurers/` | Kay Lousberg (KayKit) | CC0 1.0 | https://github.com/KayKit-Game-Assets/KayKit-Character-Pack-Adventures-1.0 |
| KayKit Character Pack: Skeletons 1.0 (Skeleton Mage, Minion, Rogue, Warrior — rigged + animated GLB) | `assets/characters/kaykit_skeletons/` | Kay Lousberg (KayKit) | CC0 1.0 | https://github.com/KayKit-Game-Assets/KayKit-Character-Pack-Skeletons-1.0 |
| Kenney Platformer Kit 4.1 (153 GLB models: floor/platform/ramp/hexagon blocks, props) | `assets/environment/kenney_platformer_kit/` | Kenney (kenney.nl) | CC0 1.0 | https://kenney.nl/assets/platformer-kit |
| Kenney Food Kit (200 GLB models: dishes, ingredients, tableware — for Poison Feast, #15) | `assets/environment/kenney_food_kit/` | Kenney (kenney.nl) | CC0 1.0 | https://kenney.nl/assets/food-kit |
| Kenney Nature Kit (329 GLB models: trees, rocks, bridges, fences — vertex-colored, no textures) | `assets/environment/kenney_nature_kit/` | Kenney (kenney.nl) | CC0 1.0 | https://kenney.nl/assets/nature-kit |
| Kenney City Kit: Commercial 2.1 (41 GLB models: buildings, storefronts — for Heist Night, #17) | `assets/environment/kenney_city_kit_commercial/` | Kenney (kenney.nl) | CC0 1.0 | https://kenney.nl/assets/city-kit-commercial |
| Basketball (MDL-002, #803 Basket Brawl) | `assets/generated/models/basketball.glb` | owner-generated (via Modly) | CC0 1.0 (original) | — |
| Basketball Hoop (MDL-001, #803 Basket Brawl) | `assets/generated/models/basketball-hoop.glb` | owner-generated (via Modly) | CC0 1.0 (original) | — |
| Dodgeball (MDL-003, #791 Dodgeball) | `assets/generated/models/dodgeball.glb` | owner-generated (via Modly) | CC0 1.0 (original) | — |
| Castle Gate (MDL-004, #808 Fort Siege) | `assets/generated/models/castle-gate.glb` | owner-generated (via Modly) | CC0 1.0 (original) | — |
| Castle Wall Segment (MDL-005, #808 Fort Siege) | `assets/generated/models/castle-wall-segment.glb` | owner-generated (via Modly) | CC0 1.0 (original) | — |
| Finish Arch (MDL-006, #785 Turbo Lap) | `assets/generated/models/finish-arch.glb` | owner-generated (via Modly) | CC0 1.0 (original) | — |
| Track Barrier (MDL-007, #785 Turbo Lap) | `assets/generated/models/track-barrier.glb` | owner-generated (via Modly) | CC0 1.0 (original) | — |
| Golf Flagstick (MDL-008, #793 Putt Panic) | `assets/generated/models/golf-flagstick.glb` | owner-generated (via Modly) | CC0 1.0 (original) | — |




| Anchor | `assets/generated/models/anchor.glb` | owner-generated (via Modly) | CC0 1.0 (original) | — || Shove Horn | `assets/generated/models/shove-horn.glb` | owner-generated (via Modly) | CC0 1.0 (original) | — || Hill Crest | `assets/generated/models/hill-crest.glb` | owner-generated (via Modly) | CC0 1.0 (original) | — || Meteor | `assets/generated/models/meteor.glb` | owner-generated (via Modly) | CC0 1.0 (original) | — |
Import note for the four Kenney packs above (M8-02, `docs/adr/002-iso-arena-rendering.md`): only
the `Models/GLB format/` (or `Models/GLTF format/` — same content, Kenney's
older zip naming) subfolder was kept, flattened into the pack's asset
directory; FBX/OBJ/DAE/STL formats and `Previews/` were dropped as unused
duplicates, same as the KayKit import convention. The platformer/food/city
packs each ship one shared `Textures/colormap.png` atlas referenced by
relative URI from every `.glb` in that pack — keep that subfolder alongside
the models. Nature Kit's models use flat vertex-color materials (no texture
file). `godot --headless --import` was run after adding these so every
`.glb` has a matching `.import` sidecar checked in, same as the character
packs.
| Kenney Interface Sounds (5 UI/chrome OGGs: click, confirm, error, tick, coin) | `assets/audio/kenney_interface_sounds/` | Kenney | CC0 1.0 | https://kenney.nl/assets/interface-sounds |
| Kenney Music Jingles (5 stinger OGGs: round start/win/lose, leaderboard, podium) | `assets/audio/kenney_music_jingles/` | Kenney | CC0 1.0 | https://kenney.nl/assets/music-jingles |
| "Monkeys Spinning Monkeys" (menu music loop) | `assets/audio/incompetech/menu_loop.mp3` | Kevin MacLeod (incompetech.com) | CC-BY 4.0 | https://incompetech.com |
| "Pixel Peeker Polka - faster" (round music loop) | `assets/audio/incompetech/round_loop.mp3` | Kevin MacLeod (incompetech.com) | CC-BY 4.0 | https://incompetech.com |
| "Exhilarate" (finale music loop) | `assets/audio/incompetech/finale_loop.mp3` | Kevin MacLeod (incompetech.com) | CC-BY 4.0 | https://incompetech.com |
| "Fluffing a Duck" (round music rotation, M20-01 #711) | `assets/audio/incompetech/round_loop_duck.mp3` | Kevin MacLeod (incompetech.com) | CC-BY 4.0 | https://incompetech.com |
| "Run Amok" (round music rotation, M20-01 #711) | `assets/audio/incompetech/round_loop_amok.mp3` | Kevin MacLeod (incompetech.com) | CC-BY 4.0 | https://incompetech.com |
| "Scheming Weasel (faster)" (round music rotation, M20-01 #711) | `assets/audio/incompetech/round_loop_weasel.mp3` | Kevin MacLeod (incompetech.com) | CC-BY 4.0 | https://incompetech.com |
| "Grand Opening" (round music rotation, #830) | `assets/audio/lud_and_schlatt/grand_opening.mp3` | Lud and Schlatt's Musical Emporium (Philip Milman) | Copyright-free, credit required | https://pmmusic.pro/downloads/ |
| "2PM" (round music rotation, #830) | `assets/audio/lud_and_schlatt/2pm.mp3` | Lud and Schlatt's Musical Emporium (Philip Milman) | Copyright-free, credit required | https://pmmusic.pro/downloads/ |
| "10AM" (round music rotation, #830) | `assets/audio/lud_and_schlatt/10am.mp3` | Lud and Schlatt's Musical Emporium (Philip Milman) | Copyright-free, credit required | https://pmmusic.pro/downloads/ |
| Kenney Impact Sounds (10 gameplay OGGs, M20-01 #711 — renamed semantically; sources fingerprinted: hit=impactPunch_medium_000, hit_heavy=impactPunch_heavy_004, ko=impactMetal_heavy_004, thud=impactSoft_heavy_000, bump=impactSoft_medium_002, clang=impactMetal_medium_000, bell=impactBell_heavy_002, break_wood=impactPlank_medium_004, crack=impactGlass_light_001, shatter=impactGlass_heavy_001) | `assets/audio/kenney_impact_sounds/` | Kenney | CC0 1.0 | https://kenney.nl/assets/impact-sounds |
| Kenney Digital Audio (8 gameplay OGGs, M20-01 #711 — renamed semantically; sources fingerprinted: jump=phaseJump1, dash=phaserUp4, zap=zap1, laser=laser4, alarm=lowThreeTone, powerup=powerUp7, powerdown=phaserDown1, pop=pepSound1) | `assets/audio/kenney_digital_audio/` | Kenney | CC0 1.0 | https://kenney.nl/assets/digital-audio |
| Splash + explosion one-shots (M20-01 #711) — **original**, synthesized by the committed deterministic generator `scripts/synth_sfx.py` (fixed seed; re-running reproduces the files) | `assets/audio/party_rush_synth/*.wav` | Party Rush project | CC0 1.0 (original) | — |
| Lilita One (display font, M16-01) | `assets/fonts/LilitaOne-Regular.ttf` | Juan Montoreano | OFL 1.1 (`assets/fonts/OFL-LilitaOne.txt`) | https://github.com/google/fonts/tree/main/ofl/lilitaone |
| Nunito variable (body font, M16-01) | `assets/fonts/Nunito-Variable.ttf` | Vernon Adams, Cyreal, Jacques Le Bailly | OFL 1.1 (`assets/fonts/OFL-Nunito.txt`) | https://github.com/google/fonts/tree/main/ofl/nunito |

## Planned sources (not yet imported)

- Kenney UI + audio packs — CC0 — https://kenney.nl/assets. Same fetch trick as above: each kit's `kenney.nl/assets/<slug>` page's "Download" button is JS-driven (no plain `<a href>` to the zip), but the actual zip URL is embedded in the page HTML as the `Continue without donating...` link's `href` (pattern `kenney.nl/media/pages/assets/<slug>/<hash>/kenney_<slug>.zip`) — `curl` the page HTML and grep for `.zip`, no browser needed.
- Music: CC0 packs or Kevin MacLeod (CC-BY, requires credit) — https://incompetech.com

## Development tools bundled in-repo

| Tool | Path | License |
|---|---|---|
| GUT (Godot Unit Test) 9.4.0 (last release supporting Godot 4.4; 9.5+ needs 4.5) | `addons/gut/` | MIT — https://github.com/bitwes/Gut |

## Data files

| Data | Path | License |
|---|---|---|
| SDL_GameControllerDB community controller mappings (M17-01) | `assets/input/gamecontrollerdb.txt` | zlib — https://github.com/mdqinc/SDL_GameControllerDB |
| Kenney Music Jingles — round_start replaced with `jingles_NES12` (#591: the original, `jingles_NES00`, is a 1.8 s descending/decaying phrase that reads as "game over"; NES12 is a 0.9 s ascending stinger from the same 8-bit family as the win/lose cues). Sources fingerprinted: start=NES00→NES12, win=NES01, lose=NES03, leaderboard=PIZZI00, podium=STEEL00. | `assets/audio/kenney_music_jingles/round_start.ogg` | Kenney | CC0 1.0 | https://kenney.nl/assets/music-jingles |
| Shred Session per-lane drum one-shots (kick/snare/hat/tom, #585/#798) — **original** 808/909-style drum-machine voices, synthesized by the committed deterministic generator `scripts/synth_drums.py` (fixed seed; re-running reproduces the files byte-for-byte), no third-party source. | `assets/audio/shred_drums/*.wav` | Party Rush project | CC0 1.0 (original) | — |
