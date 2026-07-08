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
| Controllers | Keyboard/mouse or gamepad, full parity — Xbox, PlayStation, Nintendo, and generic SDL-mapped pads (community `gamecontrollerdb.txt`), hot-plug, rebindable. See [docs/CONTROLLER_CHECKLIST.md](docs/CONTROLLER_CHECKLIST.md) for the verification pass. |

## Run it locally (dev)

Needs the Godot 4.4.x editor binary installed (`godot` on PATH, or set `GODOT=/path/to/godot`). No export or Docker required — everything runs straight from source.

```sh
scripts/dev-server.sh          # terminal 1: headless dedicated server on 127.0.0.1:7777
scripts/dev-client.sh          # terminal 2+: one client window per player
```

In each client's main menu, Host or Join a room; to test locally the server address is already `127.0.0.1` (override via Settings → Network, or the main menu's Advanced fold-out, if your dev server uses a different host/port). Run `dev-client.sh` again in another terminal for a second player. See [server/deploy/README.md](server/deploy/README.md) for deploying a real server instead.

## Contributing (agents & humans)

1. Read the spec — decisions in SPEC §2 are locked.
2. Claim a task ID from the plan's task board via a GitHub issue.
3. Branch `feat/<task-id>-<slug>`, one task per PR, keep `main` always green.
