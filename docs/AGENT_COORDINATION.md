# Agent Coordination Protocol

Multiple agents (and humans) build this game concurrently and merge their own PRs. This document is the procedure that keeps parallel work conflict-free. It exists because the friction is real, not hypothetical:

- **Duplicate claim:** issue #6 claimed M3-01 fifteen minutes after issue #4 had claimed all of M3 (resolved by withdrawing #6).
- **Stacked-PR closure:** merging PR #5 with "delete branch" permanently closed the stacked PR #8, which could not be reopened and had to be recreated as #9.
- **Duplicate implementation:** two branches independently created a `PlayerPalette` class (`src/core/` vs `src/characters/`); one had to be dropped post-merge (`245bc48`).
- **Duplicate issue batches:** two agents filed the same six playtest notes eleven minutes apart (#256–#261 vs #262–#267); six issues had to be closed as dupes before someone built the same fix twice.
- **Red main:** #243 and #247 merged without the at-merge-time check while their tests disagreed with their own code; `main` was red for half an hour and a third agent had to stop feature work to fix it (#249).
- **Merge starvation:** during the M13 sprint one green PR needed seven rebase cycles because other agents merged every ~3 minutes without yielding (#277).
- **Zombie PR:** a PR closed as superseded (#152) was reopened and merged anyway, silently overriding the fix that had already landed.
- **Lost work:** two sessions ran out of budget with uncommitted work sitting in a working tree; it survived only because another agent went looking (#236, #145).
- **Tag race:** two agents cut releases minutes apart, producing a `v0.4.1` numbered *behind* the already-published `v0.5.0`; the bogus tag and release had to be deleted.

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

1. **File the claim issue as your literal first action — before reading a single file.** The issue *is* the lock; the cost of a collision equals how long you run before detecting it, so the claim goes up before you invest any tokens in the work. Use the *Claim a plan task* template, titled with the task ID. In the **hotspot files** field, list every shared file (§4) you expect to touch — this is how other agents see collisions coming.
2. Branch **from the fresh remote main**, never from a stale local main or another feature branch:
   ```sh
   git fetch origin && git checkout -b feat/<task-id>-<slug> origin/main
   ```
3. If two claims race anyway, **the earliest-created issue wins** — and the same tiebreak applies to a racing branch or PR with no issue yet (lowest issue/PR number, else earliest push). The later claimant closes theirs with a comment and picks other work (precedent: #6 withdrew in favor of #4). A lost race costs one cheap withdrawal — that's the whole point of claiming before coding.

Additional claim rules:

- **Re-run the full three-way check (incl. `git branch -r`) right before bulk effort — not just at claim time.** For any task touching more than ~3 files or running more than ~15 minutes, the landscape moves under you (a PR merges roughly every ~5 min at fleet speed). Checking only at the start-of-work and at commit-time means you can pay for an entire multi-file sweep before spotting a duplicate that landed at minute 1. The M12-02 `play_sfx` sweep was lost exactly this way: 21 files implemented, then found already-merged at commit. One `git branch -r | grep <task>` before diving in would have caught it in 2 seconds. If a duplicate *has* landed, salvage only the genuinely additive delta (e.g. a new signal/test the merged work skipped) as a fresh claim; discard the rest.
- **Cross-cutting sweeps are a single claim, filed up front, covering every path.** A "touch all N views/sims" task (an sfx sweep, an FX pass, a scaling sweep) is the highest-collision work there is — every agent independently reasons their way to the same obvious pick. Never "just start and others will see"; the claim must name the whole territory (all paths) the moment you begin, so the second agent sees it taken immediately rather than colliding halfway through.
- **Claim only what you are starting now.** Milestone-wide claims (like #4) lock a whole area for everyone else; prefer per-task claims unless the tasks are genuinely inseparable. (Cross-cutting sweeps above are the deliberate exception — there the whole-territory claim *is* the per-task claim.)
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
| M8-01/02 iso-arena framework + assets | `src/minigames/_api/`, additive-only in `src/characters/`, `assets/` (+ `assets/CREDITS.md` rows) |
| M8-03..11 each minigame's view migration | `src/minigames/<minigame_id>/` **only**, same rule as M4-xx |
| M8-12 finale view | `src/finale/` |
| M8-13 lobby character-select wiring | `src/lobby/` |
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

### The git playbook — the exact lifecycle, command by command

This is how the coordinating agent actually drives git for every task. Follow it literally; every deviation below has caused a real incident.

**1. Start clean, start fresh.** Never commit on `main`, and never branch from a stale local `main`:

```sh
git checkout main && git pull
git checkout -b <type>/<short-slug> origin/main   # feat/, fix/, docs/, test/
```

Branching from `origin/main` (not local `main`) means you can't inherit a stale base even if your pull raced another agent's merge.

**2. Check the world before and during work.** `git fetch origin main` costs nothing; run it before claiming, before coding, and any time you've been heads-down for more than ~20 minutes. Also skim `gh pr list` and the claim issues — code that duplicates an in-flight PR is wasted budget.

**3. Commit early, commit whole.** One task = one branch, but commit at every self-contained checkpoint. Message format:

```
<type>: <what changed and why, present tense>

<body if the why needs room>

Closes #<claim-issue>
Co-Authored-By: <your agent identity>
```

**Never chain freshness checks into your commit:** `git merge-base --is-ancestor origin/main HEAD && git add ... && git commit ...` silently commits *nothing* when main has moved — this ate two agents' work (M7-04, M11-03). Commit **first**, then check freshness, then rebase. A committed change survives a botched rebase (`git reflog`); an uncommitted one doesn't survive anything.

**4. Rebase, never merge-from-main.** When behind: `git rebase origin/main`, resolve, re-run the **full local gate** (format, lint, `--check-only` on changed scripts, `--headless --import`, GUT), then `git push --force-with-lease`. Plain `--force` can vaporize a hand-off commit someone pushed to your branch; `--force-with-lease` refuses instead. After any branch switch or rebase, re-run `godot --headless --import` — a stale `.godot` class cache produces mass phantom test failures that look like your bug but aren't.

**5. Push is your save button.** Push after every commit, not at the end. An unpushed branch dies with your session (two dead agents' work had to be forensically reconstructed). If your budget is running low, pushing takes priority over finishing — see §9.

**6. PR against `main`, then babysit it.** `gh pr create` with the claim issue linked (`Closes #N`). Branch protection requires the three checks green **on the current head** — after a force-push the old run is void, wait for the new one. Merge with a merge commit, delete the branch (stacked-PR exception below), and **watch the post-merge run on `main` finish before starting anything else**.

**7. Tags are shared state — treat them like a merge.** Immediately before tagging: `git fetch --tags --force && gh release list`. Tag only a green `main`, one release in flight at a time. A mis-tag gets deleted (`gh release delete <tag> --cleanup-tag`) and re-cut correctly, announced on the issue (this is how the v0.4.1/v0.5.0 race was unwound).

**8. Things you never do:** commit to `main` directly; `git push --force` without `--with-lease`; resolve conflicts in the GitHub web editor (skips the local gate); `git stash` as a hand-off mechanism (stashes are invisible to every other agent — commit and push instead); leave a session with uncommitted or unpushed changes; retag a published version.

### Before opening a PR (and again before merging)

```sh
git fetch origin main
git merge-base --is-ancestor origin/main HEAD && echo up-to-date || echo REBASE-NEEDED
```

If `REBASE-NEEDED`: `git rebase origin/main`, re-run the local gate, force-push your feature branch:

```sh
gdformat --check src tests && gdlint src tests
git diff --name-only origin/main...HEAD -- '*.gd' | while read -r f; do
  godot --headless --check-only --script "$f"
done
godot --headless --import
godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit -ginclude_subdirs -gexit
```

**Why the `--check-only` step:** CI's Linux Godot rejects some Variant-inference patterns
(`var x := some_dict.member`) as a hard parse error that local `--headless --import` and GUT
silently tolerate — the script just gets skipped ("failed to parse"), so it passes locally and
fails CI, costing a full rebase cycle. `godot --headless --check-only --script <file>`
reproduces the same parse pass CI uses. Run it per changed `.gd` file (the whole repo is slower
and unnecessary). **Known false positive:** a file that references a project autoload (e.g.
`NetManager`, `MinigameCatalog`) fails with `Identifier not found: <Autoload>` even with
`--path` set, because a standalone script check never registers `project.godot`'s autoloads.
That specific error is safe to ignore; anything else is a real parse error worth fixing before
you push.

### Merging

1. CI green **on the current head of the PR** — after any force-push the old run is void; wait for the new one. An earlier green run on a stale base does not count, ever.
2. The up-to-date check above passes **at merge time**, re-run in the same breath as the merge command. This is the serialization: after anyone merges, every other open PR goes stale and must rebase + re-verify before it may merge. **Merging a stale or unchecked PR is how `main` went red on 2026-07-03 (#243/#247) — there are no exceptions.**
3. Merge with a **merge commit** (repo convention), then delete the branch — **unless a stacked PR is based on it** (see below).
4. Watch the post-merge CI run on `main` **before starting your next task**. If it goes red, fixing it immediately outranks all task work (plan rule: `main` is always green). Fix forward or revert your merge; either way, announce on your claim issue. Never end a session with your merge's CI still running.

### Merge etiquette (anti-starvation)

The serialization rule means every merge staleness-bombs every other open PR. When multiple agents are landing work:

- **Yield to the oldest green PR.** Before merging, run `gh pr list` — if another PR is green and has been waiting longer than yours, let it merge first and rebase yours after. A PR that has been rebase-cycled 3+ times has absolute priority; everyone else pauses merging until it lands.
- **Batch your own small PRs.** If you are about to land several S-sized changes in a row, prefer one PR with several commits over a merge every three minutes.
- **Never reopen a PR that was closed as superseded or duplicate.** The closure comment says where the fix went; if you disagree, argue on the *issue* — reopening and merging (#152) silently overrides work that already landed.

### Stacked PRs (discouraged)

Base a PR on another feature branch only when the dependency is unavoidable, and say so at the top of the PR body. **Never use "delete branch" when merging the parent** — GitHub *permanently closes* (not retargets) any PR whose base branch is deleted; it cannot be reopened (this killed PR #8). Merge the parent keeping the branch, retarget the child to `main` (`gh pr edit <n> --base main`), then delete the parent branch.

### Recovering from a conflict anyway

The **later-to-merge PR owns the resolution**: rebase, resolve, re-run the full local gate, wait for green, merge. Never resolve conflicts in the GitHub web editor (it skips the local gate).

## 6. Filing issues without duplicating them

Claims aren't the only race — *filing* races too (#256–#261 vs #262–#267 were the same six playtest notes, twice).

- **Search before filing:** `gh issue list --state open --search "<key words>"` and skim the most recent ~20 open issues. If your finding exists, comment there instead of filing.
- **Playtest waves are one batch.** If the owner hands over a set of notes, ONE agent files the whole wave, numbered in one pass; others wait for the batch and claim from it. If you find a batch already filed within the last hour, assume your notes are the same wave.
- **Dupes resolve like claims:** earliest filing wins; the later filer closes theirs with a pointer. Any agent may close obvious dupes on sight with a linking comment.

## 7. When `main` is red

- Fixing `main` **outranks all task work, for every agent**. If you notice red main, say so on the offending PR, then either fix forward or revert — whichever is faster to green.
- Diagnose before reverting: the 2026-07-03 incident was tests asserting a design the shipped code had (correctly) moved past — the fix was aligning the tests, not reverting the feature.
- While main is red: **no one merges anything else.** Feature PRs queue behind the fix.

## 8. Releases and tags

- **A release requires an explicit owner prompt asking for one — every time.** No agent tags, pushes a release, or bumps the version number on its own initiative, and "standing approval" does **not** cover releases: each release is its own fresh ask. Finishing a milestone, clearing the RELEASE_CHECKLIST, or reaching a boundary does *not* authorize cutting a release — it just means one is *ready* if the owner asks. Task work never includes a version bump unless the task the owner named is itself the release. This exists to stop the version number climbing on its own: the fleet ships fast, and without this rule every "milestone done" moment becomes an unprompted tag.
- **Immediately before tagging:** `git fetch --tags && gh release list --limit 3`. Someone may have released while you worked (the v0.4.1/v0.5.0 race). Pick the next number *after whatever is truly latest*.
- Tag only from a **green** `main` tip you have just pulled. Never tag mid-red, never tag a stale local main.
- One release at a time: if the release workflow is running, wait for it before pushing another tag.
- A mis-numbered tag/release gets deleted (`gh release delete --cleanup-tag`), not left as history clutter.
- Releases are owner-facing: cut them **only on an explicit owner request** (see the first bullet — standing approval never covers a release), and update the release-notes template if reality diverged from it.
- **M14 release boundary — v0.6.0 shipped, hold lifted (2026-07-05):** the RELEASE HOLD at the M14 boundary is **lifted**. [v0.6.0](https://github.com/JakePre/6-player-online-game/releases/tag/v0.6.0) was cut from the feature-complete base game; M14 "Genre Hop" is now open under the normal coordination rules. (Kept as a marker of where the base-game release line fell.)

## 9. Running out of budget (hand-off protocol)

Sessions die mid-task. Twice now, half-finished work survived only because someone went looking through local clones. Make rescue trivial:

- **Commit early, push always.** The moment a unit of work compiles, commit and push the branch — even rough. An unpushed branch on a dead machine may as well not exist.
- When you sense the end (long session, deep context): push whatever exists and leave a **hand-off comment on your claim issue**: what's done, what's left, any landmines (e.g. "the version const is temporarily 0.2.0 for local update testing — revert before shipping").
- **Never leave a debug edit uncommitted and unmentioned.** The stray version-downgrade from the #144 session would have shipped a broken release if the rescuer hadn't caught it.
- Rescuing agents: finish the work under the original claim, credit the prior session in the commit message, and revert anything that smells like a local test hack — loudly, in the PR body.

## 10. Owner decisions are load-bearing

- Design-tier changes (reworks, new mechanics, tier moves) get a **proposal comment on the issue and owner approval before code** — the #174/#175 pattern. Bug fixes and UX polish don't need this.
- Check the policy docs before "improving" something: PHASE2.md §7 lists games that are *intentionally 2D* — one agent already "fixed" one into 3D and it had to be reverted. If a design smells deliberate, it probably is; ask on the issue.
- Owner playtest notes always name the symptom, not the cause. Diagnose before building — two of the wave-6 fixes (#258, #260) would have been wrong if built as literally described.

## 11. Local environment gotchas (read once, save hours)

- **Test with Godot 4.4.1** (CI's pin). Newer editors produce spurious view-test failures.
- **Reimport before testing after switching branches** (`godot --headless --import`): a stale class cache produces cascades of "Identifier not declared" errors that look like real breakage. If dozens of tests fail at once after a pull, it's almost certainly this, not the code.
- **Never commit `.import` churn** outside asset-import PRs — `git checkout -- "*.import"` before staging.
- GUT + lint disagree on long lambda lines; restructure rather than fight the formatter.
- **Run `godot --headless --check-only --script <file>` on changed scripts before pushing** (§5): local `--import`/GUT tolerate some Variant-inference patterns CI's parser rejects outright, so a script can pass locally and fail CI, costing a rebase cycle. Ignore `Identifier not found: <Autoload>` from this check — that's the tool not registering `project.godot`'s autoloads, not a real error.

## 12. Recommended repo settings (owner action)

These make §5's discipline machine-enforced instead of voluntary — recommended for @JakePre (requires admin):

- Branch protection on `main`: require status checks to pass **and require branches to be up to date before merging** (this is exactly §5 step 2, enforced by GitHub).
- Optionally enable auto-merge so agents can queue green PRs instead of racing.
