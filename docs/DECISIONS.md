# Decisions

Each one is reversible; the "to change back" line says how.

## D1 · 2026-10-14 · Name: mooi
Renamed from "Tidal Shell". The scene is `mooi.plm` (socket `mooi.sock`), settings live in `~/.local/share/pleamar/mooi/`, and the environment variables are `MOOI_*`.

## D2 · 2026-10-14 · ArchEclipse stays the login shell
mooi never starts at login. Beside mode is the default; takeover is explicit and ends at logout. See SWITCHING.md.
*To change:* add `exec` of `bin/mooi start` (or `takeover`) to `exec.lua`. Not planned until mooi can replace ArchEclipse.

## D3 · 2026-10-14 · Keys: Super+Alt+Space / Super+Alt+Shift+Space
The brief's Super+Space is your float toggle and was kept. *To change:* `bind.lua`, lines under `--- mooi`.

## D4 · 2026-10-14 · Pleamar 0.4.6 for everything
The shared binary was upgraded. 0.4.x paints only what changed (fixes limitation P14) and falls back to ext-workspace when Hyprland's socket is missing. *To change back:* `cp ~/.local/bin/pleamar-0.3.7 ~/.local/bin/pleamar`.

## D5 · 2026-10-14 · Notifications: ArchEclipse keeps them, for now
- **Beside mode:** mooi does **not** declare Pleamar's `notifications` service. ArchEclipse stays the one `org.freedesktop.Notifications` server; nothing is taken from it.
- **Takeover mode (Phase 6):** mooi will declare it only when `MOOI_MODE=takeover`, when ArchEclipse's bar is stopped and the name is free. Pleamar queues behind a server that does not give the name up, so even a mistake would not steal it, but this is to be verified in Phase 6 before relying on it.
- **Why:** two notification servers cannot coexist, and you want ArchEclipse untouched while mooi is tested.
- **To change back / other options:** (a) mooi takes notifications in beside mode too, with a switch as Marea does. (b) mooi shows notifications by reading ArchEclipse's (needs an export from Quickshell). (c) Keep D5. Revisit at Phase 6.

## D6 · 2026-10-14 · One island slot
At most one island is open (`open: none | window | system`). Opening another hands the slot over. Escape acts on the topmost level: a pending confirmation, then an expanded state, then the island. *Alternative considered:* several islands at once with a z-stack. Rejected because it needs a focus model the brief does not ask for yet.

## D7 · 2026-10-14 · Shown values come back from the system
Sliders and window state display what the services or Hyprland report, never the requested value. Requests are coalesced to one every 40 ms (latest wins). Brightness from a slider never goes below 1 %.

## D8 · 2026-10-15 · The keyboard belongs to the scene, and is asked for by its first surface
`keyboard:` is read once per scene: pleamar takes the mode from `scene.surface().keyboard`
(the first surface) and a single `while` condition (the last surface that declares one). With
each island declaring its own `keyboard: exclusive while open == <name>`, **no** island ever
had the keyboard: typing went to the window below and Escape did nothing. So the Spine — the
scene's first surface — carries the scene's only clause, and the islands declare none; each
sheet takes it while it is open. The clause is `exclusive while (open != none or nav_open or
mark_open) and not (open == command and cmode == actions)`.
*Consequence:* giving a window the keyboard (membrane ↵, its Focus satellite, an Atlas tile)
cannot be done while the island holds it, so such an action gives the slot up first, waits the
frame that releases the keyboard, and brings the island back with the failure if it did not
happen. An `on_demand` keyboard would not work: its loan outlives the island by 300 ms.
*The one gap:* while the command membrane is in its window-actions mode the arrows and Enter
belong to the actions, but the focused `input` keeps eating them, and the scene's `blur` effect
does not take the writing cursor back (measured; MECHANISM.md §7). Because the condition above
is the scene's entire claim, making it false for exactly that mode is what frees the field: the
scene then holds no keyboard, the input stops swallowing the keys, and the rules read them.
Narrowing it on the island instead would replace the scene's condition everywhere — measured too,
and the reason an Escape in the Atlas stopped reaching it — which is why the gap is expressed in
the one place it is.
*To change:* if upstream makes `keyboard:` per surface, each island can declare its own again
(AUDIT.md §4 has the experiment and the source lines).

## D9 · 2026-10-15 · The Atlas is a wall of Hyprland's windows; `thumbnails` lends the pictures
The tiles are Hyprland's clients (`hyprctl -j clients`): each brings the address the actions
are verified against and the workspace it sits on, so every tile can be focused. The
`thumbnails` service is used for the pictures only — its ids are the compositor's own
(`18000015`), not addresses — matched to a window by app and title, one window each; a window
without a picture is still a tile, named only. Pictures are asked for only while the Atlas is
up (`thumbnails.want("all")`; `thumbnails.want()` on close).
*Alternative considered:* tiles built from the `thumbnails` list, joined to Hyprland by
address. Rejected: the ids do not match, so a tile could not be focused at all.
*Consequence:* the board is rebuilt on every report while the Atlas is up, so a window opening
or closing moves the tiles under the selection (an index); the board is left as it is while
the Atlas leaves. The bounded 1–16 workspace map stays as state (`spaces`).

## D10 · 2026-10-15 · The Atlas moves a window in place, and previews are a setting you can promise off
`m` gives the strip under the board the room it needs (`bh`, a spring) and turns it into the
workspace picker, drawn from the same `spaces` map; `←→` or a click chooses a slot, ↵ moves
the selected tile's window there through the window island's verified action (`follow = false`,
so the user stays) and **the Atlas stays open**: a move is not a choice, so it should not throw
the board away, and the Spine pulses where it went. Escape leaves the strip, then closes the
Atlas (the two rules are separate, because every rule's `while` is read before any of their
effects are).
*Not digits:* a scene key cannot be a digit (`key 1` is a load error: the keyboard names are
`Escape`, `a`, `Ctrl+k`…), so the picker is walked with ←→ or clicked; a number strip the user
must walk is what the window island already does.
*Previews:* `p` flips `atlas.previews`. Off is a promise that nothing is captured, not a
blinding of the tiles: `thumbnails.want()` is called at once and the frames are given back, and
no picture is matched into a tile while it holds. It is a setting, so the choice survives a
restart — and **safe mode never writes the settings file**, so a test run cannot become the
user's config (checked: `tests/config-recovery.sh` compares the file before and after).
*Alternative considered:* a separate "privacy mode" fact that is not a setting. Rejected: a
privacy switch that forgets itself at the next restart is not one.

## D11 · 2026-10-15 · The theme: fixed by default, wallpaper when asked, one Matugen, no surprises
**`theme.source` is `fixed` by default.** The brief's palette is the shell's identity; a
wallpaper-derived palette is an opt-in, not something that happens to you because you changed
your desktop picture. With `source = wallpaper`, Matugen's dark scheme fills the fourteen
semantic tokens (the mapping is written out in `lib/theme.luau`, one Material role per token).
**Matugen runs with mooi's own config** (`theme/matugen.toml.in` + `theme/palette.json.hbs`,
paths filled in by `bin/mooi theme-sync`), which writes exactly one file — the palette mooi
reads — so the user's `~/.config/matugen/config.toml` keeps owning every other program's
colours and there is still only one palette generator in the session (the brief's rule).
`theme-sync` passes `--source-color-index 0`, the same flag the user's `matugen-theme.sh`
passes, so mooi and ArchEclipse take their colours from the same source colour of the same
wallpaper (checked: identical hexes in both files).
*Colour is a fact, and only colour.* Pleamar has no colour facts, so each token is three number
facts handed to `rgb()`; the logic writes all forty-two or none. A theme update therefore cannot
move a surface, change a spring or touch a workspace (checked in `tests/theme.sh`: `settings.json`
byte-identical, other facts unchanged).
*Refused whole, never half.* Completeness and WCAG contrast are checked before anything is
painted, and a theme that fails leaves the last good one on screen with the Spine's dot lit —
"wallpaper changes may update semantic colours" but they may not make the shell unreadable.
*To change:* set `theme.source` back to `fixed`, or override single tokens under
`theme.overrides`. **To make it automatic:** add one line where your wallpaper is set, e.g. a
post-hook in `~/.config/matugen/config.toml` (the user's file — mooi does not edit it):
`post_hook = "bin/mooi theme-sync >/dev/null 2>&1 || true"` (absolute path), or the same line at
the end of `~/.config/hypr/theme/scripts/matugen-theme.sh`. Then mooi recolours itself live,
without a restart, because it watches the palette file.
*Not built:* light schemes, named theme packages, and a Workshop editor for any of it.

## D12 · 2026-10-15 · The Mechanism: the bar is four regions down one rail, and geometry carries state
mooi's bar — the Mechanism — is the always-present rail the whole shell hangs from, in four
regions top to bottom: **identity** (the mark, opening the bar's own menu), **workspace
navigation** (the Atlas key, the wheel's door, then the scale of workspace positions with the
carriage riding it), **quick access** (search, the focused window) and **status** (the
essentials, the battery key, the clock). It lives in one surface reserved for the rail: what
opens beside it floats over windows, and nothing beside the rail takes a click (pleamar commits
the input region from what is painted — checked on the running desktop).
*The rule:* **geometry carries state, colour only confirms.** A position's size and the
carriage's travel say what is; colour agrees. `accent.primary` means *what is*, `focus.ring`
means *what the pointer or the keyboard is on*, and nothing else is allowed to be loud. Two
consequences fell out of it: a conditional colour cannot be a `let` (only an arithmetic
`mix(...)` can), and nothing may be placed from a value that has not arrived — so a widget the
machine cannot have (no backlight, no radio) is not drawn, and the widgets above it close the
gap (`have_bri`, `have_bt`), leaving no hole in the column.
*Scale, not a list.* The workspace map (`lib/spaces`) is drawn as fixed-pitch positions, not as
the workspaces that happen to exist, so a position for a workspace the compositor has not made
yet is still there to be chosen; the pitch is a token (`g.slot`), and `g.slots_y` sits the first
position below Region B's keys.
*Preview is not commit.* The wheel and the scale may show a workspace before the compositor
goes there (`nav_sel` vs `active_row`), and no animation ever delays the real operation: `↵`
asks `workspaces.focus` at once, and the readout catches up. An interrupted animation is simply
the next state (MECHANISM.md §3).
*Status is a door, not a control.* Network, Bluetooth, brightness and volume each show what the
services report and each **opens the system surface**, which owns the controls — the bar never
offers a control it cannot honestly drive. Bluetooth is shown and never toggled: there is no
documented write for it, so `bin/mooi` would have to shell out and read the state back, and a
switch that cannot be trusted to reflect is worse than a state that can.
*Not here:* no workspace overview, no Assemblies, no rewrite of the command membrane, no
notification manager, no replacing Hyprland. Appearance and density (placements, size presets,
accent and surface choices) are still unbuilt — the first-run stopping point.
The whole account is `docs/MECHANISM.md`.
