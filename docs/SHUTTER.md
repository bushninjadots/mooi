# The Mechanical Shutter

A window's controls, unfolding from its edge (D35). A bracket on the window's corner, an angular
track out of it, four plates down the track, a panel sliding straight out of the plate that is open
and, where a choice needs it, a third level out of its row. Linear and angular, never round.

## Using it

| | |
| --- | --- |
| **Super + Alt + D** | on the focused window (the key is changeable: Settings → Keys) |
| **Super + Alt + right-click** | on the window under the pointer (Settings → Window shutter; right-click alone stays the app's, Super + right-drag stays Hyprland's resize) |
| `bin/mooi shutter` · `bin/mooi shutter-here` | the same, from a script |
| ↑ ↓ | the plates, the rows of the open panel, or the choices of the third level — whichever is deepest |
| Enter · Space · → (← when it opens to the left) | open a plate, act on a row, take a choice |
| Escape · ← (→ when it opens to the left) | one level back; at the plates, put it away |
| a press anywhere else | put it away |

It follows the window while it is out (looked at every 250 ms, only then), and goes when the window
closes. After an action that keeps the window here it stays out and says what happened; after one
that takes it away (another workspace, closed) it goes. A failure stays out, in amber, to try again.

## The plates — every action is checked by reading the window back

| Plate | Actions (only those the window can take now are offered) |
| --- | --- |
| ARRANGE | Maximize / Restore · Fullscreen · Centre and Size… (floating) · Swap… left / right / up / down (tiled) · Float / Tile |
| WORKSPACE | To the previous / next workspace · Move to… · Move and go… (the bar's real workspace map) · Bring here (when it is elsewhere) |
| BEHAVIOUR | Floating · Pinned (floating only) · Opacity… 100 / 90 / 80 / 70 % (read back with `hyprctl getprop`) · Close window (press twice) |
| CONNECTIONS | The folder its program works in (a terminal's: what runs in it): Open folder · Terminal here (kitty) · Copy path · Open repository (its Git root, when there is one) · Other windows of the same app… · Copy title |

Not offered, because Hyprland 0.56 gives no way to check them: pseudo-tiling, always-on-top
(`alter_zorder`), the dwindle split (it acts on the focused window only and cannot be read back).

## Where it goes (lib/shutter.luau `place`)

Outside the window's right edge when the column and an open panel fit there, else its left; when
neither fits (a tiled window filling the screen — the usual case) inside the window's right edge, the
panel opening inward. Everything is held inside the monitor's work area (the monitor less the bar's
strip); a column near the foot slides up, a panel that would leave the screen opens the other way.
Settings → Window shutter: where it unfolds (where it fits · left · inside), standard or compact
plates, open-on-hover, and which plates there are.

## Motion

The anchor answers first; the plates come down the track in a short stagger (~230 ms); a panel
slides out of its plate (~170 ms), the third level out of its row; going, the panel folds first. The
speed setting (Motion & effects) scales it with everything else; reduced motion settles it at once.

## Files

`shell/lib/shutter.luau` placement and the action registry (pure, unit-tested) ·
`shell/shutter.luau` the controller · `shell/lib/hypr.luau` the commands and their checks ·
`shell/mooi.plm` `shutter_surface` and the keys · `shell/ui/ferrolume.plm` ShPlate, ShRow, ShItem,
ShHousing · `shell/icons/{arrange,workspace,behaviour,connections}.svg`.

## Limits

- Which monitor's copy draws it is matched by index: Hyprland's monitors in id order, taken to be the
  outputs' own order (this Pleamar does not let a surface compare its monitor's name).
- The working directory is the newest process under the window's (for a terminal, what its shell
  runs); a program that keeps its folder elsewhere shows its own.
- Plate order is fixed; plates can be turned off.
