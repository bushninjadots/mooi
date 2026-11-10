# The Pill: one pill, one panel (redesign, 2026-11-10)

Approved by the owner after the D246–D258 designs were rejected as scattered. Design references (third-party
screenshots, kept OUTSIDE the repo in `/home/bender/Projects/mooi-refs/`, never commit them):
`cp-pillBar.png`, `cp-controlCenter.png`, `cp-miniDashboard-calendar.png`, `cp-spotlight.png`,
`cp-wallpaperSwitcher.png`, `cp-powerMenu.png`, `cp-clipboardManager.png`, `cp-mediaPopup.png`, `cp-lock.png`
(ChillPill-Shell) and `di-*.png` (quickshell-dynamic-island). Follow their *language*, in mooi's palette:

- **One body.** The pill (with its modules) is the only thing at rest. Everything else opens as ONE rounded panel
  grown straight down out of the pill (the node's own body morphing into it). Nothing floats beside it: no side
  pills, no orbiting satellites, no spokes, no rings scattered round the node.
- **Inside the panel:** inset cards (`fl.well`, corner 14, 14 px padding), filled rounded buttons in rows, the
  active one lit (accent fill ~0.2 + accent outline), a bold title with a muted line under it, small mono numbers.
- **Real icons:** Nerd Font glyphs (`family: "CaskaydiaCove Nerd Font"`), never words-as-buttons
  ("CALENDAR", "NEXUS" pills are what was rejected).
- **Dynamic theming:** every colour from `fl.*` / `nd_acc` / `nd_glc` (the wallpaper's palette). No fixed colours
  except black shadows.

## Done already (D259)
Modules live in the pill (none → seed); `place` floating / attached (notch drawn by the frame, D257); studio page
"Pill" with the module editor.

## Step 2 — the panel (kind 13, replaces the shelf kind 12 and the branches)
Super at rest (`nd_cmd 1`) and a press on the pill at rest open the panel on its **home** page. Super again, Esc,
or a press on an empty part of the panel closes it. Width 500 for every page; height per page from the logic.
The panel is the node's body (`G.body("panel", …)` sizes) so it grows out of the pill on the body's springs.

**Home page** (top to bottom, see `cp-controlCenter.png`):
1. Media card (inset, h 112): cover 64×64 (corner 10, `nd_cover`), title (sans 14 bold), artist (11 muted),
   on the right ⏮ ⏯ ⏭ as Nerd icons (`󰒮` `󰐊`/`󰏤` `󰒭`), play inside a filled accent circle; a seek bar across the
   card's foot with the two times under it (mono 9). Nothing playing: the card says "Nothing playing" (muted)
   and hides the controls. A press on the cover opens the full player (kind 11).
2. Toggle row (4 equal buttons, h 40): Wi-Fi (`󰖩` + network name, or `󰖪` Off; press: `nmcli radio wifi on|off`),
   Silent (`󰂛`/`󰂚`; press: `pleamar --say mooi "emit note_dnd"`; state from settings
   `notifications.dnd ~= "off"`), Timer (`󰔛` + the running capsule's text or "Timer"; press opens time, kind 8),
   Bluetooth (`󰂯`/`󰂲` On/Off from the `bluetooth` service; press: `bluetoothctl power on|off`). Lit = on.
3. Two sliders: volume (`󰕾`, drag → `audio.volume`) and brightness (`󰃟`, drag → `brightnessctl`, hidden without
   a backlight), each a thin bar with a knob and its % at the right (mono 10). Reuse the D236/D244 debouncing
   (`nd_mt` with stride 2000: meter*2000 + level).
4. Notifications: header "Notifications (N)" (bold 11) + a "Clear all" button (emit `note_clear` to mooi); up to
   three rows (h 52): Nerd icon, app (bold 12), title (muted 11), age (mono 9) right, × dismiss. Row press = the
   notice's default (note_act idx*10), × = note_act idx*10+9. None: one muted line "No notifications".
5. A divider, then the **icon row** (h 44): 󰋜 home · 󰃭 calendar · 󰎞 notes · 󰅌 clipboard · 󰏗 stash · 󰸉 wallpaper ·
   󰍛 system · 󰔛 time · 󰏘 studio · 󰒓 settings · 󰐥 power. The current page lit. Every page shows this row.

**Other pages** reuse the branch contents already written (calendar, notes, clipboard, stash, wallpaper strip,
power) but inside the panel: a header line (‹ back to home + the page's title), content, the icon row. Widths
from `nb_w` (500), never fixed 560 positions. **System page:** a 2-column grid of cards (CPU, RAM, TEMP, NET,
BAT) each with its value and its 20-bar history (D249 graphs style); a press on CPU/RAM/TEMP opens btop (D249).
**Time** opens kind 8; **studio** runs the studio (`nd_cmd 4` path); **settings** runs `mooi settings`.

**Remove** (with their events, models, facts, tests): the shelf (kind 12, `sh` model, `nd_sh`, side pills,
`SHELF`), the floating system cluster (kind 5's spokes/rings/graphs drawing, `sys_style` look row) — the system
lives on the panel page now, satellites (`sa` model, `SAT`, look rows `satellites`/`sat_style`, the Settings row
`node.satellites`; keep `lib/node/satellites.luau` deleted with its tests). Keep: media capsule/visualiser/vinyl,
notices growing as cards (D237/D245), volume gauge, workspace rail styles, launcher, universe, time, player,
privacy/battery cards, reactions.

## Step 3 — the studio only offers what applies
`LK.rows(t, tab)` marks a row `off = true` with `why` text when it cannot matter under the current look, and the
deck draws it dimmed (opacity 0.35) with the reason in place of its description, its zones disabled. At least:
Seed / Seed width / Seed height / Breathing / Clock seed when the pill has modules (form ≠ "seed"); Clock seed
when seed ≠ clock; "From the top" when place = attached; Visualiser (capsule's) when Music as ≠ capsule; Cover when
Music as = visualiser; Roundness note for notch. Test each rule.

## Step 4 — the player like `di-media.png`
Cover large on the left (with title and source over its foot), title/artist, the mirrored spectrum as a wave of
vertical bars in the middle, seek bar with times, transport row (shuffle, prev, play/pause, next, repeat) drawn as
icons, and the three vertical segment meters (VOL, LIGHT, MIC) on the right in their own inset card with their
icons under them. The mixer page and lyrics stay.

## Rules
Pleamar 0.9 scenes are generated by `tools/gen-node.py` (never edit `shell/mooi-node.plm` by hand);
`pleamar --check shell/mooi-node.plm` must say ok. Logic is Luau (`luac5.4 -p` must parse it; no locals used
before their declaration — check with `luac5.4 -l -p shell/mooi-node.luau | grep GETTABUP` that only runtime
globals appear). `bash tests/gate.sh` must pass before every commit. Record each step in `docs/DECISIONS.md`
(D260, D261, …) in the house style. Update `docs/NODE.md` to match.
