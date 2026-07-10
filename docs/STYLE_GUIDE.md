# Party Rush Style Guide (M16-01)

The visual contract for every M16 surface task. All tokens live in
`src/ui/party_theme.gd` (`PartyTheme`), applied once at the app-shell root —
**never hardcode a color, size, duration, or radius that has a token here.**
Hotspot rule (AGENT_COORDINATION §4): the theme and this guide are
additive-only — add tokens/variations, never change existing meanings.

## Voice

Chunky, warm, confident — a couch party game, not a dashboard. Depth comes
from soft shadows on dark blue-slate, energy from the coin-gold accent, and
personality from the display font. If a surface looks like default Godot or
like an enterprise app, it's wrong.

## Typography

| Use | How | Font / size |
|---|---|---|
| Hero moments (title screen, "WINNER!") | `theme_type_variation = "DisplayLabel"` | Lilita One 44 |
| Screen titles | `"TitleLabel"` | Lilita One 30 |
| Section headers | `"HeaderLabel"` | Lilita One 22 |
| Body text | plain `Label` (theme default) | Nunito 500 · 16 |
| Control hints / key-caps | `"HintLabel"` | Nunito 600 · 16, accent |
| Secondary/meta text | `"DimLabel"` | Nunito 500 · 16, dim |
| Fine print, captions | `"SmallLabel"` | Nunito 500 · 13, dim |

Buttons get Lilita One 18 automatically — don't override it. **Do not** put
long body copy in the display font; it's a headline face.

## Palette

| Token | Role |
|---|---|
| `BG_DARKER` | Screen backgrounds, input wells, pressed states |
| `BG_DARK` | Standard panels |
| `BG_RAISED` | Elevated cards, hover rows, buttons |
| `BORDER` | Default 2px borders |
| `ACCENT` (coin-gold) | The identity color: focus, selection, fills, hints |
| `ACCENT_BRIGHT` / `ACCENT_DIM` | Hover text glow / pressed & muted gold |
| `SUCCESS` / `DANGER` / `INFO` | Semantic only — wins, errors/kicks, neutral notices |
| `TEXT` / `TEXT_DIM` | Primary / secondary text |

Player identity colors stay `PlayerPalette` — never recolor those. Semantic
colors are for meaning, not decoration: a red button is a destructive action.

## Space & shape

Spacing comes off the scale — `SPACE_XS 4 · SM 8 · MD 16 · LG 24 · XL 40` —
for all margins, padding, and separations (`add_theme_constant_override` on
containers). Radii: `RADIUS_SM 6` (small chips), `RADIUS_MD 10` (buttons,
inputs — the default), `RADIUS_LG 16` (big panels/cards).

Depth: `PanelContainer` is a shadowed panel; the `"CardPanel"` variation is
the raised treatment for list rows and result cards. Plain `Panel` is flat —
use it for full-screen backdrops, not floating elements.

## Motion

All animation uses the shared tempo — `DUR_FAST 0.12` (hover, presses),
`DUR_MED 0.22` (panels sliding, toasts), `DUR_SLOW 0.4` (screen transitions,
celebrations) — with `TRANS_DEFAULT`+`EASE_DEFAULT` (quad-out) normally and
`TRANS_OVERSHOOT` (back-out) reserved for playful pop-ins (podium, coins).

Rules: animate transform/modulate (not layout properties), never longer than
`DUR_SLOW` outside celebrations, and **every** animation added under M16 must
no-op when `ArenaFX.reduced_motion` is set (M12-03) — check it before
tweening, as `request_shake()` does.

## Images

Generated art goes through [IMAGE_REQUESTS.md](IMAGE_REQUESTS.md) (owner runs
the generations). Ship the fully-styled no-art fallback first; art slots in
when delivered. Fonts/licenses live in `assets/fonts/` and are logged in
`assets/CREDITS.md`.

## In-match overlay text (#831)

Screen text drawn over the 3D arena runs bigger than chrome (read from
further away) and comes from exactly two `MinigameView3D` helpers — never a
hand-rolled `Label.new()`:

- **Top-center phase/status headline** ("WATCH", "ROUND 3", reveals):
  `make_status_label(name)` — `SIZE_OVERLAY_TITLE` (40), black outline, on the
  never-hidden `BannerLayer`. Secondary status lines (round counters) pass
  `PartyTheme.SIZE_OVERLAY_BODY` and offset `position.y` below the headline.
- **Bottom-center gameplay prompt** (role prompts, charge bars, held-item
  hints): `make_banner(name)` — `SIZE_OVERLAY_BODY` (24), grows upward, clears
  the emote band (#258/#576).

**Color rule:** semantic meanings use `PartyTheme` tokens everywhere —
`SUCCESS` = good/complete, `DANGER` = threat/failure, `INFO` = neutral call
out, `ACCENT`/`ACCENT_BRIGHT` = coins & highlights, `TEXT`/`TEXT_DIM` for
plain copy. Game-identity palettes (team colors, lane colors, tier colors)
are fine but must be **named consts** on the view/sim — never inline
`Color(...)` literals at the call site.

**In-world text (`Label3D` — nameplates, pad values, callouts):** use
`pixel_size = 0.002` and set apparent size via `font_size` (30–56 by camera
distance), `outline_size >= font_size / 4` so text survives bright floors.
Don't scale with `pixel_size` — mixed pixel densities are what made in-world
text look incoherent across games.
