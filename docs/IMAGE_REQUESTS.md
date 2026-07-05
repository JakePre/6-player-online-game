# Image Requests — owner-run generation ledger

The owner runs image generations on request (M16 directive, 2026-07-05). Agents
**never** generate or scrape images themselves — this file is the queue.

## Workflow

1. **Request:** append a row to the table below (append-only, like
   `assets/CREDITS.md` — never edit or reorder another task's rows). Write the
   prompt as you'd give it to an image model: subject, style, mood, palette
   hints, what to avoid. Reference the game's look: chunky low-poly party game,
   dark slate UI, coin-gold accent (`PartyTheme`).
2. **Generate:** the owner batches pending rows, runs them, and delivers
   results (commits the files to the listed destination, or attaches them to
   the requesting issue). The owner may regenerate/adjust taste-wise — the
   prompt is a starting point, not a contract.
3. **Land:** the requesting task imports the delivered file, logs it in
   `assets/CREDITS.md` (author: owner-generated), flips the row's status to
   `landed`, and wires it in.

**Never block on an image.** Ship the fully-styled fallback first; art slots in
when it arrives. A `requested` row is a follow-up, not a dependency.

## Conventions

- **Sizes:** UI icons 256×256, key art / intro cards 16:9 (≥1280×720),
  backgrounds ≥1920×1080, app icon 512×512 (square, readable at 32×32),
  boot splash 16:9.
- **Destination:** under `assets/generated/<area>/` unless the row says
  otherwise, kebab-case filenames.
- **Status values:** `requested` → `generated` (delivered, not yet wired) →
  `landed`. Withdrawn requests get `withdrawn`, not deleted.

## Requests

| ID | Task / issue | Prompt | Size / aspect | Destination | Status |
|---|---|---|---|---|---|
| IMG-001 | *(example — replace with the first real request)* M16-03 | Party-game logo lockup: the words "PARTY RUSH" in chunky rounded 3D letters, coin-gold on dark slate, confetti accents, clean silhouette, transparent background | 2048×1024, transparent PNG | `assets/generated/menu/logo.png` | withdrawn |
| IMG-002 | M16-03 (#515) | Logo lockup: the words "PARTY RUSH" in chunky rounded 3D block letters with a soft bevel, warm coin-gold (`#F5CA33`) with a darker gold rim, a few confetti flecks around it, clean readable silhouette, no background. Matches a low-poly couch party game. The main menu shows a two-tone text lockup as the fallback until this lands. | 2048×1024, transparent PNG | `assets/generated/menu/logo.png` | requested |
| IMG-003 | M16-03 (#515) | App icon: a single chunky coin-gold token with a subtle star/burst motif, centered on a dark blue-slate rounded square, bold and readable down to 32×32, no text. Playful, low-poly party-game feel. | 512×512, square PNG | `assets/generated/menu/app_icon.png` | requested |
| IMG-004 | M16-03 (#515) | Boot splash: a wide dark blue-slate (`#12141C`) backdrop with a soft top-down light, scattered faint gold confetti/coin bokeh, and generous empty center space for the logo to sit over. Muted, ambient, not busy. Until this lands the splash is a flat `BG_DARKER` fill. | 1920×1080, 16:9 PNG | `assets/generated/menu/boot_splash.png` | requested |
