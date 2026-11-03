# Widgets 2b Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Widgets that read the wallpaper (tone, haze, local accent, mood, calm spots) and can sit
behind its subject.

**Architecture:**
- `bin/mooi wallmap` uses ImageMagick and rembg and writes a cached cut-out plus a 32×18 map.
- `lib/wallmap` is pure and works out what each widget gets.
- The widgets logic sets per-row facts; the scene draws in depth order with the cut-out image
  between.

**Spec:** `docs/superpowers/specs/2026-11-03-widgets-wallpaper-aware-design.md`

## Global Constraints

- `language 0.9`; lua5.4-parsable; event payloads under 2^24.
- Nothing moves by itself.
- GPU under 8 % with depth on.
- Before every commit run `capture.sh`; commit with the Co-Authored-By line and push.

## Review Focus

1. **A wallpaper changed while a wallmap is running.** Only the latest result is applied.
2. **rembg missing.** No depth, everything else works, and Settings says why.
3. **A video wallpaper.** Colour from its first frame, depth off.
4. **A widget straddling bright and dark.** Tone follows the mean; contrast still ≥ 4.5 for the
   accent.
5. **The bar's height.** The cut-out lines up with the wallpaper.

### Task 1: rembg and `bin/mooi wallmap`
- [ ] **Install:** `uv tool install --python 3.13 "rembg[cpu,cli]"`. Check that `rembg --help`
  works and fetch the model once.
- [ ] **Write the subcommand.** `wallmap` in `bin/mooi` (frame, cut, grid stats via `magick … -scale
  32x18! txt:` for luma and Lab, and Sobel edges for detail), plus the cache and the copy.
- [ ] **Verify** on the current wallpaper: the files exist, the map is valid JSON, and the cut-out
  has transparency.
- [ ] **Commit.**

### Task 2: `lib/wallmap` (TDD)
- [ ] **Tests:** parse, under, tone, haze, accent contrast ≥ 4.5, calm_spot avoids subject and
  others, mood ranges.
- [ ] **Implement** until they pass, then commit.

### Task 3: The logic and options
- [ ] `lib/widgets` options `adapt` / `behind`, with a test.
- [ ] `lib/config` `widgets.depth` / `widgets.mood`, with a test.
- [ ] **Logic:** watch the wallpaper, run wallmap (latest wins), read the map, set the row facts,
  mood facts, depth facts and `text.wall_cut`.
- [ ] **Commit.**

### Task 4: Scene
- [ ] Components take tone, haze and accent; lanes take the accent; mood scaling.
- [ ] Depth order with the cut-out image.
- [ ] **Edit mode:** subject shading, the hint, and the panel's ADAPT / BEHIND / CALM SPOT.
- [ ] **Live screenshots** and **GPU**.
- [ ] **Commit.**

### Task 5: Settings, log, review
- [ ] Settings switches (Depth, Mood) and the rembg note.
- [ ] D139, TODO.
- [ ] Final review by a fresh reviewer; fix the Important findings.
