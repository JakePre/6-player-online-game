# Agent Coordination Protocol

Multiple agents (and humans) build this game concurrently and merge their own PRs. This document is the procedure that keeps parallel work conflict-free. It exists because the friction is real, not hypothetical:

- **Duplicate claim:** issue #6 claimed M3-01 fifteen minutes after issue #4 had claimed all of M3 (resolved by withdrawing #6).
- **Stacked-PR closure:** merging PR #5 with "delete branch" permanently closed the stacked PR #8, which could not be reopened and had to be recreated as #9.
- **Duplicate implementation:** two branches independently created a `PlayerPalette` class (`src/core/` vs `src/characters/`); one had to be dropped post-merge (`245bc48`).
- **Duplicate issue batches:** two agents filed the same six playtest notes eleven minutes apart (#256–#261 vs #262–#267); six issues had to be closed as dupes before someone built the same fix twice.
- **Red main:** #243 and #247 merged without the at-merge-time check while their tests disagreed with their own code; `main` was red for half an hour and a third agent had to stop feature work to fix it (#249).
- **Merge starvation:** during the M13 sprint one green PR needed seven rebase cycles because other agents merged every ~3 minutes without yielding (#277).
- **Invisible-branch duplicate:** two agents claimed M17-03 within minutes (#645 vs #646) and both built the full feature locally; neither branch was pushed until PR time, so the claim check showed nothing and one whole implementation (#648) was thrown away. Self-assigned claim issues + an immediately-pushed marker branch (§2) exist to close that window.
- **Zombie PR:** a PR closed as superseded (#152) was reopened and merged anyway, silently overriding the fix that had already landed.
- **Lost work:** two sessions ran out of budget with uncommitted work sitting in a working tree; it survived only because another agent went looking (#236, #145).
- **Tag race:** two agents cut releases minutes apart, producing a `v0.4.1` numbered *behind* the already-published `v0.5.0`; the bogus tag and release had to be deleted.

The rules below make each of those a checked step instead of a surprise. **Guarantee level:** following this procedure makes *textual* merge conflicts impossible for disjoint tasks and makes overlapping work visible before code is written. It cannot prevent two green PRs from disagreeing *semantically* — the targeted rebase for shared-file PRs (§5) plus CI on every merge is the net for that.

---

## 1. The three rules

1. **Claim before you code.** One task = one claim issue = one branch = one PR. If the claim check (§2) shows the task is taken, pick another task.
2. **Touch only what you own.** Each task owns a path set (§3). Shared "hotspot" files have specific edit rules (§4). Anything outside both requires a comment on your claim issue *before* you edit it.
3. **Merge when green; rebase only when it matters.** `main` no longer requires branches to be up to date (owner decision, 2026-07-06), so a PR with green checks lands via `gh pr merge --auto --merge` the moment CI passes — no rebase treadmill for disjoint work. The one exception: if your PR changed a *shared framework file* (a §4 hotspot, or behavior under `src/minigames/_api/`, `src/net/`, `src/ui/party_theme.gd`, `src/client/settings_store.gd`), rebase onto `origin/main` and re-run the gate before merging, so a semantic clash with a PR that landed under you is caught before merge, not after. CI-on-`main` is the backstop (§7).

## 2. Claiming a task

Run the claim check — all three, not just one:

```sh
gh issue list --state open --search "<task-id>"   # is a claim issue already open for THIS task?
gh issue list --state open --json number,title,assignees \
  --jq '.[] | "\(.number) \(.assignees[0].login // "UNASSIGNED") \(.title)"'  # who holds each claim
gh pr list --state open                            # in-flight work
git fetch origin && git branch -r | grep <task-id> # pushed + marker branches
```

A task is **taken** if any open issue, open PR, or remote branch references its ID. Two clarifications that have each burned an agent:

- **An open issue whose title carries the task ID is *itself* the claim** — it needs no "claiming" comment, and it counts even when its body reads like a plain spec (Planned approach / Prerequisites). That is exactly the trap: seeing a task-ID issue and reading it as an available backlog item rather than someone's lock. If it looks abandoned, use the stale-claim path below — never just start it.
- **Read the assignee.** A claim issue is self-assigned (below), so `gh issue list` shows its owner; an `UNASSIGNED` task-ID issue is unusual — treat it as taken anyway and ask in a comment before touching it.

Then:

1. **File the claim issue as your literal first action — before reading a single file.** The issue *is* the lock; the cost of a collision equals how long you run before detecting it, so the claim goes up before you invest any tokens in the work. Use the *Claim a plan task* template, titled with the task ID, and **self-assign it** so the lock is glanceable in `gh issue list` (no need to open every issue to see who holds it):
   ```sh
   gh issue create --title "<task-id> …" --body "…" --assignee @me
   # or, claiming on an existing task-ID issue:
   gh issue comment <n> --body "Claiming (<model>). …" && gh issue edit <n> --add-assignee @me
   ```
   In the **hotspot files** field, list every shared file (§4) you expect to touch — this is how other agents see collisions coming.
2. Branch from the fresh remote main, **then push it immediately — before writing any code** — so the lock shows up as a remote branch within seconds, not only when the PR opens. A branch that lives only on your machine during a 20-minute build is invisible to every other agent's `git branch -r`; that window is where the M17-03 duplicate was built (both agents claimed within minutes, neither could see the other's local branch). The empty marker commit closes it:
   ```sh
   git fetch origin && git checkout -b feat/<task-id>-<slug> origin/main
   git commit --allow-empty -m "claim: <task-id>" && git push -u origin HEAD
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
| M16-01 design system | `src/ui/party_theme.gd` (rebuild), `docs/STYLE_GUIDE.md` (create), fonts under `assets/` (+ `CREDITS.md` rows) — after it merges both become §4 hotspots |
| M16-02..13 per-surface beauty | the surface's existing owned paths (menu/settings → `src/client/`, lobby/select → `src/lobby/`, chrome/HUD/results → `src/match/`+`src/ui/`, finale → `src/finale/`) + additive-only reads of the theme; image needs go through `docs/IMAGE_REQUESTS.md` |

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
| `src/ui/party_theme.gd`, `docs/STYLE_GUIDE.md` (once M16-01 lands) | Additive only: new tokens/variations get added, existing ones never change meaning mid-milestone. A change that would restyle other surfaces goes through an issue on M16-01's claim, not a drive-by edit. |
| `docs/IMAGE_REQUESTS.md` | Append rows only, never edit/reorder another task's rows (same rule as `CREDITS.md`). Status flips (`requested`→`generated`→`landed`) touch only your own row. |
| `docs/MODEL_REQUESTS.md` | Same rules as `IMAGE_REQUESTS.md`: append-only rows, status flips touch only your own row. Agents never generate or download models themselves (#817). |

## 5. Branch, PR, and serialized merge procedure

### The git playbook — the exact lifecycle, command by command

This is how the coordinating agent actually drives git for every task. Follow it literally; every deviation below has caused a real incident.

**1. Start clean, start fresh — and push the branch immediately (§2).** Never commit on `main`, and never branch from a stale local `main`:

```sh
git checkout main && git pull
git checkout -b <type>/<short-slug> origin/main   # feat/, fix/, docs/, test/
git commit --allow-empty -m "claim: <task-id>" && git push -u origin HEAD   # make the lock visible now
```

Branching from `origin/main` (not local `main`) means you can't inherit a stale base even if your pull raced another agent's merge. Pushing the marker branch before you write code makes the claim visible to `git branch -r` for the whole build, not just at PR time — the single biggest fix for the invisible-branch duplicate class (§2, M17-03).

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

**6. PR against `main`, then merge when green.** `gh pr create` with the claim issue linked (`Closes #N`). Branch protection requires the three checks green **on the current head** — after a force-push the old run is void, wait for the new one. Then `gh pr merge --auto --merge --delete-branch`: with the up-to-date requirement off, a PR lands the instant its checks pass, so you rarely rebase. **Watch the post-merge CI run on `main`** — if your change and one that landed under you clash semantically, `main` goes red and fixing it is top priority (§7). `--delete-branch` sometimes doesn't fire (observed on #725) — after confirming the merge, `git push origin --delete <branch>` if it's still listed in `git branch -r`. This is also why #714's sweep existed: 70 already-merged branches had piled up this way.

**7. Tags are shared state — treat them like a merge.** Immediately before tagging: `git fetch --tags --force && gh release list`. Tag only a green `main`, one release in flight at a time. A mis-tag gets deleted (`gh release delete <tag> --cleanup-tag`) and re-cut correctly, announced on the issue (this is how the v0.4.1/v0.5.0 race was unwound).

**8. Things you never do:** commit to `main` directly; `git push --force` without `--with-lease`; resolve conflicts in the GitHub web editor (skips the local gate); `git stash` as a hand-off mechanism (stashes are invisible to every other agent — commit and push instead); leave a session with uncommitted or unpushed changes; retag a published version.

### Before opening a PR (and again before merging)

Always run the full local gate below before you push — that is non-negotiable regardless of freshness. The rebase itself is now **conditional**: `main` does not require your branch to be current, so you only need to rebase-before-merge when your PR changed a *shared framework file* (§4 hotspots, or behavior under `src/minigames/_api/`, `src/net/`, `src/ui/party_theme.gd`, `src/client/settings_store.gd`) — that is where two independently-green PRs can break `main` together. Disjoint per-game/per-surface work can merge stale.

```sh
git fetch origin main
git merge-base --is-ancestor origin/main HEAD && echo up-to-date || echo BEHIND-MAIN
```

If `BEHIND-MAIN` **and** you touched a shared file: `git rebase origin/main`, re-run the local gate, force-push your feature branch:

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

`main` does not require branches to be up to date (owner decision, 2026-07-06), so serialization is **optimistic, not enforced**: PRs merge when green, and the post-merge CI run on `main` is the net that catches any bad combination. GitHub's merge queue is not used — it is organization-only and this repo is user-owned.

1. CI green **on the current head of the PR** — after any force-push the old run is void; wait for the new one. An earlier green run on a stale base does not count, ever.
2. `gh pr merge --auto --merge --delete-branch`. With the up-to-date requirement off, this lands the PR the instant its checks pass (or immediately, if they already are). No manual rebase for disjoint work.
3. **Rebase-before-merge is a targeted step, not a default.** Do it when your PR changed a *shared framework file* (`src/minigames/_api/`, `src/net/`, `src/ui/party_theme.gd`, `src/client/settings_store.gd`, or another §4 hotspot's behavior) — that is where two independently-green PRs can break `main` together. Rebase onto `origin/main`, re-run the full local gate, force-push, wait for green, then merge. Disjoint per-game/per-surface work skips this.
4. **Watch the post-merge run on `main`.** If it goes red — a semantic clash the individual PRs couldn't see — fixing it outranks all task work (§7): fix forward or revert your merge. Never leave a session with your merge's `main` run unwatched.
5. **Textual conflicts still block the merge.** Git refuses a conflicting merge regardless; the later PR owns the rebase + resolution (below).

### Merge etiquette

With the up-to-date requirement off, the old "yield to the oldest PR" and rebase-cycle starvation problems are gone — a merge no longer staleness-bombs every other open PR.

- **Merge and move on** — but glance at the post-merge `main` run (step 4) before you call it done; that is the only babysitting left.
- **Batch your own small PRs.** Prefer one PR with several commits over three separate ones landing minutes apart.
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

Current state (owner-configured 2026-07-06):

- **Up-to-date requirement is OFF** on `main`: PRs merge when their checks are green without being forced current with `main`, which kills the rebase treadmill. GitHub's **merge queue is not used** — it is organization-only and this repo is user-owned, so the setting does not exist here. The trade is a small semantic-clash risk between two independently-green PRs, caught by CI-on-`main` (§7) and the targeted rebase for shared-file PRs (§5).
- Branch protection on `main` (keep as-is): the three required status checks (GDScript lint, Unit tests (GUT), Multiplayer soak), a PR required before merging, no force-push, no deletion, admin enforcement on. "Allow auto-merge" stays on so `--auto` lands green PRs without babysitting.
- If optimistic merging ever gets noisy (repeated red `main` from semantic clashes), the one-toggle rollback is to re-check "Require branches to be up to date before merging" — back to serialized-but-churny.
