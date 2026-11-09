# Music in the picture — design

> Status: approved in conversation (2026-11-09). The owner: "I want the visualiser to blend, become part of the
> wallpaper, so it adapts everything to it, colours and all, or be able to select which part or parts come in from
> the blend and out, like it's literally growing out from the image." Chosen: **picture bars**; it lives as **a
> Live wallpaper effect**; the parts it grows from are chosen **all four ways** — drawn areas, an edge or line,
> picked colours, the subject.

## What it is

A fifth Live wallpaper effect (D219), **Music in the picture**: while music plays, strips of the wallpaper itself are
pulled up out of the picture by the music's bands (the bar's analysis, `viz-levels.txt`, 32 bands resampled to 16),
lit at their tips, and fall back into it. Every colour is the picture's own: a bar is the picture stretched.

## Where it grows (any of them at once)

- **An edge line** (on by default): bars rise from a line across the picture — the bottom by default, or wherever
  it is dragged — up to the chosen height.
- **Drawn areas**: up to four boxes on the picture; bars rise from each box's floor, no taller than the box.
- **Picked colours**: up to two colours clicked in the picture; the parts of the picture near that colour stretch up
  with the band of their column.
- **The subject**: the picture's subject (mooi's cut-out, `wall-map.json`'s `cutpath`) stretches up with the music.

## Choosing them: the Overview's Music mode

A **MUSIC** button in the Overview. In Music mode the widgets step aside and the whole picture shows at full
brightness; a toolbar: **AREA** (drag a box), **COLOUR** (click the picture; its colour is read from the screen),
**EDGE** (on/off; drag its line), **SUBJECT** (on/off), **CLEAR**, **DONE**. What is chosen is kept in `surface.json`
(`music`: areas, colours, edge line, subject), mooi-surface's own file.

## Settings → Live wallpaper → Music in the picture

On (default on), strength, size (how wide the bars are), blend, and height (how tall bars may grow, % of the
screen, for the edge line).

## Calm and cost

As every Live wallpaper effect: only while music plays (or Try it), never while resting (off, opening shown,
fullscreen, reduced motion, the whole picture covered). The bars are one pass per place (an edge band, each area);
colours and the subject are one pass over the screen each. The bands are read every 50 ms only while it draws.

## Out of scope

Freehand shapes (boxes only), more than two colours, per-place strength.
