# mooi — to do

What the user has asked for and is not built yet, newest first. The long view is docs/VISION.md;
what was done, and why, is docs/DECISIONS.md.

## The Subsurface (D209, the spec's phases 2–5)

- [x] **Phase 1, the opening**: the shared hole, the Tear and Aperture, follow/snap/section/full/heal, the
      hubs and components below, widgets and BMO as citizens, click to use, drag out and back, the keyboard
      path, the drag bind (`docs/plans/2026-11-08-subsurface-phase1.md`)
- [x] **Phase 2a, the Overview canvas (D211)**: full open, the wallpaper pulls back to the thin lit
      margin and an opaque canvas with a faint grid takes the screen; hubs and components are arranged
      there — drag by the body, eight-pixel snap, clamped, saved to `surface.json`, with Undo / Reset /
      Close on the canvas and a Super tap, Esc or a press on the margin to close
- [ ] **Phase 2b, the Overview's shapes and the Nexus**: resize a place with a shape handle and inspector,
      and move the Nexus deck and canvas cards in as citizens (the full-screen successor to the Nexus)
- [ ] **Phase 3, push up from below**: `meet` per thing (woven); a song change, a notice or an event makes a
      soft bulge in the wallpaper over its place, its words pressing up through the picture; light through
      the skin (glow and contour traces, the notification ping and border trace) once wall-sense exists
- [ ] **Phase 4, peering and burying**: hold Super over a window with another behind it — a live patch of the
      window behind, widened by the wheel; drag a window into an opening (or Super+B) to bury it on
      `special:mooi-buried` with a live tile; a click brings it back
- [x] **D210, the Subsurface's own settings and looks**: its own Settings page (hold, eight effects, intensity,
      edge, colour, speed, corner; wallpaper show/dim/tint/fit/grid/labels; glow and ping; layout, component
      and BMO sides, Overview margin; edit/reset places; widget style and above/below; power confirm), the
      wallpaper drawn under the opening, and the lag fix (one process per citizen, a 100 ms follow throttle,
      a frozen section, the visualiser's open gate)
- [x] **Phase 5's effect list (D210)**: Membrane, Ripple, Fold, Dissolve, Glass, Glow, with intensity, edge
      width and colour
- [ ] **Phase 5, the owner's own shaders and chains**: a folder for owner WGSL, and effects that chain (D210
      ships the eight the spec names)
- [ ] **The owner's real-key session** (phase 1's open item): switch Surface on, hold Super, roam, snap a
      widget and a hub, widen, click a hub item while holding, drag a widget out, let go; Super+Return and
      Super+W must leave no opening; run `tests/surface.sh` with this branch on the desk

## Next: the spine and the Nexus drawer (the user's plan, 2026-10-28)

- [x] The spine & shelves (D100) — the user likes it
- [x] **The spine as an option in Settings**: its own "Control Nexus" card on Settings → Colour, beside
      what the mark opens and the deck's edge (D102)
- [x] **Autohide for the spine** (Settings → Colour → Control Nexus → Hide the spine, D103): out of sight until
      the right edge is touched; a hairline keeps its place, warm while notifications or updates wait
- [x] **The Control Nexus redesigned: the Nexus Deck** (D102) — Console + Context + Scenes merged, workspace
      previews in the middle, on any edge (Settings → Colour → Control Nexus → Deck edge)
- [x] **Cascade** as the opt-in alternative (Settings → The mark opens → Cascade): every shelf out at once
- [x] Deck: move and hide its parts by hand (✎), seven parts, twelve quick settings (D103)
- [x] Deck: drag a window from one miniature onto another; name a scene as it is saved; an environment (D43)
      restored with a scene (D103)
- [x] Cards on a circuit, every one movable, two rows, profile/activity/visualiser (D105)
- [x] The side notch: Claude, music, workspace and wallpaper arcs, weather, GitHub; notches off the Nexus;
      Claude in BMO; Claude and GitHub bar modules (D106)
- [x] Settings → SHELL → Nexus; angular notches; cards resized (D108); Hyprland 0.57 wobble and blur finishes (D107)
- [x] BMO: his own chat, game pop-ups, a tantrum, peeking (D109)
- [ ] Log out and in to run Hyprland 0.57, then check Wobble and Blur finish look right (the variant's spelling)
- [x] The frame and the bar as one border in every mode; the frame its own program (D119)
- [x] The side notch and the stash behave and look as one family (D121)
- [x] Nexus: two rows are a free canvas, cards sized by hand; sizes down a side (D122)
- [x] The spine and Cascade removed at the user's request (D123)
- [ ] Run `sudo hyprpm remove Hyprdrive` (the plugin is no longer used, D118)
- [ ] Later: one deck per monitor; the notch on the right edge as a choice; the GitHub panel's
      issues assigned to you

## Bar islands (asked 2026-10-27) — built (D97)

- [x] **One design for every pop-up island** — the island kit (ui/island.plm), two styles:
      Plate (Ferrolume) and Tether (ours), Settings → Colour → Islands
- [x] Resources → **system statistics island** · clock → **calendar island** + view states (right
      press) · media → view states (right press) · **sound, display, power islands** · **weather island**
- [x] **Control Nexus** — a right-side drawer with everything, every tile acting (D98)
- [ ] Later: per-app volumes in the sound island; the Signal Field and side panels in the kit

## Roadmap (asked 2026-10-27, in order)

- [x] Workspaces: one viewer (D90) · Colours and theming, light mode (D91) · Corner style (D93)
- [x] Music island from the bar: ArchEclipse's player ported (D142). [ ] The full player (D92) still waits for its review; finish later (deferred review
      items in docs/superpowers/plans/2026-10-27-music-player.md's ledger, and: EasyEffects dies with the
      player, so the EQ only applies while it is open).
- [x] Settings — `shell/mooi-settings.plm`, in daily use (D147)
- [x] Wallpapers: Lumen removed; Skwd Wall is the one picker beside the notch's arc (D118)
- [x] Wallpapers are mooi's (D145): the desk draws every kind (videos through mpvpaper), `mooi wall apply`,
      the picker (strip + colour orbit, Super+W), the notch wears through it
- [x] Skwd Wall, its daemon, wallpaper-styles and the Quickshell picker retired: archived in
      ~/.local/state/mooi/archive/skwd-2026-11-04, out of setup/ (D146). [ ] `sudo pacman -Rns awww` (yours to run)
- [x] Control Nexus — the drawer (D98)
- [ ] The bar ("needs big work") — islands done (D97); next the Control Nexus
- [x] BMO — starts with mooi, throwing, sizes, the bar, variants, awareness, idle life, talk, Settings page (D94)
- [x] Desktop widgets, music first: Now Playing (Sleeve, Lyric stage, Record) + Visualiser (12 modes), edit mode, Settings → Widgets (D137)
- [ ] After a few days on the new widgets: delete `~/.config/desktop-widgets` and `setup/home/.config/desktop-widgets`, drop it from `setup/capture.sh` (D137)
- [x] Widgets 2a: editor (selection, handles, keys, undo, align, lock, panel v2) + visualisers 16–128 bars, upgraded modes (D138)
- [x] Widgets 2b: wallpaper awareness + depth behind the subject (rembg), resizing fixed (D139)
- [x] Widgets 2c: Clocks (digital, analogue, words, info), Notes, GitHub (card, commits, pulse) (D140)
- [x] Widgets 2c: every new layout seen on screen (D141 desk mode screenshots)
- [x] Widgets 3: weather, system, calendar, focus, Claude, photo, launcher; styles, shadows, ambient, groups, desk mode; music transport + viz; GitHub activity map (D141)
- [ ] Deferred: the claude.ai BMO design doc still describes the Quickshell BMO
