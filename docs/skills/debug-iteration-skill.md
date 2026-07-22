---
name: debug-iteration-skill
description: >
  Focused live-debug loop for iterating on a single minigame. Agent hosts a
  debug RPC server + client with bots, the user plays a round, suggests
  changes, and the agent edits and relaunches — repeat till the user is happy.
---

# Debug Iteration Skill

## Purpose

Iterate rapidly on one minigame's gameplay/UX: the agent boots a full debug
session (server + client), the user plays a round with bots and reports what
to change, the agent edits and relaunches. Every cycle is: launch → play →
feedback → edit → relaunch.

## Lifecycle

```
SETUP → [ LAUNCH → PLAY → FEEDBACK → EDIT → RELAUNCH ]* → DONE
```

- **SETUP**: resolve the minigame id, confirm the Godot binary exists, create or verify the `usertest-<minigame_id>` branch.
- **LAUNCH/RELAUNCH**: start/restart the debug-server and debug-client processes.
- **PLAY**: user plays the round. Agent waits.
- **FEEDBACK**: user reports what's wrong or what to change.
- **EDIT**: agent makes the requested changes.
- **DONE**: user says stop (or `/loop stop` if inside loop mode). Agent commits, pushes, and creates a PR.

## Prerequisites

- Godot binary on `$GODOT`, `godot4`, or `godot` (same resolution as
  `scripts/dev-server.sh`).
- A minigame id known to `MinigameCatalog` (e.g. `coin_scramble`, `basket_brawl`,
  `shred_session`). Run `--debug-minigame=<id>` once to check.

## Convention: "debug game" = one minigame

The user and agent agree on one minigame id. The agent **must** verify the id
against the catalog before launching — `--debug-minigame=typo` fails silently.
If unsure, grep `MinigameCatalog.register_builtins` or the directory listing at
`src/minigames/` (each subdir name is the id, e.g. `coin_scramble`).

## Branch management

On SETUP, the agent manages a branch named `usertest-<minigame_id>`:

1. Check if `usertest-<minigame_id>` exists locally or on `origin`.
2. **Does not exist** — create it from `main`:
   ```
   git checkout main
   git checkout -b usertest-<minigame_id>
   ```
3. **Exists** — switch to it and ensure it's caught up to `main`:
   ```
   git checkout usertest-<minigame_id>
   git merge main
   ```
   If the merge fails (conflicts), **do not proceed**. Error out and ask the user
   what to do — the branch has diverged from `main` and needs manual resolution.
4. All edits during the session happen on this branch.

## Process ownership

The agent **owns** exactly two `hub` processes:

| name | application | key args |
|------|-------------|----------|
| `debug-server` | `godot4` (via `scripts/dev-server.sh`) | `--debug-rpcs` |
| `debug-client` | `godot4` (via `scripts/dev-client.sh`) | `--debug-minigame=<id> --debug-bots=5` |

### Launch sequence

1. Kill any prior `debug-server` / `debug-client` (`hub stop`).
2. Start `debug-server` — use `hub start` with the dev-server script. Wait for
   readiness: the log line `SERVER READY` or the port (default `NetConfig.DEFAULT_PORT` = 7777).
   Use `ready.log` regex or `ready.port`.
   ```
   hub start name=debug-server
     application=bash
     args=["scripts/dev-server.sh", "--debug-rpcs"]
     ready={log: "SERVER READY", port: 7777, timeout: 60}
     restart=on-failure
   ```
3. Once the server is ready, start `debug-client` — use `hub start` with the
   dev-client script. Do NOT wait for readiness (the client opens a window and runs).
   ```
   hub start name=debug-client
     application=bash
     args=["scripts/dev-client.sh",
           "--debug-minigame=<MINIGAME_ID>",
           "--debug-bots=5"]
     restart=no
   ```
   Bot count: 5 bots for a full 6-player round (1 human + 5 bots). Adjust if
   the minigame supports fewer — check `MinigameMeta.max_players` for the id.
4. Print `[debug-iteration] launched <minigame_id> — play the round and report back`.
5. Start a background watcher that monitors the `debug-client` process. When the
   client exits (user closes the window, crash, or any reason), the watcher
   automatically stops the `debug-server`:
   ```
   task name=debug-watcher
     task: "Run `hub wait name=debug-client` then `hub stop name=debug-server`."
   ```
   This ensures the server is never left orphaned after the client terminates.

### Relaunch sequence

After editing a minigame (`.gd` scenes, scripts, or assets):

1. **Stop both processes**:
   ```
   hub stop name=debug-client
   hub stop name=debug-server
   ```
2. **Re-read** the changed files to verify they parse.
3. **Launch** again (same sequence as above).
4. Print `[debug-iteration] relaunched <minigame_id>`.

### Process lifecycle rules

- NEVER leave orphan processes. Always `stop` before relaunch or on abort.
- If the server crashes (hub reports exit), check `hub logs name=debug-server`
  for the error, fix, then relaunch.
- If the client window doesn't appear or the user reports a blank screen, check
  `hub logs name=debug-client`.
- The `debug-watcher` subagent handles automatic server cleanup when the client
  exits. The main agent does **not** need to manually stop the server after a
  client exit — the watcher handles it. The watcher is automatically killed when
  its parent task ends.

## Workflow commands

These are conventions the user and agent use to steer the session:

| Command | Meaning |
|---------|---------|
| `debug <minigame_id>` | Start debug-iteration for this minigame |
| `debug relaunch` | Kill + restart server + client after edits |
| `debug stop` | Kill both processes and end the session |
| `debug status` | Print which minigame, uptime, and recent logs |
| `debug logs` | Dump recent server + client output |
| `debug bots N` | Relaunch with N bots instead of 5 |
| `debug solo` | Relaunch with 0 bots (empty arena, just you) |
| `debug duration S` | Relaunch with round duration override (seconds) |

## Prompt engineering for the user

When waiting for feedback, the agent asks a concrete question, never "what do
you think?":

- "How was the round timer? Too fast/slow?"
- "Did the spawn positions feel fair?"
- "Were the controls responsive?"
- "Did the scoring make sense?"
- "Any visual glitches or missing feedback?"

After the user answers, the agent **edits the code immediately** (no planning
spiral) and relaunches. Small change? Edit then `debug relaunch`. Large change?
Break into sub-phases.

## Combined with /loop

If the user runs this inside `/loop start "debug-iterate"`, the skill follows
loop conventions: every turn is one edit or one launch, `LOOP_DONE` fires when
the user says "looks good", and `PROGRESS.md` tracks what changed each cycle.

## Auto-PR on done

When the user says "done" (or `/loop stop`):

1. **Commit** all changes on the `usertest-<minigame_id>` branch with a descriptive
   message summarising the changes made during the session.
2. **Push** the branch to `origin`:
   ```
   git push origin usertest-<minigame_id>
   ```
3. **Create a PR** using `gh pr create`:
   ```
   gh pr create --base main --head usertest-<minigame_id> \
     --title "debug-iteration: <minigame_id> changes" \
     --body "Iterative changes from a debug-iteration session on <minigame_id>."
   ```
4. Print the PR URL.

## Error handling

| Problem | Response |
|---------|----------|
| Server exits immediately | Check `hub logs debug-server`. Likely missing Godot binary or broken script. |
| Client hangs on connecting | Server may not be ready. Check `hub logs debug-server` for readiness. Verify port. |
| "unknown minigame id" | Wrong id. List registered ids from `MinigameCatalog`. |
| Match doesn't start | Server missing `--debug-rpcs`. Restart with the flag. |
| Mystery crash | `hub logs` on both, look for `error:` or `SCRIPT ERROR`. |
| Bots don't move | Check `src/core/bots/bot_brains.gd` for a brain registered for this id. |
