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
