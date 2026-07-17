# Controller Checklist — M17-06 closing verification sweep

Owner-run, gamepad-only play session covering menu → lobby → a representative
slice of minigames → the finale → podium. Replaces the original M17-06 plan
("gamepad-only end-to-end pass across every game") — no agent can press
physical buttons, so this is a ~30-45 minute human pass instead. Findings
become individually-claimable fix issues (Sonnet/Opus on sight, tag
`gamepad`); the M17-06 checkbox in `docs/IMPLEMENTATION_PLAN.md` closes when a
run of this checklist comes back clean.

**What you need:** one Xbox-layout pad, one PlayStation-layout pad, and one
generic/SDL-DB-mapped pad you don't already have a layout for (a cheap
third-party or older pad is fine — the point is exercising `gamecontrollerdb.txt`
fallback, not name-brand hardware). Run the full checklist once per pad, or at
minimum once fully on Xbox/PS and a lighter spot-check on the generic pad
(menu nav + one game + the rebind check).

Keyboard/mouse stays untouched the whole session — every check below is pad
only. If your hand reaches for the keyboard or mouse to get unstuck, that's a
finding.

## Before you start

- [ ] Pad is connected *before* launching the game (cold-plug). Confirm
  `InputGlyphs` picks the right button prints (Xbox pad shows Ⓐ Ⓑ Ⓧ Ⓨ,
  PlayStation shows ✕ ● ■ ▲) on the first hint you see in the main menu.
- [ ] Note the pad's reported name if anything looks wrong (Settings →
  Diagnostics can help you find it, or just note "unknown/generic" — helpful
  for filing an unmapped-GUID issue).

## Menu / chrome navigation (M17-04)

Every screen below should have a visible focus ring on launch (no click
required to "wake up" focus), and `ui_cancel` (pad B / ✕... whichever your
layout maps to "back") should back out one level, never skip levels or dead-end.

- [ ] **Main menu**: stick/d-pad moves between buttons, action_primary
  activates, no focus trap (can reach every button, including Stats and
  Credits, without keyboard).
- [ ] **Lobby**: navigate the ready toggle, the character color swatches
  (#581 — confirm a color can be picked and shows the "picked" state), and
  the Round/Series format dropdowns and mutator toggles, all on the pad.
  Confirm focus doesn't get stuck inside a dropdown once a value is picked.
- [ ] **Settings**: the section bar (Gameplay / Video / Audio / Controls /
  Network / Diagnostics) is reachable and switching sections doesn't lose
  focus into a section that's now hidden. Every slider/toggle in each
  section is operable on the pad (sliders in particular — confirm left/right
  or stick nudges the value, not just click-drag).
- [ ] **Pause overlay** (Start button mid-match): opens, resume/settings/leave
  are all reachable, closing it returns focus to the match without a dead
  client-side input frame.
- [ ] **Results / standings / podium**: no interactive focus needed here, but
  confirm `ui_cancel`/continue prompts (if any) respond to the pad and the
  screen doesn't silently wait on a keyboard press to advance.
- [ ] **Credits / Stats screens**: reachable from the main menu and back
  again, entirely on the pad.

**Watch for (common focus-trap symptoms):** a screen that loads with *no*
node focused (first stick/d-pad press does nothing until you click once with
a mouse); a dropdown or slider that "eats" further stick input after one
adjustment; a modal (pause, confirm-leave) that doesn't grab focus on open so
`ui_cancel` closes the screen *behind* it instead.

## Representative games (10, covering every input archetype)

Not all ~45 games — this set is chosen so every *kind* of input surface used
anywhere in the catalog gets exercised at least once. If one of these plays
clean, other games using the same archetype are low-risk; if one fails, check
its sibling games in the same row for the same bug.

| Game | Archetype | What to confirm |
|---|---|---|
| `coin_scramble` | Baseline stick move | Left stick moves smoothly in all 8 directions, no dead zone dead spots |
| `quick_draw` | Reaction press only (no stick) | action_primary registers instantly on the DRAW flash — no missed presses |
| `target_range` | Aim (stick) + fire (button) | Right-stick-free aim works via left stick/WASD-equivalent axis; fire button lands shots |
| `shred_session` | 4-way lane press (rhythm) | ◀ ▶ ▲ / action_primary each hit their own lane reliably under time pressure |
| `count_quick` | Walk-onto-pad selection | Locking in by standing on a pad works the same as walking anywhere else |
| `turbo_lap` | Richest combo: steer+gas+drift+item | Steer on stick x, gas held on action_primary (#1067), brake on stick down, hard turn drifts, item (action_secondary) — all together under load |
| `tumble_run` | Side-scroll (SideScrollSim) | A/D-equivalent run + jump on stick + button, jump timing feels responsive |
| `wall_builders` or `cart_push` | Team-mode move + interact | Move + shove/interact button both work while on a team |
| `the_mole` or `pickpocket_plaza` | Hidden-role (move + button + private info) | Role-specific action (saboteur cut / guard arrest) fires correctly; private-role UI doesn't require keyboard to read |
| `putt_panic` | Charge-and-release | Holding action_primary charges, releasing putts — release timing feels accurate, not input-lagged |

For each: confirm the `control_hints` shown in the pre-round card matches
what the pad layout actually shows (Xbox vs PlayStation glyphs), and that
nothing in the round needs the keyboard or mouse to complete.

## Finale (Gauntlet)

- [ ] Buy-in shop: navigate item rows and the Confirm button entirely on the
  pad; confirm the "N/M locked in" readout updates and a maxed-out item's Buy
  button visibly disables (not just silently ignores presses).
- [ ] Sabotage / grudge targeting: firing a grudge/sabotage token at the
  nearest living rival works on the pad's action buttons; as an eliminated
  spectator, confirm you can still aim + strike a grudge (per #462/#476).
- [ ] Podium: reachable and readable without keyboard input.

## Hot-plug check (pick one)

- [ ] Disconnect the pad mid-menu, confirm a toast/notice appears (M6-03),
  reconnect, confirm control resumes without a restart.
- [ ] *(Alternative if you only have one test window)* Connect a *second* pad
  mid-match and confirm `joy_connection_changed` doesn't steal the first
  player's input or crash the input-glyph device detection.

## Rebind check (pick one)

- [ ] Settings → Controls: rebind one action (e.g. `action_secondary`) to a
  different pad button, back out, start a match, confirm the new binding is
  live and the old one no longer fires.
- [ ] Confirm the rebind persisted after a full app restart.

## Findings

Log anything that broke here before filing, then convert this table into
GitHub issues (or comment directly on #713 if this checklist run itself
surfaced something new) — one issue per distinct symptom, tagged for
Sonnet/Opus fix-on-sight per `docs/AGENT_COORDINATION.md` §2.

| Symptom | Where (screen/game) | Pad(s) affected | Filed as |
|---|---|---|---|
| | | | |

**Where symptoms usually belong:**
- Menu/chrome focus traps or `ui_cancel` misbehavior → new issue tagged
  `M17-04 follow-up`.
- A specific game's control feel/response → new issue against that game
  (existing per-game issue if one's open, otherwise a fresh one referencing
  M17-02's audit precedent).
- Rebind not persisting or not taking effect → check against M17-03's PR
  first; if it's a genuine regression, file against `settings_store.gd` /
  `settings_menu.gd`.
- Unmapped/misdetected pad (wrong button glyphs, no response at all) → file
  with the pad's reported name (from Diagnostics or OS controller panel) so
  the `gamecontrollerdb.txt` refresh (M17-01's documented cadence) can add it.

## Closing the loop

Once a full run (Xbox + PS + one generic pad, or Xbox + PS full plus a
lighter generic spot-check) comes back with the Findings table empty — or
every finding filed and either fixed or explicitly deferred — check the
M17-06 box in `docs/IMPLEMENTATION_PLAN.md` and note the run date + pads used
in the commit.
