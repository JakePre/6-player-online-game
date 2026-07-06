# Diagnostics logging (M18-06 / M18-07)

Owner directive (2026-07-06): during human testing we want a **massive,
analysable log** of everything that might explain a bug after the fact. The
server logs always; the client logs when the tester opts in via Settings.
This doc is the design and the catalog of *what to log* — the implementation
tasks (M18-06 server, M18-07 client) build to it.

The playtest wave (#575 crash, #578 Thin Ice desync, #601 ghost rigs) is
exactly the class of bug this exists to make diagnosable: hard to reproduce,
reported vaguely ("crashed everyone", "died without the tile breaking"), and
gone by the time anyone looks. A timestamped event trail turns "it broke" into
a line number.

## Format — one JSON object per line (JSONL)

Every entry is a single line of JSON so the whole log greps, `jq`s, and diffs,
and an analysis script can stream it. Precedent: the #548 balance telemetry
already emits per-round JSONL the nightly consumes.

```
{"t": 1751780421.317, "up": 42.10, "lvl": "INFO", "cat": "match", "ev": "round_start", "room": "ABCDEF", "round": 3, "game": "coin_scramble", "seed": 918273, "slots": [0,1,2,3]}
```

Required keys on every line: `t` (unix seconds, float), `up` (seconds since
process start — monotonic, survives clock changes), `lvl`, `cat`, `ev`.
Everything else is event-specific. Keep values primitive/flat so a line never
needs a parser beyond JSON.

### Levels

- `ERROR` — something is wrong (script error, RPC from an unknown peer, sim
  exception, version mismatch, malformed state).
- `WARN` — recoverable oddity worth noticing (tick overrun, snapshot backlog,
  reconnect, dropped malformed input, guard-rail rejection).
- `INFO` — lifecycle milestones (connections, room/match transitions,
  results). The default level.
- `DEBUG` — high-volume detail (per-tick timing, per-input receipts, snapshot
  sizes). Off by default; enabled by `--debug-log` (server) or the verbose
  toggle (client). This is the "log everything" firehose.

## Shared helper — `DiagnosticsLog`

One class both sides use (M18-06 builds it). Responsibilities:

- `DiagnosticsLog.event(cat, ev, fields := {})` — the single call site;
  stamps `t`/`up`/`lvl`, serializes, appends a line. Level is inferred per
  category or passed explicitly (`.warn(...)`, `.error(...)`).
- **Level gate** — below-threshold events are dropped before serialization
  (a `DEBUG` call is nearly free when the level is `INFO`).
- **Buffered writes** — append to an open `FileAccess`, flush on a short timer
  and on `ERROR`/shutdown, so logging never blocks the 30 Hz tick.
- **Rotation & retention** — a new file per process start named
  `user://logs/<role>-<YYYYMMDD-HHMMSS>.log`; cap each file (~50 MB) and keep
  the newest N (~10), deleting older ones so a long-lived server never fills
  the disk.
- **Crash safety** — install a hook so an uncaught script error is written as
  an `ERROR` line (with the message + where available, the script/line) before
  the process dies. This is the single highest-value line in the whole system.
- **Privacy** — display names and room codes are fine (already visible in
  game); never log session tokens, IPs beyond a coarse peer id, or anything a
  tester wouldn't paste into a bug report. Client logs live only on that
  tester's machine unless they choose to share.

## Server catalog (M18-06) — always on

The server is authoritative, so its log is the ground truth for any desync or
"it crashed everyone" report. Wire `DiagnosticsLog.event` at these points
(most already have a `print("[server] …")` that becomes a structured line):

- **Process**: `boot` (version, protocol_version, port, args), `shutdown`.
- **Connection** (`cat: net`): `peer_connect` / `peer_disconnect` (peer id),
  `handshake` (name, protocol_version, accepted?), `version_mismatch`
  (their version vs ours), `rejoin` (token matched → slot).
- **Room** (`cat: room`): `create`, `join`, `leave`, `kick`, `bot_add`,
  `bot_remove`, `host_change`, `ready_change`, `settings_change` (rounds,
  series, mutator pool, excluded games), `expire`.
- **Match** (`cat: match`): `match_start` (game order or selector seed),
  `round_intro` / `countdown` / `round_start` (game, seed, round_slots) /
  `round_end` (placements, per-slot scores + coins, duration_ms) /
  `leaderboard` / `finale_shop` / `podium` / `match_end` (final standings),
  `mutator_roll` (which mutator, params).
- **Gameplay** (`cat: game`, mostly DEBUG): notable sim events a game chooses
  to surface (KO, elimination, ring-out) via an optional hook; not required
  per game, but the hook exists.
- **Input** (`cat: input`): `malformed_drop` (WARN, from an unexpected shape),
  `rate` (DEBUG, inputs/sec per slot). Do **not** log every intent at INFO —
  that's the firehose, gated to DEBUG and sampled.
- **Snapshot** (`cat: snap`, DEBUG): per-broadcast size in bytes and per-room
  bandwidth (reuses the #463 measurement), backlog/skip WARN if a broadcast is
  late.
- **Timing** (`cat: tick`): `overrun` (WARN, tick exceeded its 1/30 s budget,
  with the duration), periodic `stats` (DEBUG: avg/max tick ms).
- **Errors** (`cat: err`, ERROR): any caught exception in the tick loop or an
  RPC handler, an RPC from a peer not in a room, a state assertion failing.

## Client catalog (M18-07) — opt-in

Off by default; a tester enables **Settings → (Network/Diagnostics) → "Save a
diagnostics log"**. When on, mirror the relevant client-side view of a session
so a bug report can attach both ends:

- **Session** (`cat: app`): `boot` (version, OS, resolution, settings
  snapshot minus secrets), `settings_change`, `shutdown`.
- **Connection** (`cat: net`): `connect_attempt` (address), `connected`,
  `connect_failed` (reason), `disconnect`, `reconnect`, `version_mismatch`,
  round-trip/ping estimate if available.
- **Match** (`cat: match`): `event_received` (type), `view_mount` /
  `view_unmount` (game id), snapshot cadence + `snapshot_gap` (WARN, a
  received-order/interval anomaly), interpolation `teleport` (a snap-instead-
  of-slide, the same signal the view uses).
- **Input** (`cat: input`, DEBUG): local intent sent (sampled), `device_change`
  (kb ↔ pad, from InputGlyphs).
- **Perf** (`cat: perf`): periodic FPS + frame-time; `spike` (WARN) on a long
  frame; dropped/late snapshots.
- **Errors** (`cat: err`, ERROR): script errors (via the shared crash hook),
  failed RPCs, asset/scene load failures.

### Sharing the log

The Settings/Diagnostics page gets **Open log folder** and **Copy log path**
so a tester can grab the file and attach it. Pairs with #609 (opt-in
crash/error report toggle) — the log is the payload that feature would send.

## Non-goals / guardrails

- Logging must never change behaviour or measurably cost frame time — buffered,
  level-gated, off-thread-of-tick flushing. If in doubt, drop to DEBUG.
- Not a replacement for GUT tests or the nightly telemetry (#548); this is
  observability for *humans testing live sessions*, not automated assertions.
- No secrets, ever (tokens, raw IPs). Client logs are local until shared.
