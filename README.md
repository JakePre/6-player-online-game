# Party Rush — 6-Player Online Minigame Party

A 2–6 player online party game in the style of Mario Party's minigame mode: join a private room via code, play a ~20-minute rush of short minigames earning coins, then settle it all in a coin-fueled final showdown.

## Start here

- **[docs/SPEC.md](docs/SPEC.md)** — full game specification (locked decisions, match flow, economy, 17-minigame roster, network architecture, asset strategy).
- **[docs/IMPLEMENTATION_PLAN.md](docs/IMPLEMENTATION_PLAN.md)** — milestones, task board with IDs, repo layout, and how contributing agents claim work.

## At a glance

| | |
|---|---|
| Engine | Godot 4.4.x (GDScript) |
| Platforms | Windows, Linux, macOS desktop |
| Visuals | 2.5D isometric (3D low-poly + orthographic camera) |
| Multiplayer | Dedicated authoritative server (headless Godot, Docker), private rooms via 6-char code |
| Players | 2–6, mid-match rejoin supported |
| Content | 17 minigames across 4 categories + "The Gauntlet" finale |
| Assets | CC0/CC-BY only (KayKit + Kenney), tracked in `assets/CREDITS.md` |

## Contributing (agents & humans)

1. Read the spec — decisions in SPEC §2 are locked.
2. Claim a task ID from the plan's task board via a GitHub issue.
3. Branch `feat/<task-id>-<slug>`, one task per PR, keep `main` always green.
