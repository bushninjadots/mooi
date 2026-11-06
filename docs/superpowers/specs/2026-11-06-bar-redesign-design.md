# The bar, redesigned: Shape × Material × Density

Date: 2026-11-06 · Status: design approved in brainstorming, spec awaiting review · Decision: D164
Mockups: `.superpowers/brainstorm/583795-1793963491/content/` (concept, pill, editor, frame-theme)

## 1. Why

The bar works but does not yet feel finished. On 2026-11-06 the visual audit and the owner named:

- **Empty humps**: the frame's band rises in the gaps between bar groups, so the gaps read as empty
  islands.
- **Jumps**: the bar's bottom edge sits at three heights (frame on y≈34, frame off + morph y≈37, the
  bar's own outline y≈31), so toggling the frame moves it.
- **Inconsistency**: uneven gaps between modules, unlabelled icons beside labelled ones, accents used
  at random (a pink date, red/green transport buttons), low-contrast workspace numbers.
- **Too little to do, and no quiet option**: the owner wants a bar that does a lot *and* a true
  aesthetic-minimal mode.
- **No premium feel**: depth, motion and polish are uneven.
- **A tray that cannot act**: clicking Steam should offer its actions (open, close, its own menu).
- **Editing is weak**: arranging and customising the bar should be direct and complete.

Success is a bar where every combination of the owner's choices looks deliberate, nothing jumps or
seams, the same rules (spacing, colour, depth, motion) hold everywhere, and it can be anything from a
single quiet capsule to a dense instrument panel.

## 2. The model

The bar becomes three independent choices that combine freely, over one shared core.

| Axis | Values | Setting |
| --- | --- | --- |
| **Shape** | full · notch · islands · **pill** | `bar.mode` (gains `pill`) |
| **Material** | **ferrolume** · **liquid** · **cartridge** | `bar.material` (new, default `ferrolume`) |
| **Density** | minimal · balanced · rich | `bar.density` (new, default `balanced`) |

- The **core** owns the modules, their order, their data, the layout, the editor and the shape model.
  It knows nothing about how a body looks.
- A **material** owns only the body: how a piece, a band, an island, the Pill and a moon are drawn,
  their depth, and the character of their motion (Ferrolume slides, Liquid pours, Cartridge clicks).
  Swapping it never changes what is on the bar or where.
- **Density** decides what each module shows (§5): at minimal the bar can be a single capsule.

### What happens to today's settings

Every current setting is kept and applies to whichever material is active:

- Outline (`bar.edge`, `bar.outline_width`, `bar.outline_colour`), `bar.shadow`, `bar.opacity`,
  `bar.frost`, `bar.smoke`, `bar.ground`, `bar.height`, `bar.offset`, `bar.width`, `bar.radius`,
  `look.corners`, `look.corner_size`, `bar.bg*`, `bar.rail`, `bar.accents`, `bar.visualizer`,
  `bar.workspaces`, `bar.helix_frame`, `nexus.notches`, `clock.view`, `tray.style`, `island.*`,
  `music.rim*`, every `frame.*`.
- `bar.surface` (solid · glass · blur · clear · mech) becomes the **finish** of the material.
- `bar.style` presets become **per-material presets**: Ferrolume keeps instrument, glass, floating,
  minimal and steel; Liquid and Cartridge get their own sets. A preset only writes the finer settings;
  nothing is locked, and editing a value afterwards shows the preset as "Custom".
- A settings file from before this redesign loads unchanged: `bar.material` and `bar.density`
  default in, `bar.mode` keeps its value.

## 3. One chassis shape

Today the bar draws its own outline in some modes and mooi-frame draws it in others, from geometry
each computes on its own. That is where the three bottom heights and the humps come from.

- **One shape model** (a pure `lib/` module, unit-tested) turns the layout into the chassis: the
  pieces (one per group or module, per shape), the band (when the frame is on), the Pill and its
  moons, and the islands grown out of pieces. It outputs rectangles, radii and blend radii, and
  nothing else.
- **One program draws it**: mooi-frame draws the chassis in every shape, frame on or off, so there is
  one outline and one bottom edge. The bar draws only content. (This is already true with
  `island.morph` on; it becomes true always.)
- **No humps**: the band is flat between groups; it only rises where a piece is.
- **One bottom edge**: a piece's foot is the same `row_b` whatever the frame does; the blend between a
  piece and the band is measured so it never moves the foot. A test asserts the foot's y in all states
  (the 16-state harness used on 2026-11-06, kept as `tests/chassis.sh`).
- **Swell** moves the one outline in every shape and material, at the outline width; no second line
  (the rule of commit 0ac5421, kept).
- **Performance**: the frame keeps its tiled drawing (gen-frame.py). Budget: the frame with swell at or
  under today's (~10 % GPU), the bar at or under today's (~2 % of a core); measured before and after
  each stage.

## 4. The Pill

A capsule at the top centre that becomes whatever is happening, then shrinks back.

- **States**: idle (clock + workspaces), music (art, title, live bars), volume/brightness, a
  notification (grows taller), recording/timer, charging/battery low. Clicking opens that thing's full
  island; scrolling adjusts what it shows (volume over music, workspaces over idle).
- **Two at once** (`pill.multi`): **satellites** (default): the main activity keeps the Pill, others
  bud off as moons beside it, each a live badge; hovering a moon swaps it in. **split**: the capsule
  pinches into two side by side and rejoins when one ends.
- `pill.moons` (1–4, default 3): moons shown at most; the rest wait.
- `pill.order` (ids): which activities may take the Pill, in priority order; each can be switched off.
- In every material and with the frame: the Pill hangs from the band (Ferrolume: a plate set into it;
  Liquid: the rim pours into it, moons pinch off; Cartridge: a cartridge in a slot).
- The Pill is also a **component**: in full, notch and islands it can be placed like any module.

## 5. Modules and density

- Every module renders through one component contract: icon, value, label, a small graph, and a
  warn/critical state. Spacing comes from the grid (§7), not from the module.
- Per-module options (stored under `bar.modules.<id>`, beside today's `show` and `frame`):
  `display` (icon · icon+value · label+value · graph), `minimal` (hide · icon · into the Pill),
  `accent` (theme · ember · custom colour), `warn` (thresholds where it applies), and its click,
  right-click and scroll actions.
- Density applies those: minimal uses each module's `minimal` choice; balanced shows icon+value;
  rich shows labels and graphs.
- **New components**: GPU, disk, power profile, timer, pomodoro, window title, screen recorder,
  spacer, divider, and **group** (several modules sharing one plate).
- **Media**: the red/green split transport is replaced by themed controls (previous · play/pause ·
  next) that follow the material.

## 6. The editor

One edit mode on the live bar (the current ✎ edit mode, extended), not a separate window:

- **Top strip**: Shape, Material, Density, Preset, Frame on/off, Swell (off · swell · ripples ·
  pulse); undo; "save as my preset" (named, stored in settings, listed with the material's presets).
- **On the bar**: every component has a handle; drag to reorder within and across left, centre and
  right; drop slots show where a drag can land; the Pill and its moons move like any component.
- **Components panel**: the palette by category (system · media & time · desktop · life); drag in to
  add, drag out to remove.
- **Selected panel**: the per-module options of §5.
- **Pill panel**: satellites/split, moons at most, the priority list (drag to order, switch each).
- Settings → Bar shows the same choices for keyboard use, and both write through `lib/settingsfile`.

## 7. Consistency rules (all materials, all shapes)

- **Spacing**: one 4 px grid: 8 px between items in a module, 12 between modules, 24 between groups;
  every module the same height, text on one baseline.
- **Colour roles**: accent (active, live), warn (thresholds, low battery), critical (recording,
  failure), text, secondary; all from the wallpaper palette (Matugen through `lib/ferro`), with
  contrast checked against the body they sit on. No colour outside a role.
- **Depth**: three layers: ground (band/frame), body (plates, droplets, cartridges, Pill, moons),
  content. One shadow scale, one inner-light rule.
- **Motion**: one spring family (quick, settle, slow) shared by bar, islands, Pill and frame; the
  material only sets the character. `motion.reduced` turns all of it into fades.

## 8. The tray

- Clicking a tray icon opens a themed menu in an island: the app's own menu items (read over D-Bus from
  its `com.canonical.dbusmenu` object, the way Steam and most apps publish them), plus mooi's own:
  open/activate, and close (the app's Quit item when it has one).
- Pleamar's `tray` service only lists items today, so this starts with a **spike**: read and trigger
  Steam's menu with `gdbus` from a scene's logic (it would join that scene's `run:` list). If that
  works, the menu is built on it; if not, the fallback is `tray.context` (the app's own menu, as now)
  plus activate, and a request to Pleamar for menu support.

## 9. Build order (each stage its own plan, tested and shipped before the next)

1. **Core and chassis**: the shape model, mooi-frame drawing every shape, no humps, one bottom edge,
   `bar.material`/`bar.density` in the schema, `tests/chassis.sh`. Ferrolume only.
2. **Ferrolume, perfected**: the consistency rules applied to every module in full, notch and
   islands; the new media controls; per-material presets.
3. **The Pill**: shape, states, satellites and split, priority, in Ferrolume.
4. **Modules**: the component contract, per-module options, density, the new components.
5. **The tray**: the spike, then the menu.
6. **The editor and settings**: §6.
7. **Liquid**: the material, its frame, its Pill.
8. **Cartridge**: the material, its frame, its Pill.

## 10. Testing and verification

- Unit tests for the shape model, density rules, Pill priority, settings migration and presets.
- `tests/chassis.sh`: the live harness that cycles Shape × Material × Border × Frame × Swell,
  screenshots each, measures the outline's weight and the foot's height, and restores the owner's
  settings byte for byte.
- After any logic change, `bin/mooi session`, then `~/.local/state/mooi/mooi.log` checked for
  `runtime error` (a Pleamar-only failure the unit tests cannot see, as on 2026-11-06).
- Before/after screenshots for every visual change; performance sampled per stage against §3's budget.
- The gate (`bin/mooi check`) and the CI container gate green before each push.

## 11. Out of scope

- The Control Nexus, the side notch and the player's own designs, except where they meet the bar
  (islands, the Pill, colour roles).
- Multi-monitor layouts beyond one bar per monitor as today.
- Changes to Pleamar itself (a menu request is filed upstream if the tray spike needs it).
