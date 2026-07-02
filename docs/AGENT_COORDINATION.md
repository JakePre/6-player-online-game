# Agent Coordination Protocol

Multiple agents (and humans) build this game concurrently and merge their own PRs. This document is the procedure that keeps parallel work conflict-free. It exists because the friction is real, not hypothetical:

- **Duplicate claim:** issue #6 claimed M3-01 fifteen minutes after issue #4 had claimed all of M3 (resolved by withdrawing #6).
- **Stacked-PR closure:** merging PR #5 with "delete branch" permanently closed the stacked PR #8, which could not be reopened and had to be recreated as #9.
- **Duplicate implementation:** two branches independently created a `PlayerPalette` class (`src/core/` vs `src/characters/`); one had to be dropped post-merge (`245bc48`).

The rules below make each of those a checked step instead of a surprise. **Guarantee level:** following this procedure makes *textual* merge conflicts impossible for disjoint tasks and makes overlapping work visible before code is written. It cannot prevent two green PRs from disagreeing *semantically* — the serialized merge procedure (§5) plus CI on every merge is the net for that.

---

## 1. The three rules

1. **Claim before you code.** One task = one claim issue = one branch = one PR. If the claim check (§2) shows the task is taken, pick another task.
2. **Touch only what you own.** Each task owns a path set (§3). Shared "hotspot" files have specific edit rules (§4). Anything outside both requires a comment on your claim issue *before* you edit it.
3. **Merge serially, never stale.** A PR merges only when its branch already contains the current `origin/main` tip (§5). After any merge lands, every other open PR rebases before it can merge.

## 2. Claiming a task

Run the claim check — all three, not just one:

```sh
gh issue list --state open          # open claims
gh pr list --state open             # in-flight work
git fetch origin && git branch -r   # pushed branches without a PR yet
```

A task is **taken** if any open issue, open PR, or remote branch references its ID. Then:

1. Open an issue with the *Claim a plan task* template, titled with the task ID. In the **hotspot files** field, list every shared file (§4) you expect to touch — this is how other agents see collisions coming.
2. Branch **from the fresh remote main**, never from a stale local main or another feature branch:
   ```sh
   git fetch origin && git checkout -b feat/<task-id>-<slug> origin/main
   ```
3. If two claims race anyway, **the earliest-created issue wins**; the later claimant closes theirs with a comment and picks other work (precedent: #6 withdrew in favor of #4).

Additional claim rules:

- **Claim only what you are starting now.** Milestone-wide claims (like #4) lock a whole area for everyone else; prefer per-task claims unless the tasks are genuinely inseparable.
- **Stale claims:** an open claim with no branch pushed and no activity for 24 h may be queried with a comment; if another 24 h passes silently, it may be taken over (say so in the issue).
- **Docs/infra work** without a plan task ID still gets a claim issue, titled `[DOCS]`/`[INFRA]`.

## 3. Path ownership

A task's PR may create/edit files only in the areas the plan's repo layout (IMPLEMENTATION_PLAN.md §3) assigns to its feature, plus its checkbox line and the hotspot files it declared. Current map:

| Task area | Owned paths |
|---|---|
| M2-03 character select | `src/lobby/` (select UI), `src/characters/` roster resources |
| M2-05 settings | `src/client/` (settings screen + wiring) |
| M3-04/05/07 chrome, interstitials, emotes | `src/match/`, `src/ui/` |
| M4-xx each minigame | `src/minigames/<minigame_id>/` **only**, + one `register(...)` line in `MinigameCatalog.register_builtins()`, + one row appended to `assets/CREDITS.md` if assets are added |
| M5 finale | `src/finale/` |
| M6 polish | declared per-PR in the claim issue (this milestone inherently crosses areas — extra care) |
| M7 deploy/release | `server/deploy/`, `.github/workflows/` (coordinate — see §4) |

**Before creating any new shared-sounding class** (palette, helpers, math utils, constants): search first — `grep -ri <concept> src/` — and check the open PRs' claims. The duplicate-`PlayerPalette` incident is what this line prevents. If the thing your task needs feels reusable, it probably belongs to an existing owned area (e.g. identity/colors → `src/characters/`, protocol constants → `NetConfig`).

## 4. Hotspot files — shared by design, edited by rule

| File | Rule |
|---|---|
| `docs/IMPLEMENTATION_PLAN.md` | Edit **only your own task's checkbox line**, in the same PR as the task. Never reflow or renumber anything else. |
| `src/net/net_config.gd` `PROTOCOL_VERSION` | Bump by exactly +1 **only** if your PR changes the RPC surface. If a rebase reveals someone else bumped it too, keep the highest value and bump once more only if your change is still additional. |
| `src/net/net_manager.gd` | Additive only: new request wrappers and `_rpc_*` handlers go under the existing section banners; never reorder or rename existing members. Declare it in your claim issue. |
| `src/minigames/_api/minigame_catalog.gd` | M4 PRs add exactly one `register(...)` line in `register_builtins()`; nothing else. |
| `project.godot` | Autoload/input-map additions are additive and must be declared in the claim issue. |
| `assets/CREDITS.md` | Append rows to the bottom of the table. Adjacent-append conflicts are trivial — resolve by keeping both rows. |
| `export_presets.cfg`, `.github/workflows/ci.yml` | Do not edit under a feature task. Open/comment an `[INFRA]` issue and coordinate explicitly. |
| `docs/SPEC.md` | Locked (§2 decisions). Deviations are flagged in PR descriptions, not edited in. |

## 5. Branch, PR, and serialized merge procedure

### Before opening a PR (and again before merging)

```sh
git fetch origin main
git merge-base --is-ancestor origin/main HEAD && echo up-to-date || echo REBASE-NEEDED
```

If `REBASE-NEEDED`: `git rebase origin/main`, re-run the local gate, force-push your feature branch:

```sh
gdformat --check src tests && gdlint src tests
godot --headless --import
godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit -ginclude_subdirs -gexit
```

### Merging

1. CI green on the PR head.
2. The up-to-date check above passes **at merge time** — an earlier green run on a stale base does not count. This is the serialization: after anyone merges, every other open PR goes stale and must rebase + re-verify before it may merge.
3. Merge with a **merge commit** (repo convention), then delete the branch — **unless a stacked PR is based on it** (see below).
4. Watch the post-merge CI run on `main`. If it goes red, fixing it immediately outranks all task work (plan rule: `main` is always green). Fix forward or revert your merge; either way, announce on your claim issue.

### Stacked PRs (discouraged)

Base a PR on another feature branch only when the dependency is unavoidable, and say so at the top of the PR body. **Never use "delete branch" when merging the parent** — GitHub *permanently closes* (not retargets) any PR whose base branch is deleted; it cannot be reopened (this killed PR #8). Merge the parent keeping the branch, retarget the child to `main` (`gh pr edit <n> --base main`), then delete the parent branch.

### Recovering from a conflict anyway

The **later-to-merge PR owns the resolution**: rebase, resolve, re-run the full local gate, wait for green, merge. Never resolve conflicts in the GitHub web editor (it skips the local gate).

## 6. Recommended repo settings (owner action)

These make §5's discipline machine-enforced instead of voluntary — recommended for @JakePre (requires admin):

- Branch protection on `main`: require status checks to pass **and require branches to be up to date before merging** (this is exactly §5 step 2, enforced by GitHub).
- Optionally enable auto-merge so agents can queue green PRs instead of racing.
