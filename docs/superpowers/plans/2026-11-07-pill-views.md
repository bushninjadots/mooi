# The Pill, round two, stage 1: views, shapes, detail — plan

> For agentic workers: superpowers:executing-plans. Spec: docs/superpowers/specs/2026-11-07-pill-round-two-design.md (D171) §2, §6, §7 (Super), and the owner's 2026-11-07 asks: the Pill's shape (attached · floating · dot), scroll over it through views, BMO as BMO.

## Global Constraints
- Setter codes append-only (lib/setters.luau ↔ tools/gen-settings.py); never hand-edit `<gen:edit>`.
- `fact.open` from the logic goes through `opens.by_logic`; scene-changed facts are followed with `on("fact:X")`.
- mooi.luau's main chunk is at 200 locals: new state goes in tables.
- Live tests restore settings byte for byte; no pointer driving.

## Review Focus
1. `pill.views` hand-edited with unknown ids or empty: scrolling still works (falls back to the default list).
2. Scroll while an activity shows (music, volume): the volume, not the views (only idle turns views).
3. The dot shape with the frame on and off: the dot is reachable and expands on hover, Super, scroll and activity.
4. Rest: a turned view goes back to the default after `pill.rest` s, never while pointed at or the board is open.
5. Detail `icon` on time/BMO/Nexus: they keep their own form (icon applies to module faces).

## Tasks
1. Pure: settings (pill.shape, pill.views, pill.detail, pill.rest), `pill.next_view`, widths by detail, the dot, chassis shapes. Tests first.
2. Bar: idle scroll turns views; rest; `pill_call` (Super: peek, again: the board); `mooi pill`; Hyprland Super release bind. Tests first.
3. Scene: faces at three details; workspaces dots, alerts with the newest, visualiser faces; the dot drawn and pulsing; BMO's body.
4. Rooms: Visualiser, Actions, Diagnostics, Workspaces, Wallpaper.
5. Settings rows, the edit bin's views, live checks, docs, review, merge.
