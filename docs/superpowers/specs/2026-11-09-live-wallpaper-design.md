# Live wallpaper — design

> Status: approved in conversation (2026-11-09): the owner asked for the moving wallpaper to be "its own feature
> for the shell" with its own settings (size, blend, the effects), then chose: **both** places (around the widgets
> below, or the whole picture — a setting), and **all four** effects (Ripple, Breathe, Flow, Light sweep), each
> with its own strength, size and blend. Grows out of D217 (the Subsurface's "moves the wallpaper").

## What it is

The wallpaper itself comes alive: the real picture (mooi's copy, fitted as the wallpaper is) is bent and lit by
a shader, over the wallpaper and under the windows (mooi-surface's `skin` surface, level bottom). It is its own
feature: it works with the Subsurface off.

## Settings → Live wallpaper (its own page)

- **Live wallpaper** on/off (`live.on`, on).
- **Where**: around the widgets below that move the wallpaper (`live.where = "widgets"`, the default: a patch round
  the Visualiser and the Clock whose `meet` is `moves`) or **the whole picture** (`"whole"`).
- **Speed** 50–200 % (`live.speed`, 100).
- **Try it**: plays every effect that is on for a few seconds, music or not.
- Each effect: on, strength, size, blend (`live.<effect>.on|strength|size|blend`, 0–100):

| effect | driven by | size means | default |
|---|---|---|---|
| Ripple | the music's level: rings run out with the beat | how far the rings reach, how wide | on · 60 · 50 · 50 |
| Breathe | the music's level: the picture swells and settles | how big the swell is | on · 40 · 50 · 60 |
| Flow | nothing: a slow drift, alive with no music | the scale of the drift | off · 30 · 50 · 70 |
| Light sweep | the hour turning (and Try it) | the band's width | on · 60 · 50 · 50 |

**Blend**: how softly the effect melts into the still picture — a wide feathered edge and a gentler mix at 100,
a crisp patch at 0.

## Calm and cost

Nothing is drawn while: Live wallpaper is off; the opening shows (it shows the real things); a window is
fullscreen; the whole picture is chosen and windows cover ≥ 90 % of the screen (read from Hyprland on window
and workspace changes, at most once a second); nothing would move (no music for Ripple and Breathe, no Flow, no
sweep). Each effect is one shader pass over its patch (or the screen); the surface paints at most 30 times a
second. Reduced motion: no Flow, no Ripple; Breathe and the sweep stay still at their resting state (none).

## Out of scope

Contour traces (need wall-sense), video wallpapers' own frames (the shader bends a still, as the Subsurface's
effects do), per-monitor settings.
