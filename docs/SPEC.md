# Party Rush — Game Specification

**Version:** 1.0 (initial spec, 2026-07-02)
**Status:** Approved by project owner. This document is the source of truth for *what* we are building. See [IMPLEMENTATION_PLAN.md](IMPLEMENTATION_PLAN.md) for *how* and *in what order*.

---

## 1. One-line pitch

A 2–6 player online party game in the style of Mario Party's minigame mode: friends join a private room via code, play a ~20-minute rush of 10–15 short minigames earning coins, and settle it all in a coin-fueled final showdown.

## 2. Locked decisions

These were decided with the project owner and are **not open for re-litigation** by contributing agents. If a decision below blocks you, flag it in a PR description rather than silently deviating.

| Area | Decision |
|---|---|
| Structure | Minigame rush (no board game) |
| Platform | Desktop app: **Windows, Linux, macOS** |
| Engine | **Godot 4.x** (GDScript) |
| Visuals | **2.5D isometric** — 3D low-poly scenes rendered with a fixed orthographic camera |
| Art strategy | CC0 / freely-licensed asset packs only (see §10) — chosen for easiest acquisition of models *and* animations |
| Multiplayer | Private rooms via 6-character join code |
| Hosting | **Dedicated authoritative server** (headless Godot export on a VPS) |
| Match length | ~20 minutes: 10–15 minigames + finale |
| Scoring | **Coins during minigames + final showdown** that can flip the standings |
| Minigame types | All four: chaotic free-for-all, skill/precision, team-based, sabotage/betrayal |
| Input | Keyboard (WASD), full controller support, mouse for aiming minigames |
| Player count | **AMENDED 2026-07-04 → up to 24** (owner directive, see [ADR 003](adr/003-player-count-24.md)). Originally 2–6. Not every minigame scales — brawlers/racers stay 6–8 by design; parallel games scale to 24. Small lobbies (2–6) are unchanged. |
| Disconnects | Player can **rejoin mid-match** with the room code; score preserved; match continues without them meanwhile |
| Characters | Roster of distinct selectable characters (no cosmetics/unlock system in v1) |
| V1 scope | **15+ minigames** at launch |

## 3. Design pillars

1. **Zero-friction fun** — from launching the app to playing with friends in under 60 seconds. One button to host, one code to join.
2. **Readable chaos** — 6 players on screen must always be identifiable at a glance (distinct silhouettes + player-color outlines/markers).
3. **Everyone stays in it** — coins + finale means last place in round 12 can still win. No minigame eliminates a player from the *match*.
4. **30-second rules** — every minigame is explainable in one sentence + one picture. Instruction screen shows controls and goal before each round.

## 4. Match flow

```
Launch → Main Menu → Host or Join (code) → Lobby (character select, ready-up)
  → Match start
    → repeat 10–15×:
        Minigame intro card (10 s, shows rules + controls, players ready-skip)
        → Minigame (45–90 s)
        → Results + coin award (8 s, running totals shown)
        → every 5 rounds: leaderboard interstitial with dramatic reveal
    → FINALE: The Gauntlet (§6)
  → Final podium + match summary → back to lobby (rematch keeps the room)
```

- The server picks minigames randomly **without repeats** within a match, respecting player-count constraints (§7) and ensuring category variety (no more than 2 of the same category in a row).
- Round count: host picks Quick (8 rounds), Standard (12, default), or Marathon (15) in the lobby.

## 5. Economy: coins

- **Placement award** per minigame (6-player values): 1st = 30, 2nd = 20, 3rd = 15, 4th = 10, 5th = 5, 6th = 3. With fewer players, use the top-N values (e.g. 3 players → 30/20/15). Team games: every member of the winning team gets 20, losers get 5; 3-team games 25/15/5.
- **Pickup coins**: some minigames contain collectible coins worth their face value (capped at ~30/round so pickups don't dwarf placement).
- **Ties** share the higher award.
- Coins are displayed persistently in the match HUD and are the input to the finale.

## 6. Finale: The Gauntlet

A last-player-standing elimination arena (shrinking isometric platform with escalating hazards), where the match's coins convert to survival power:

1. **Buy-in phase (30 s):** each player spends coins in a simple shop: extra life (100c, max 2), head-start shield (40c), speed boost (40c), sabotage token (60c — trigger one hazard manually during the finale).
2. **Gauntlet phase:** all players fight/survive; knocked-out players with lives remaining respawn after 3 s. Eliminated players spectate with a limited "grudge" ability (one-time hazard vote) so nobody is idle.
3. **Match ranking:** finale elimination order decides final match placement, ties broken by leftover coins, then by total coins earned. **Winner of the Gauntlet wins the match.**

Design intent: a big coin lead buys real advantage (≈2 extra lives) but never guarantees victory — skill in the finale can flip the standings, which was an explicit owner choice.

## 7. Minigame roster (v1 = 17)

Every minigame implements the shared **Minigame Contract** (see plan §M3): declared min/max players, category, duration, input needs, and a server-authoritative result of ranked placements + pickup coins.

### Chaotic free-for-all
| # | Name | One-liner | Players | Notes |
|---|---|---|---|---|
| 1 | Coin Scramble | Coins rain from the sky; grab the most, bump others to make them drop 20% | 2–6 | Pickup-coin heavy |
| 2 | King of the Hill | Score points standing in a zone that shrinks and relocates | 2–6 | |
| 3 | Hot Potato | A ticking bomb passes by touch; don't hold it when it blows (3 blasts) | 3–6 | Blast survivors ranked by hold-time |
| 4 | Thin Ice | Floor tiles crack and fall under footsteps; last one standing | 2–6 | Fall order = placement |
| 5 | Sumo Smash | Shove players off a platform; dash has a cooldown | 2–6 | Ring-out order = placement |

### Skill / precision
| # | Name | One-liner | Players | Notes |
|---|---|---|---|---|
| 6 | Simon Stomp | Repeat the flashing tile sequence by walking onto tiles; sequences grow | 2–6 | Elimination on error |
| 7 | Quick Draw | On the signal, hit the button first — false-start signals eliminate the trigger-happy | 2–6 | Best of 5 |
| 8 | Hurdle Dash | Isometric obstacle race to the finish line | 2–6 | Finish order = placement |
| 9 | Target Range | Mouse/stick-aimed shooting gallery; moving targets, shared arena | 2–6 | Highest score wins |
| 10 | Beat Bounce | Jump on the pad in rhythm; tempo increases; miss twice and you're out | 2–6 | |

### Team-based (random teams each round)
| # | Name | One-liner | Players | Notes |
|---|---|---|---|---|
| 11 | Tug of War | Alternating-key mashing tug; first team dragged over the line loses | 2–6 (even) | 1v1 to 3v3 |
| 12 | Relay Sprint | 2v2v2 relay through hazard lanes; tag your partner | 4 or 6 | 2-player fallback: head-to-head sprint |
| 13 | Cart Push | 3v3: push your mine cart to the depot first; opponents can body-block | 4–6 | |
| 14 | Color Clash | Paint floor tiles your team color; most tiles when time expires wins | 2–6 | Works FFA at 2–3, teams at 4–6 |

### Sabotage / betrayal
| # | Name | One-liner | Players | Notes |
|---|---|---|---|---|
| 15 | Poison Feast | Everyone eats dishes for points; one hidden saboteur poisoned three of them | 4–6 | Saboteur scores by poisonings |
| 16 | Trap Corridor | One trapper places hidden traps, the rest run the gauntlet; roles rotate | 3–6 | Trapper scores per catch |
| 17 | Heist Night | Lights cycle on/off; in the dark, steal pickup-coins from others' vaults | 3–6 | Theft is anonymous until the end reveal |

**Scaling rule:** at 2–3 players the server excludes games whose min-players exceed the lobby size; the roster guarantees ≥10 eligible games at any player count.

## 8. Characters

- Roster of **8 characters** from CC0 animated packs (KayKit character packs — knight, mage, barbarian, rogue, skeleton, etc.), giving distinct silhouettes with shared humanoid rigs and reusable animations (idle/run/jump/attack/KO/dance).
- Each player also gets a **player color** (fixed palette of 6) applied as outline + nameplate + minimap marker; color is the primary identity channel, character is flavor.
- Duplicate character picks allowed (colors disambiguate).
- Victory dance on podium; KO'd characters ragdoll or play the KO animation.

## 9. Multiplayer architecture

- **Topology:** dedicated authoritative server. Clients send inputs/intents; server simulates and replicates state. No client authority over gameplay-relevant state (party games die by cheating and host-advantage).
- **Transport:** Godot high-level multiplayer over **ENet (UDP), port 7777**. Desktop-only targets mean no WebRTC/WebSocket complexity needed in v1.
- **Tick model:** server physics/network tick 30 Hz; clients interpolate remote entities (~100 ms buffer) and use local prediction for own movement only where a minigame needs it (racing/sumo); most minigames are latency-tolerant by design.
- **Rooms:** one server process hosts many rooms. Room = 6-char code (unambiguous alphabet, no 0/O/1/I). Host = first player; host controls settings + start; host migration not needed (server is authority — if host disconnects, oldest member inherits lobby controls).
- **Session/rejoin:** on join, client receives a session token (UUID) stored locally. Rejoin = connect + present code + token → server restores player slot, score, and character; they sit out the in-progress minigame and rejoin at the next round. Disconnected players score 0 placement coins for missed rounds. Room dies 5 min after the last player leaves.
- **Server build:** Godot headless/dedicated-server export (Linux), same codebase as client, `--server` feature flag / dedicated_server export preset. Ships as a Docker image; deployable on any cheap VPS.
- **Server browser:** none. Direct connect to the official server address baked into config (overridable via settings file / CLI arg for self-hosters).

## 10. Art, audio & asset strategy

Chosen explicitly for **easiest acquisition of assets and animations**:

- **Characters:** [KayKit](https://kaylousberg.itch.io/) character packs (CC0, GLB, rigged + animated, shared rig). Primary choice because animations come free with the models.
- **Environment/props:** Kenney (kenney.nl, CC0) 3D kits — platformer kit, city kit, food kit, etc. Uniform low-poly style that matches KayKit.
- **Look:** 3D scenes, fixed orthographic camera at classic isometric angle (~30–45° pitch, 45° yaw) → the "2.5D isometric" feel without authoring 8-direction spritesheets.
- **UI:** Kenney UI packs + one rounded display font (e.g. Fredoka/Baloo, OFL).
- **Audio:** Kenney audio packs + freesound CC0 for SFX; music from Kevin MacLeod (CC-BY, credited) or CC0 packs.
- **Rule:** every imported asset's license must be CC0 or CC-BY, recorded in `assets/CREDITS.md`. No asset with unclear licensing enters the repo.

## 11. UX requirements

- Input: full remapping not required in v1, but all three schemes work everywhere — keyboard (WASD + Space/E), gamepad (stick + A/B), mouse only where a minigame is aim-based (those games must also offer stick aiming).
- Every minigame intro card shows: goal sentence, control diagram, category icon, and coin stakes.
- Connection status indicator; graceful "reconnecting…" overlay on drop.
- Settings: audio volumes, window/fullscreen, server address override.
- Nameplates + colored outlines always visible through occluders (silhouette shader).

## 12. Non-goals for v1

Explicitly out of scope (do not build): board mode, public matchmaking, accounts/persistence/progression, cosmetics/unlocks, voice chat, text chat (v1 uses quick-emotes only), spectator-only slots, mobile/web builds, localization (English only), anti-cheat beyond server authority, Steam integration.

## 13. Success criteria for v1

1. Six real players on three OSes complete a full 12-round match + finale with no desyncs or crashes.
2. A disconnected player rejoins within one round and finishes the match.
3. Cold start → playing with friends in < 60 s (excluding download).
4. All 17 minigames playable and fair at 2, 4, and 6 players.
5. Server runs a week on a 1-vCPU VPS hosting ≥10 concurrent rooms without restart.
