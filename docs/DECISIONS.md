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
