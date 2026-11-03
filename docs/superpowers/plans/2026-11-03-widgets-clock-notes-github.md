# Widgets 2c Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans. Checkbox steps.

**Goal:** Clock (4 layouts), Notes (mooi's notes, edited in place) and GitHub repo (3 layouts)
widgets.

**Spec:** `docs/superpowers/specs/2026-11-03-widgets-clock-notes-github-design.md`

## Global Constraints

- `language 0.9` and lua5.4-parsable.
- Every fact the logic writes is declared (the unit test checks).
- Event payloads stay under 2^24.
- Limits: notes 1, github 2.
- Before every commit run `capture.sh`; push.

## Review Focus

1. **Midnight and noon** in the words, and in 12 h mode.
2. **No `gh`, not signed in, a repository that doesn't exist,** and stats answering 202.
3. **notes.json changed by the side panel while a note is being edited** in the widget.
4. **A board with no due cards**, or only past ones.
5. **Two GitHub widgets for the same repository:** one fetch, shared.

### Task 1: The pure parts (TDD)
`lib/clockface`, `lib/ghparse`, and the kinds in `lib/widgets`, all with tests.

### Task 2: Logic
The clock tick, notes edits, GitHub fetches and cache, the info strip data, and the lane facts.

### Task 3: Scene
The components, the lanes, the panel options and the add chips; the Settings rows.

### Task 4: Live check, GPU, D140, review
