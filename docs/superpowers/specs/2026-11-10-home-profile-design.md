# The panel's Home profile (2026-11-10)

The owner: "when clicking the pill the homepage part. add a part ontop where obvios and relevant for profile
picture with system name". Asked which name, they said "yes hostname".

## What

Home opens with a profile card above its clock. It is a full-width inset card, 58 px tall, 14 px from the panel's
side and top: a 40 px round picture with an accent ring on the left, the display name in bold sans beside it, and
the hostname in small mono beneath. Without a picture the circle holds the display name's first letter in the
accent. The card is an identity header, not a control.

The picture and display name are the Nexus's identity (`settings.nexus.identity.avatar` and `.name`), the same
ones the Nexus's profile card and the lock screen use. The hostname comes from `hostname`.

## Approaches

1. **A card above the header (chosen).** It reads as the first thing on Home, gives the picture room, and keeps
   the existing header intact. Home grows by the card's height, 660 → 718 px.
2. Reorganise the existing header into one row with the picture, clock, weather and battery. Saves height but
   crowds four things into 58 px and makes the time smaller.
3. A wide banner behind the avatar and name. More decorative, but the owner asked for a picture and a name, and
   the Nexus's banner is a separate picture.

## Design

- Insert a `fl.well` card at `nb_x + 14, nb_y + 14`, size `nb_w - 28 × 58`, corner 14.
- Picture: 40 px circle at `nb_x + 27, nb_y + 23`, clipped, `fit: cover`, with a 1 px accent ring. Its absence
  shows the initial, centred, in the accent.
- Words: display name at `nb_x + 80, nb_y + 34` (sans 13, bold, ink), hostname at `nb_x + 80, nb_y + 52`
  (mono 9, dim). A small machine glyph sits at the card's right.
- Every Home y below the header shifts down 58 px. The panel's `PANEL_H.home` becomes 718.
- `lib/node/home.identity(name, host, avatar)` is the pure part: it trims, falls back to "mooi" for an empty
  name, keeps the avatar file name, and returns the first letter upper-cased.
- The logic reads the data folder with `files.folder`, sets the text/fact values, and refreshes them when
  `settings.json` changes.

## Constraints

- Never edit `shell/mooi-node.plm` by hand: change `tools/gen-node.py` and regenerate.
- Luau: no bitwise operators, no `goto`, no empty-matching `gmatch`; every local before its first use.
- Colours only from `fl.*` and the accent; Nerd Font for glyphs.
- Unit tests for the pure helper and scene-string checks for the new drawing.
- Checks: `python3 tools/gen-node.py`, `pleamar --check shell/mooi-node.plm`,
  `lua5.4 tests/unit/run.lua`, `lua5.4 tests/luau-ops.lua shell`, `bash tests/gate.sh`, and the `_ENV` allowlist.
