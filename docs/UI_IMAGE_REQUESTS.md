# UI image generation requests (M16)

Agents cannot generate images. If an M16 (or any) task would benefit from a
generated image — icon, background illustration, texture, logo, splash art —
**do not** try to source or fake one. Append a row below describing exactly
what's needed; the owner runs the generation offline and drops the result
into the path you requested, then comments on your claim issue with the
final file path(s) so you can wire it in.

Append-only, like `assets/CREDITS.md` (§4 hotspot rule: add rows at the
bottom, never edit/reorder existing ones — adjacent-append conflicts resolve
by keeping both rows). Mark a row `done` once the asset lands and is wired
in; don't delete rows.

| Task | Needed | Suggested path | Notes | Status |
|---|---|---|---|---|
| _(example)_ M16-02 | Main menu background illustration, iso-arena at dusk, 1920x1080 | `assets/ui/menu_background.png` | Matches the KayKit/Kenney low-poly aesthetic already in use; no photorealism | open |

## Requesting well

- Be specific about **size/aspect ratio**, **style** (match the existing CC0
  KayKit/Kenney low-poly look — see `assets/CREDITS.md` for the established
  palette/asset sources), and **where it's used** (background, icon at what
  display size, tileable texture, etc).
- One row per distinct asset. Don't bundle "5 icons" into one row — list
  each so the owner can generate and hand them back independently.
- If your task can ship without the image (e.g. a solid-color placeholder
  now, art later), do that and note it in your PR rather than blocking on
  this list.
