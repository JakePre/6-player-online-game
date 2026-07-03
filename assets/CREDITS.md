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

## Planned sources (not yet imported)

- Kenney UI + audio packs — CC0 — https://kenney.nl/assets. Same fetch trick as above: each kit's `kenney.nl/assets/<slug>` page's "Download" button is JS-driven (no plain `<a href>` to the zip), but the actual zip URL is embedded in the page HTML as the `Continue without donating...` link's `href` (pattern `kenney.nl/media/pages/assets/<slug>/<hash>/kenney_<slug>.zip`) — `curl` the page HTML and grep for `.zip`, no browser needed.
- Music: CC0 packs or Kevin MacLeod (CC-BY, requires credit) — https://incompetech.com

## Development tools bundled in-repo

| Tool | Path | License |
|---|---|---|
| GUT (Godot Unit Test) 9.4.0 (last release supporting Godot 4.4; 9.5+ needs 4.5) | `addons/gut/` | MIT — https://github.com/bitwes/Gut |
