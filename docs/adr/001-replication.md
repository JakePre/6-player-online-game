# ADR 001: State replication — custom room-scoped snapshots over MultiplayerSynchronizer

**Status:** Accepted (M1-03)
**Date:** 2026-07-02

## Context

The dedicated server hosts **many rooms in one Godot process** (SPEC §9), all
sharing one `SceneMultiplayer`. Each room needs its gameplay state replicated
at 30 Hz to up to 6 clients, and nothing may leak between rooms.

Two candidate approaches:

1. **Godot's node-based sync** (`MultiplayerSpawner` + `MultiplayerSynchronizer`)
   — idiomatic, declarative, little code for the happy path.
2. **Custom snapshots** — the server serializes each room's state into a
   Dictionary and sends it to that room's members via an
   `unreliable_ordered` RPC; clients interpolate from the last two snapshots.

## Decision

**Custom room-scoped snapshots** (option 2), implemented in
`NetManager._rpc_snapshot` / `_broadcast_snapshots`.

Reasons:

- **Room isolation by construction.** Node-based sync replicates by scene-tree
  path and requires careful per-peer visibility management
  (`set_visibility_for`) to prevent cross-room leakage — the classic
  multi-room-single-process pain point. A snapshot loop that iterates a room's
  member list cannot leak by accident.
- **Rejoin is trivial.** A rejoining client is fully resynced by the very next
  snapshot; node-based sync requires respawning the peer's view of every
  replicated node.
- **Bandwidth control in one place.** One serialization site per room makes it
  easy to measure, cap, and later delta-compress; 6 players × ~10 entities at
  30 Hz is small, so plain full snapshots are fine for v1.
- **Testability.** Snapshot payloads are plain Dictionaries — the soak bots
  (tests/soak/) assert on delivery rate, and the fake-lag/loss harness wraps
  the single receive path.

Costs accepted: we hand-roll interpolation buffers on the client (M3 arena
helpers) and must maintain snapshot schema discipline per minigame.

## Consequences

- Minigames never touch RPCs directly: they fill a state Dictionary server-side
  and read the interpolated snapshot client-side (enforced by the Minigame
  Contract, M3-02).
- Client input is sent as intents on the unreliable channel; the server
  validates everything.
- Revisit trigger: if a fast-action minigame (Hurdle Dash, Sumo Smash) feels
  bad at 80 ms simulated latency even with interpolation + local prediction of
  the own character, evaluate adding per-entity delta compression or partial
  reliability — not a switch to node-based sync, which does not solve latency.

## Validation

The M1-05 soak harness runs a server + 6 headless bots (one exercising
disconnect→rejoin) with 80 ms artificial latency and 5 % loss, asserting
sustained ≥50 % snapshot delivery and ping round-trips. CI runs it on every PR.
