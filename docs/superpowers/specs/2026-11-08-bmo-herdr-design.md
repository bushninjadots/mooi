# BMO in the bar, and Herdr beside him — design

> Status: design approved in conversation (2026-11-08), awaiting review of this written spec.
> Proposed decisions: **D209** (BMO, one shared) and **D210** (Herdr).
> Builds on: the Pill's BMO (D169/D170/D196), the living desktop companion (`shell/bmo/`), and the
> Sigil/Surface host work (D207/D208). Replaces nothing; the Sigil's `bmo` source stays.

## 1. What the owner asked for

The owner already has BMO twice: as a source inside the Sigil in the bar, and as a living desktop
companion that walks, talks and gets into things. They want a third form:

> "i also want as a normal module an actual face of bmo that has all the features the others have."

Then, in the design conversation:

> "yes eyes follow he can react to all sorts of things, and yes island he mustbe like a pet
> tamagochi, needs quick settings, click and hold to charge and he expresses it, chat, yes they must
> be 1 shared, also i can ask him to do things like start programs/apps/find information, can explore
> my files and edit if needed, change my settings, and yes interact with things like what app opens
> or what kind of website im on, he has grumpy emotion i want it bit more grumpy/angry and he can be
> a little naughty cheeky as i mean 18+ stuff. and yes look for herdr module and build too."

And on Herdr:

> "everything is perfect nce. also herdr can give small brief of what hes doing currently"

The owner approved the click map and architecture in conversation before this document was written.

## 2. The two things being built

1. **BMO, the bar module.** A normal `bmo` module in every bar layout: his actual animated face at
   the bar's height, placeable and removable in edit mode, with a frame look, show/hide, settings,
   hover, tooltips and an island. He is one pet across the bar, the desktop and the Pill: one mood,
   one charge, one memory. Clicking him opens a tamagotchi island where he can be charged, petted,
   played with, talked to, and asked to do things.
2. **Herdr, the bar module.** A normal `herdr` module that is quiet until a coding agent needs you.
   Its island groups agents into **Needs attention / Working / Idle**, shows a short brief of what
   each is doing, and focuses or attaches to them. It is the Pleamar version of
   `io.github.eszanon.herdr`, improved: live counts, elapsed time, project/branch, cached briefs,
   keyboard navigation, and BMO reacting when an agent blocks.

BMO is built first. Herdr reuses the same module, island, settings and test patterns; its plan is a
second phase of the same work.

## 3. Goals, non-goals, anti-goals

**Goals**

- A face that looks better than the Pill's current BMO: the same BMO geometry, drawn larger and
  cleaner, with eye tracking, blinking, a charge ring, a live expression, and a little body language.
- One BMO. Mood, charge, bond, mischief, grump, chat, asleep, reaction and current speech are the
  same whether seen in the bar, on the desktop, in the Pill or in the Sigil.
- A real pet loop: charging, petting, playing, chatting, poking, neglect, sleep, overcharge,
  grumpiness and mischief all change him and are visible.
- Safe hands: he can look, open things and change things in tiers, with confirmation for anything
  destructive.
- A Herdr island that tells you, at a glance, who needs you and what they are doing, without
  reading terminal content into logs or keeping a heavyweight UI open.
- All of it works on every monitor, survives a bar restart, and degrades to a plain face if the
  shared files are missing.

**Non-goals**

- BMO is not a general coding agent. He does not replace Claude Code, opencode or Herdr.
- He does not read terminal scrollback for chat context, passwords, tokens, browser cookies or
  private keys.
- The bar module is not a second desktop BMO; it does not walk, get dragged around the screen, or
  draw a full panel. Those remain the desktop companion's body.
- Herdr does not manage agents (start, stop, prompt) in this phase. It observes and focuses/attaches.
- No browser extension, so no exact URL. "What kind of website" comes from the active window's
  class and title, and the design says so plainly.

**Anti-goals** — things that would make this a failure even if it works:

- Two BMOs that disagree about mood or charge.
- A face that stutters or repaints the whole bar every frame.
- An assistant that can silently rewrite files, run arbitrary shell commands, or read secrets.
- An island that steals the keyboard from the window below while closed.
- Herdr polling that hammers the CLI or reads every terminal every few seconds.
- Settings that cannot be undone, or setter codes inserted in the middle (append-only).

## 4. What exists today

- `shell/lib/barlayout.luau` owns `MODULES`, `ORDER`, `INDEX`, `DEFAULT`, widths, layout and edit
  drop codes. `ORDER` ends with `sigil`; its edit code is 32. `DEFAULT` is full at 1920.
- `shell/bar.luau` runs the bar's logic, writes module facts (`x_`, `p_`, `w_`, `g_`, `fi_`) and
  currently feeds the Pill's BMO through `lib/pillface` and `pb_*` facts.
- `shell/mooi.plm` declares the bar scene: module facts, spring props, module groups and zones,
  edit-mode zones, and island content. It already imports `ui/pill.plm`, uses `cursor.x/y`, and has
  `on release` zones.
- `shell/ui/pill.plm` has `Pill.BmoFace`, `Pill.BmoScreen` and `Pill.BmoMark`. `BmoFace` draws the
  96×66 face (50×34 screen) from `pb_*` facts.
- `shell/bmo/bmo.luau` is the desktop body: movement, panel, games, body-local energy, mood display,
  position (`bmo-state.json`). `shell/bmo/brain.luau` is the pure personality (moods, `FACES`,
  `poke`, `drift`, `chatter`, `energy`). `shell/bmo/wire.luau` encodes text as one safe token.
- `shell/lib/claude.luau` runs Claude tool-less for chat and BMO; `shell/lib/pillface.luau` is a
  separate BMO-in-Pill state machine. The bar and the desktop do not share state today.
- `bin/mooi` symlinks the `bmo` scene's data folder to `mooi`'s, so both programs read and write the
  same `settings.json`, `bmo-state.json` and any new shared files.
- `tools/gen-settings.py` generates the settings scene from `MODULES`; generated files are edited
  only through the generator. Setter codes in `shell/lib/setters.luau` are append-only.

## 5. Approaches considered

### 5.1 One BMO

**A. One owner, many bodies (chosen).** The bar owns the pet's state and writes it to shared files;
the desktop body, the Pill and the Sigil only read it and send intents. The desktop keeps its own
position and animation, but not its own mood. Survives the desktop being closed. Costs one small
state file and no election, because `mooi.plm` is one scene with one logic process for every monitor
surface (D34).

**B. The desktop BMO owns everything.** Simplest conceptually, no lease. Rejected: closing the
desktop companion would freeze the bar's pet, and a bar could show a different BMO while the
desktop starts.

**C. Every bar keeps its own BMO.** No shared files. Rejected outright: it produces several BMOs
that disagree, which is exactly what the owner asked not to have.

**A** is the only one that keeps one pet with the desktop optional. There is exactly one writer,
so consistency needs no clock agreement and no election.

### 5.2 Hands

**A. A permissioned action bridge (chosen).** Claude answers with a short JSON object containing
words and, optionally, one action. A pure `bmoact` module validates the action against an allowlist
and a tier; the bar executes it. The model never gets Bash/Edit tools.

**B. Give Claude Code real tools.** Powerful and quick to wire, but it destroys the "asked lean, no
tools" safety property and lets a chat turn edit files or run commands with the user's authority.
Rejected.

**C. A menu of fixed commands only.** Safe but not what was asked; cannot "find that PDF" or
"change my settings" in natural language. Rejected as the only mode; it survives as the fast path
for common intents.

### 5.3 Herdr

**A. Poll `herdr api snapshot` on a timer, cache briefs (chosen).** Works with the CLI already
installed, no socket client in Luau, easy to unit-test. 2–3 s poll; briefs cached 8–10 s and fetched
only for visible/blocked agents.

**B. Subscribe to Herdr's event socket.** Lower latency, but Pleamar/Luau has no socket client; it
would need a helper process. Rejected for this phase; the polling contract leaves room for a later
`herdr-feed` helper.

**C. Copy the Omarchy plugin's 5 s poll and layout.** Works, but slower, no briefs, no elapsed time,
and no BMO reaction. Rejected as the baseline; kept as prior art.

## 6. Architecture: one owner, many bodies

### 6.1 One writer

`mooi.plm` is one scene with one logic process; every monitor surface is a copy of that scene, not a
separate bar logic (D34). So the bar is the single owner and there is no leader election, no lease,
and no follower path. The desktop body is the only other writer, and it writes only its own body
state and intents.

- The bar writes `bmo-shared.json`, `bmo-chat.json` and `bmo-actions.json`.
- The desktop body writes `bmo-body.json` and `bmo-cmd.json`; it never writes the shared pet state.
- The Pill and the Sigil are views: they read what the bar already exposes as facts/feeds.
- If the desktop body is not running, the bar still owns the pet; the body's last record is marked
  `running = false`.
- If a future bar grows one process per monitor, this design adds a lease then; it does not need one
  now.

### 6.2 Intent queue

The desktop body, or any part of the bar, can ask for something. The intent goes into
`bmo-cmd.json` as one object with a unique id:

```json
{ "id": "bmo-<boot>-<n>", "at": 1760000000, "kind": "poke", "arg": {} }
```

The bar watches the file and applies each id once (the last seen id is kept in
`bmo-shared.json.last_cmd`). The writer also watches for the resulting `rev` change; if no change
arrives in 800 ms it retries once. This is deliberately a single-slot queue: pet interactions are
human-paced, and a lost duplicate is better than a double action.

Kinds: `poke`, `pet`, `play`, `nap`, `charge_start`, `charge_stop`, `charge_step`, `chat`,
`confirm`, `dismiss`, `quick_setting`, `set_mood`, `react`, `summon`, `panel`, `say`,
`herdr_blocked`. Body-local controls (size, place, motion, panel tab, carry) stay local to the
desktop body and do not pass through the queue; they are not pet state. Mood buttons, awareness
reactions and the game's mood changes are proposals and do pass through.

### 6.3 Files

All in the shared mooi data folder (already shared with the desktop by `bin/mooi`'s link):

| file | writer | readers | what |
|---|---|---|---|
| `bmo-shared.json` | bar | desktop, Pill/Sigil feeds | the pet's whole state |
| `bmo-body.json` | desktop body | bar | where the body is and what it is doing |
| `bmo-chat.json` | bar | desktop, all bars | last 24 turns, streaming text, busy |
| `bmo-actions.json` | bar | all bars | last 50 actions, undo refs, confirmations |
| `bmo-cmd.json` | bar or desktop | bar | one intent |
| `bmo-state.json` | desktop body | desktop body | existing x/y/mon position, unchanged |
| `herdr-seen.json` | bar | bar | first-seen status transitions, for elapsed time |

Writes are whole-document writes (Pleamar's `files.write`) and consumers use `sys.watch` on the
name. The bar writes `bmo-shared.json` at most every 2 s during idle decay, immediately on any
interaction, mood change, speech or reaction. `rev` still increments on every write, so a view can
tell a stale read from a fresh one; it is not used to arbitrate writers.

`bmo-shared.json` v1:

```json
{
  "version": 1, "rev": 184, "at": 1760000000, "owner": "eDP-1:...",
  "charge": 0.62, "bond": 0.41, "mischief": 0.58, "grump": 0.12,
  "mood": "playful", "asleep": false,
  "reaction": { "face": "giggle", "until": 1760002600 },
  "say": { "text": "charge me, human", "until": 1760002400 },
  "last": { "pet": 1760001000, "play": 0, "chat": 1760000500, "poke": 1760002000, "charge": 1760001900 },
  "last_cmd": "bmo-...",
  "context": { "class": "firefox", "title": "…", "kind": "browser" }
}
```

`bmo-body.json` v1: `{version, rev, at, running, x, y, mon, activity, tab, panel, speaking, bubble}`.

### 6.4 Pure modules

| module | does | tested |
|---|---|---|
| `shell/lib/bmostate.luau` | the pet's state machine: create/migrate, apply an intent, tick decay, derive mood/reaction, view for drawing | yes, no timers |
| `shell/lib/bmoact.luau` | parse a model reply into `{say, action}`, validate action kind and tier, describe a confirmation | yes |
| `shell/lib/bmochat.luau` | chat turn list, prompt assembly, action protocol prompt, streaming state | yes |
| `shell/lib/bmo/hands.luau` | the allowlist, path safety, setting whitelist, argument shapes | yes |
| `shell/lib/herdrfeed.luau` | parse `herdr status`/`api snapshot`, group rows, elapsed, sanitise a brief | yes |
| `shell/bmo/brain.luau` | existing faces and personality; gains new faces and grump/mischief weights | yes (existing tests) |

`bar.luau` stays the only place that runs processes, touches facts and writes files. The pure
modules never call `run`, `sys.ask`, `fact` or `after`.

### 6.5 Timing and failure

- Bar tick: 1 s in memory; state persisted at most every 2 s when idle, immediately on an event.
- Desktop body: reads `bmo-shared.json` on watch; reports `bmo-body.json` when position, activity or
  panel changes, throttled to 250 ms.
- Missing or corrupt `bmo-shared.json`: the bar creates a fresh pet from defaults and keeps going;
  a corrupt file is copied to `bmo-shared.bad.json` once, never written over silently.
- One writer: the bar. A desktop body that comes up stale only reads the shared state and sends
  intents; the bar applies each intent id once, so no pet action is duplicated.
- Desktop BMO off: the bar and Pill remain fully alive; the desktop's last body state is marked
  `running = false`, and the island says "he's asleep on the desktop" rather than showing stale
  movement.
- No `herdr` binary: the module is absent (`needs = "herdr"`), no errors. Herdr server down: the
  module can still be placed, and the island shows a clear warning card.

## 7. The face in the bar

### 7.1 Shape

- New module id `bmo`, appended to `barlayout.ORDER` after `sigil`; edit code **33**.
- Width: 64 px (a fixed slot; the face scales inside it). Keeps the 1920 default fit test unchanged
  because the module is not in `DEFAULT`; it starts on the shelf with `show = true` so it is one
  drag away, not absent.
- Height: the bar's module height. The face is drawn in the existing 96×66 units scaled to
  `min(fl.mod_h - 4, 40)` high, centred, with a 2 px bezel. At a 30 px bar the face is about 36×25;
  at 44 px it is about 52×36. The module never clips the face.
- A new `Pill.BmoModule(w, h)` component draws the shell around `Pill.BmoFace`: rounded mint bezel,
  inner glass, a faint outer glow in BMO's current palette, and the charge ring around the screen.
  It is the same face people already know, not a new mascot.

### 7.2 Motion

- **Eyes follow the pointer** wherever it is on the monitor, using the same `follow pb_lx/ pb_ly`
  maths the Pill uses. The gaze is clamped at the glass edge.
- **Blink** on the shared state's idle timer; a double blink when he wakes.
- **Breathe/bob** on a slow spring; a small hop on a new reaction; a squash on poke.
- **Charge ring** fills while charging; the face climbs sleepy → happy → excited → jittery →
  overcharged; past the top he goes cross-eyed, burps a little pixel cloud, and slumps into `dizzy`.
- **Expression** is always the shared state's face. Local hover does not change mood; it may add a
  tiny lean or a side-eye.
- **Reduced motion**: the setting stops the bob, hop and ring overshoot; expression changes are
  instant.

### 7.3 Pointer and actions

| input | what happens |
|---|---|
| hover | eyes track; tooltip `BMO · 62% · cheeky` (charge · mood); a faint highlight |
| left press, held < 450 ms | island opens under the module |
| left press, held ≥ 450 ms | charge starts; release stops it; the island does **not** open on release |
| middle press | poke (one giggle, many a grumble; the desktop and island react too) |
| right press | summon/focus the desktop BMO: if running, send `emit ui 1`; else ask `mooi.luau` to start it |
| double press | island opens on the Chat tab |
| keyboard focus + Enter | island opens on Care |

The press/release split lives in `bar.luau`: `on press z_bmo` starts a 450 ms timer and emits
`bmo_press`; `on release z_bmo` emits `bmo_release`. The logic decides whether it was a tap or a
hold. Scrolling over the face steps the charge down/up in small amounts (`charge_step` intents) when
he is awake.

### 7.4 The tooltip

A small rounded label under the module, drawn in the bar's surface, shown while hovered:
`BMO · 62% · cheeky`, plus `⚡ charging` while held, or `"your agent needs you"` when Herdr has a
blocked agent. It never covers the face.

## 8. The island

One island slot is added: `open` gains `bmo`. Width ~380, height ~460, anchored under the module
and clamped to the screen, like the weather/stats islands. It has three tabs across the top and a
persistent quick-settings strip at the bottom.

```
╭─ BMO ───────────────────────────────────────╮
│   ◉◡◉      BMO            ⚡ 62%   [ring]   │
│            mood: cheeky · bond ▓▓▓░        │
│   charge ▓▓▓▓▓▓░░░░   mischief ▓▓▓▓░       │
│   grump  ▓░░░░░░░░░                        │
├────────────────────────────────────────────┤
│  [ Care ]   [ Chat ]   [ Do ]              │
│                                            │
│  Care:                                     │
│   [ Charge ] [ Pet ] [ Play ] [ Nap ]      │
│   last: petted 3m ago · charged 5m ago     │
│   "you could charge me. just saying."      │
│                                            │
│  Chat:                                     │
│   BMO: hi!                                 │
│   you: what's on my screen?                │
│   BMO: a browser, and a very long title.   │
│   [ Ask BMO something…              ]      │
│                                            │
│  Do:                                       │
│   [ open kitty ] [ find my PDFs ]          │
│   pending: "write ~/.config/…"?            │
│   [ Show diff ] [ Yes ] [ No ]             │
├────────────────────────────────────────────┤
│ eyes ✓  companion ✓  music ✓  cheek 2      │
│ doze ✓  herdr ✓  hands: balanced           │
╰────────────────────────────────────────────╯
```

- **Care**: the face, charge, stats, four care buttons, last-interaction lines, and one current
  quip. Holding Charge charges (same 450 ms rule as the module); tapping Pet/Play/Nap applies the
  intent. Pokes are not a button — poking is done by clicking the face itself; the island face is
  also pokeable.
- **Chat**: the last turns (BMO / you), a busy indicator, an input field, and the action protocol's
  results inline. Enter sends; Esc closes the island; the input keeps focus until the island closes.
  History persists across restarts (`bmo-chat.json`), capped at 24 turns.
- **Do**: suggested actions and the pending confirmation card. "Look" actions complete immediately
  and show a one-line result. "Do" actions run and show an undo toast. "Change" actions show a diff
  or exact command; nothing runs until Yes. The card has an expiry bar (60 s), and No/dismiss is
  always available.
- **Quick settings** (always visible): `eyes`, `companion`, `music`, `cheek`, `doze`, `herdr`,
  `hands`. Each is a chip that writes the matching setting and immediately updates the shared state.
  Long labels get a compact form; a tooltip explains each.
- **Context line**: under the header, `browser · "Some page title"` or `herdr · 2 working`, from the
  same context watch. It is informational, never a claim about an exact URL.
- **Accessibility**: all chips and buttons are zones with labels; Tab/Shift+Tab walk them, Enter
  activates, Esc closes; reduced motion respected.

### 8.1 Opening and closing

The island opens on left tap or double-click Chat. It closes on Esc, a click outside, or the face
being tapped again. Opening it does not move the desktop BMO. If the desktop BMO is open, the island
still opens in the bar; they share state but not position.

## 9. The pet: state, mood and mischief

### 9.1 Stats

- **charge** 0–1. Drains awake (~2 h to empty), faster at night; refills while charging or asleep
  (~10 min). Low charge makes him sleepy then grumpy.
- **bond** 0–1. Grows with petting, playing, chatting and being charged when he asks; decays very
  slowly. High bond unlocks affectionate lines and softer grump.
- **mischief** 0–1. Grows with play and poking; decays. High mischief gives harmless pranks: a
  side-eye, a fake error on his screen, moving a pixel, a cheeky line. Never destructive.
- **grump** 0–1. Grows with over-poking, low charge, neglect, being woken, and a blocked agent when
  he is already tired. Decays with care. Grump is the main new visible axis: the owner asked for
  more grumpy/angry.
- **mood** is chosen from the stats and the last event, using `brain`'s moods and the new weights.
  More grumpy/angry than today; still not the default.

### 9.2 Charging

- Hold the face or the Charge button; `charge_start` sets `charging = true`; the bar adds
  `dt / CHARGE_MS` each tick. The face climbs through expressions; at 1.0 the ring pulses, he says
  "full!", and holding further goes to `overcharge` for 6 s: cross-eyed, burp, `dizzy`, then a small
  grump. Releasing stops immediately and saves.
- Charging while asleep wakes him gently; charging a grumpy BMO softens him.
- The ring and expression are drawn from `charge`; the state file is the only source.

### 9.3 Poking, petting, playing, sleeping

- Poke: `brain.poke` gains a grump/mischief input. 1–2 pokes: giggle/curious. 3–4: "hey!" and a
  shake. 5+: tantrum/angry, grump up. Over-poking while grumpy raises grump and may make him turn
  his back for a minute.
- Pet: bond up, grump down, content/happy; a small chance of a purr-like hum.
- Play: a 30–90 s mini-moment (chase the cursor, a tiny game on his screen, dance); mischief up,
  charge down a little, bond up.
- Nap/doze: `companion.doze` still controls automatic dozing; the island's Nap puts him to sleep now.
  Asleep: charge fills, grump decays, waking early raises grump slightly.
- Neglect: no interaction for a long time → sleepy, then grumpy; he may say something when you
  return.

### 9.4 Speech and cheek

- Speech still uses `wire.luau` for transport. The message goes to the shared `say` field with an
  expiry; the bar, desktop and Pill all show it.
- The **cheek dial** is `companion.cheek`: `Off`, `Tease`, `Flirty`, `Unfiltered`.
  - Off: kind, cute, no swearing, no innuendo.
  - Tease (default): playful sarcasm, mild swearing, cheeky jokes.
  - Flirty: flirtatious innuendo, adult jokes, bratty teasing.
  - Unfiltered: stronger profanity and sexual innuendo; still no explicit sexual content, no slurs,
    no harassment, and nothing non-consensual. This is a tone setting, not a content generator.
- If the owner asks for something outside that boundary, BMO deflects in character and the island
  says so once.
- The persona prompt is extended with the cheek level and the pet's current stats, so the words and
  the face agree.

### 9.5 New faces

`brain.FACES` gains a few rows so the new states read clearly: `smug` (one brow, half-lidded),
`wink`, `bored` (flat lids), `lovestruck` (heart-ish shine / blush), and `overcharged` (cross-eyed,
wide). Existing faces keep their names and numbers. `BmoFace` learns `wink` via `pb_lid` per-eye and
`overcharged` via `pb_sql/pb_sqr`; no new drawing library.

## 10. Hands: look, do, change

### 10.1 The protocol

Claude still runs tool-less through `lib/claude.luau` with the `bmo` persona. The prompt asks for
one JSON object and nothing else:

```json
{ "say": "opening kitty", "action": { "kind": "open_app", "arg": { "name": "kitty" } } }
```

`lib/bmochat` parses it tolerantly: plain text is allowed (no action), fenced JSON is unwrapped, an
unknown kind becomes a spoken refusal. Only one action per turn. The model is told the action
schema, the current tier, and the context line. It is told never to claim an action succeeded; the
bar appends the result as a system line.

### 10.2 Tiers

| tier | actions | behaviour |
|---|---|---|
| **Look** | `get_context`, `search_files`, `read_file`, `list_dir`, `get_setting`, `herdr_list`, `herdr_read`, `web_fetch` | run immediately, result returned to the next model turn (max 3 loops) |
| **Do** | `open_app`, `open_url`, `focus_window`, `media`, `notify`, `set_setting` (safe list) | run immediately; show a one-line result and an Undo where possible |
| **Change** | `write_file`, `run_command`, `set_setting` (other keys), `delete_file` | never run immediately: show a confirmation card with a diff or the exact command; wait for Yes |

- `companion.hands`: `Off` (chat only), `Look`, `Balanced` (default: Look + Do, Change confirms),
  `Trusted` (Change runs but still shows the exact action and an undo; no sudo ever).
- Path safety: only under `$HOME`, never `~/.ssh`, `~/.gnupg`, `~/.local/share/keyrings`,
  browser profile/cookie stores, `*.pem`, `*.key`, `*.kdbx`, `bmo-secrets*`; no symlink escape; no
  writes outside the allowed roots. Reads of `settings.json` are allowed, but secrets in it are
  redacted from the model's view.
- `run_command` is a single command string, no shell metacharacter chaining except what is printed;
  never `sudo`, `doas`, `pkexec`, `rm -rf`, `dd`, `mkfs`, `shutdown`, `reboot`, or anything that
  writes outside `$HOME`. A command that fails the allowlist is refused with a reason.
- Every action appends to `bmo-actions.json`: `{id, at, tier, kind, arg, result, undo}`. Undo is
  available for the last Do action and the last Change within its expiry.
- Confirmations expire after 60 s; a new Change replaces the pending one; Esc dismisses.
- The model never sees file contents it did not explicitly read, and nothing is sent to a network
  service except the URL explicitly fetched.

### 10.3 Context

- Active window: `hyprctl -j activewindow` → class, title, workspace. Browser classes map to a
  `browser` kind; the title is cleaned of the browser suffix. The island shows the title, not a URL.
- Herdr: `herdr api snapshot` gives agent count/status and titles. BMO can mention "3 agents, one
  blocked" only if `companion.react.herdr` is on.
- Media: current song/artist; battery: percent/charging; workspace: id/name.
- The context is written into `bmo-shared.json.context` at most every 5 s, and sent to the model as
  a short line, not as a transcript.

### 10.4 Execution

The bar executes actions with `run`/`spawn`. Pleamar's `files` service is sandboxed to the mooi data
folder, so it is used for BMO's own files only. Look actions use `rg`, `fd`, `ls`, `cat` (with a byte
cap), `hyprctl`, `herdr`, `curl`; Do actions use `hyprctl dispatch`, `xdg-open`, `playerctl`,
`notify-send`, settings writes through `lib/setters`; Change actions write a temp file in the mooi
data folder, show a diff preview, back up the target to `bmo-backups/`, then `cp`/`mv` into place (or
`rm` for delete). Paths are resolved and checked under `$HOME`, symlinks are not followed out of it,
and secret-looking paths are refused. All results are appended to chat as a system line and to
`bmo-actions.json`. Execution is asynchronous; the island shows a spinner until the result arrives.

### 10.5 What BMO will not do

No credential entry, no password manager, no reading browser history/cookies, no sending local file
contents anywhere, no sudo, no disabling the firewall, no installing packages, no changing login
shells or SSH keys. If asked, he says no in character and offers the safe alternative.

## 11. Reactions and awareness

The shared state receives events from `bar.luau`'s existing watches and from `mooi.luau`:

- workspace change → curious (0.5 s)
- new window / focus change → curious or focused; browser title becomes context
- notification → surprised, then excited; a line if cheek allows
- music start/change → excited or singing; dance if the desktop body is out
- battery low / charging → sleepy/grumpy or happy
- Herdr blocked count rises → exclamation, a line ("your agent needs you"), tooltip
- focus block starts/ends → focused / content
- idle for a long time → doze; return → a look
- being poked/charged/petted → the pet reactions above

Reaction faces are short (`reaction.until`), then the mood returns. Reactions never overwrite the
mood. The island shows the current reaction as the face.

## 12. One BMO in the desktop body and the Pill

### 12.1 Desktop body

`shell/bmo/bmo.luau` keeps its movement, panel, drag/throw, games and position. It gains a small
bridge:

- It reads `bmo-shared.json` on `sys.watch`; `mood`, `charge`, `reaction`, `say`, `asleep` and
  `grump` replace its local copies.
- It writes `bmo-body.json` when its position/activity/panel/tab changes (throttled 250 ms), and
  keeps `bmo-state.json` for where it stands.
- Its poke/panel controls send intents (`poke`, `panel`, `quick_setting`, `chat`) instead of
  mutating mood directly. Its own `brain` calls remain for animation choices, but results are
  proposals sent to the bar; the bar's state wins.
- The CHAT tab becomes a view of `bmo-chat.json`: the desktop sends the prompt as a `chat` intent
  and renders the stream the bar writes. The old `nt_bmo_q`/`mooi-notch` path is retired for BMO
  (the notch keeps its own separate Claude conversation). No history is auto-imported; BMO starts the
  shared thread with a greeting, so there is exactly one memory going forward. Streaming and the
  free-model fallback stay in the bar path.
- The existing panel's tabs and quick settings stay. The shared file is the source of truth; the
  panel writes `companion.*` through its existing `save_companion`.
- When the desktop body starts, it adopts the shared mood/charge. If no shared file exists, it shows
  a default face and waits for the bar; it never creates the shared pet itself.

### 12.2 Pill and Sigil

- The Pill's BMO face (`lib/pillface`) becomes a view: it reads the shared mood/reaction/say and
  keeps its typing/bump timers. Its independent `DRIFT_MS`/`SLEEPY_MS` mood choice is removed; the
  shared state decides sleep and drift. Its `poke`/`touch` send intents to the bar (the bar owns
  changes); no second copy of mood exists.
- `bar.luau`'s `face_show` sets `pb_*` from the shared view (with `pillface` for the animation
  counters), so the Pill, the module and the desktop agree.
- The Sigil's `bmo` source reads the same shared view through the bar's facts/feeds, so its line
  expression matches.
- If the shared file is missing, `pillface` falls back to today's behavior; the module shows a
  default face and a "waking up" tooltip.

## 13. Settings

All new settings are defaults plus validation in `lib/config.luau`, rows/pages in
`tools/gen-settings.py`, and setter codes appended at the end of `lib/setters.luau` (never inserted).
The generated settings scene is regenerated, not hand-edited. `tools/gen-settings.py`'s `MODULES`
gains `bmo`, `herdr`; `NAMES` gains "BMO", "Herdr". `barlayout.ORDER` gains them in the same order.

**Companion (existing page, extended):**

| key | kind | default |
|---|---|---|
| `companion.eyes` | boolean | true |
| `companion.cheek` | enum Off/Tease/Flirty/Unfiltered | Tease |
| `companion.hands` | enum Off/Look/Balanced/Trusted | Balanced |
| `companion.react.herdr` | boolean | true |
| `companion.react.browser` | boolean | true |
| `companion.react.battery` | boolean | true (existing react table) |

`companion.bmo`, `companion.size`, `place`, `above`, `variant`, `wander`, `motion`, `talk`, `throw`,
`locked`, `music`, `clock`, `doze` stay as they are. `bar.modules.bmo.show/frame` are auto-added by
`config.luau` when `bmo` joins `ORDER`; the module starts `show = true` but not in `DEFAULT`, so it
is on the shelf.

**Herdr (new page):**

| key | kind | default |
|---|---|---|
| `herdr.path` | string | `herdr` |
| `herdr.poll` | number 2–10 s | 3 |
| `herdr.show_idle` | boolean | false |
| `herdr.show_done` | boolean | false |
| `herdr.brief` | boolean | true |
| `herdr.brief_lines` | number 2–8 | 4 |
| `herdr.focus_on_open` | boolean | false |

`bar.modules.herdr.show/frame` auto-added; not in `DEFAULT`, on the shelf. `needs = "herdr"` and
`ctx.herdr` in `barlayout.present` hide it when the binary is absent.

## 14. Herdr: the module and island

### 14.1 Feed

`lib/herdrfeed.luau` (pure):

- `M.status(doc)` → `{running, compatible, version, socket, restart_needed, problems}`.
- `M.snapshot(doc)` → `{agents, focused, workspaces, tabs, error}`; sanitises fields, keeps only
  `pane_id`, `agent`, `agent_status`, `terminal_title`, `cwd`, `foreground_cwd`, `workspace_id`,
  `tab_id`, `state_change_seq`, `completion_seq`, token count when present.
- `M.group(agents, now, seen, meta, opts)` → `{attention, working, idle, done}`, each a sorted list
  (blocked first, then working by oldest state change, then idle), with
  `elapsed = now - seen[key]` when the bar has observed a transition, and `branch` from `meta` when
  known. Unknown agents go to idle with an "unknown" marker.
- Elapsed has no timestamp in Herdr's API; the bar records `seen[pane_id..":"..status] = now` on the
  first observation of each status, in memory and in `herdr-seen.json` (reset when a pane disappears).
  Elapsed is shown as ">2m" rather than a precise figure when the record is older than the bar's run.
- Branch is not in the snapshot. While the island is open, the bar runs
  `git -C <cwd> branch --show-current` for visible rows, caches it for 30 s, and hides the column
  when git or the branch is unavailable.
- `M.brief(title, text, cols)` → first meaningful line: title, then the last non-empty output line
  with ANSI stripped, whitespace collapsed, truncated to 120 chars. No prompts, no full
  transcripts, no secrets heuristics beyond stripping common token patterns.
- `M.warn(status, snapshot)` → `nil` or a short string for server down/incompatible/restart.

`bar.luau` polls `herdr status --json` at start and every 30 s. It polls `herdr api snapshot` every
`herdr.poll` seconds (default 3) whenever the module is placed or its island is open. When the module
is unplaced but `companion.react.herdr` is on, it still polls at `max(herdr.poll, 5)` so BMO can react
out of the box. Briefs are cached per `pane_id` for 8 s, fetched one at a time for the first
blocked/visible rows, and only when `herdr.brief` is on. The bar sets facts: `hd_up`, `hd_warn`,
`hd_blocked`, `hd_working`, `hd_idle`, `hd_total`, `hd_brief`, `hd_version`, `hd_pulse`.

### 14.2 The module

- Width 56, height as the bar. Quiet state: a small terminal/agent glyph and a dot; no count when
  zero. Blocked state: the dot becomes amber, a count appears, and the module pulses once when the
  count rises. Working: a thin progress tick. Server down: a dim warning glyph.
- Tooltip: `Herdr · 2 blocked · 3 working`, with the first blocked agent's brief on a second line.
- Click opens the island; middle click focuses the first blocked agent; right click attaches to it
  in a terminal; hover shows the tooltip.
- `needs = "herdr"`; absent binary means no module and no errors.

### 14.3 The island

Width ~420, height ~460, anchored under the module. Header: `Herdr` + version + counts + load meter
(working/total) + a server warning card when needed. Groups:

```
NEEDS ATTENTION
  ● claude   ~/Projects/mooi   main        blocked 2m   "waiting for approval"
  ● codex    ~/Projects/site   feat/x      blocked 5m   "tests failed, retry?"

WORKING
  ● opencode ~/Projects/mooi   main        working 12m  "editing bar.luau"

IDLE
  ○ claude   ~/Projects/notes  —           idle 1h      "ready"
```

Each row: vendor mark (claude/codex/opencode/terminal), agent name, project basename, branch if
known, status dot, elapsed, and the brief. Click focuses (`herdr agent focus <pane_id>`) and then
raises the matching Hyprland window: the bar matches `terminal_title`/`cwd` against `hyprctl -j
clients` and focuses the client through `lib/hypr`; if no window matches, it opens
`kitty -e herdr agent attach <pane_id>` instead, so the click never looks like nothing happened.
Right click attaches in a new terminal; middle focuses and raises the first blocked; `r` refreshes;
Esc closes; `h/j/k/l`/arrows move, Enter focuses and raises, `a` attaches. Wheel scrolls when there
are more than 6 rows; a `+N more` line shows the rest. `show_idle`/`show_done` hide those groups. The
island never reads terminal content unless `brief` is on and only for visible rows; briefs are
cached, so a blocked agent's text is not polled every second.

### 14.4 BMO and Herdr

When the blocked count rises, the bar applies `herdr_blocked` (throttled to once per 20 s per
agent) with the agent and brief. BMO reacts with `surprised`/`focused`, says a short line if his
cheek and current mood allow, and the tooltip shows the first blocked brief. When it clears, he
relaxes. This is a reaction, not a notification replacement; the notification system still owns
notifications.

## 15. Phases

**Phase 1 — one BMO and the bar face.**
`bmostate`, shared/body files, `bmo` module in barlayout/mooi.plm/edit mode, the
`BmoModule` face, hover/poke/charge, tooltip, island Care + quick settings, desktop body bridge,
Pill view. No chat/actions yet. This is the visible win.

**Phase 2 — chat and hands.**
Chat tab, `bmochat`, `bmoact`, `bmo/hands`, Look/Do/Change, confirmations, action log, context line,
cheek levels, new faces, richer reactions.

**Phase 3 — Herdr.**
`herdrfeed`, module, island, briefs, focus/attach, BMO reaction, settings page.

Each phase lands with its own tests and a commit; the design is one document because the pieces
share the module/island/settings shapes.

## 16. Integration checklist (the parts that bite)

- `barlayout`: append `bmo` and `herdr` after `sigil`; edit codes 33 and 34; widths; no `DEFAULT`
  change; `INDEX` follows automatically.
- `bar.luau`: names in `NAMES`; event handlers (`bmo_press`, `bmo_release`, `bmo_cmd`, `bmo_chat`,
  `bmo_confirm`, `bmo_quick`, `bmo_summon`, `bmo_panel`, `herdr_*`); facts; watch files; poll
  Herdr; `herdr-seen.json`; release/cleanup on settings change.
- `shell/bmo/bmo.luau`: desktop body reads `bmo-shared.json`, writes `bmo-body.json` and intents;
  CHAT tab becomes a view of `bmo-chat.json` and stops emitting `nt_bmo_q` for BMO (`mooi-notch` is
  untouched for its own chat).
- `lib/bmostate.luau`/`bmochat.luau`/`bmoact.luau`: pure and single-writer; `bmoact` uses `run` plus
  temp/backup for file changes outside the Pleamar files sandbox.
- `mooi.plm`: facts `x_/p_/w_/m_/fi_/g_` for both modules; spring props `xs_/ws_/pv_`; draw group
  and zone; edit-mode `ez_bmo`/`ez_herdr` zones and `ed_press` 33/34; `ed_ix`/`ed_fi`/`ed_g` pick
  lists; `hc_x/hc_w` and frame pick lists; island slot `open` enum; `life.bmo`/`life.herdr` layers;
  island `IslandFrame` + content; keyboard clause already covers any `open != none`.
- `tools/gen-settings.py`: `MODULES` and `NAMES`; new companion/herdr rows and page; regenerate
  `shell/mooi-settings.plm` (never hand-edit).
- `lib/config.luau`: defaults/validation; auto `bar.modules.*`.
- `lib/setters.luau`: appended codes and matching tests.
- `bin/mooi`: scene/data links already cover `bmo`; no new scene for phase 1–3. If Herdr needs a
  helper later, add its scene and link.
- Tests: `tests/unit/run.lua` cases for bmostate, bmoact, hands, herdrfeed, barlayout order/widths,
  config defaults, setter order, scene text assertions (`ez_bmo`, `ez_herdr`, `ed_press = 33/34`,
  `follow xs_bmo`, `ws_bmo`); live `tests/bmo.sh` (start the bar in safe mode, click facts, state
  file round-trip) and `tests/herdr.sh` (fake JSON fixtures, no real agents). `bin/mooi check`
  compiles all scenes and runs the gate.

## 17. Testing and verification

- Unit: pure modules under `lua5.4`; no timers, no files, no `sys`. Every state transition has a
  test; corrupt JSON, missing fields, stale `rev`, double intent, path traversal,
  command refusal, cheek boundaries, brief sanitising.
- Scene: compile with `pleamar --check`; fact names and labels; module width and edit code; island
  open/close; no keyboard claim while closed; reduced motion.
- Live: `tests/bmo.sh` starts a temporary bar scene in safe mode (`MOOI_SAFE=1`), writes a shared
  state, checks facts and the island, then restores `settings.json`/state files byte for byte.
  `tests/herdr.sh` uses fixture JSON and a fake `herdr` path, never the real server.
- Default layout: existing 1920 fit test must pass unchanged; both new modules are on the shelf.
- Performance: the module should compose/paint under 1 ms; the face is a handful of shapes; no
  full-bar repaint per frame; the bar writes at most every 2 s idle. Measure with
  `pleamar --report` as the Sigil spike did.
- Manual: one monitor first (the current machine), then a second monitor if available; desktop BMO
  on/off; bar restart; missing Herdr; corrupt shared file; settings reset.

## 18. Risks and how the design handles them

- **Multi-monitor state split** → one scene/one logic process owns the pet; every monitor is a
  surface on the same scene, so there is nothing to split; `rev` only marks stale reads.
- **Desktop and bar fighting over mood** → desktop proposes intents, the bar decides; desktop adopts.
- **File write storms** → 2 s idle persistence, immediate only on events; body throttle 250 ms.
- **Chat leaking context to a model** → only the explicit context line and explicit reads; redaction
  and path allowlist; no tool use by default.
- **Dangerous actions** → tier + confirmation + exact command/diff + undo + no sudo; the log is
  visible in the island.
- **18+ tone becoming harassment** → cheek is a bounded tone; explicit content, slurs and
  non-consensual content are out of scope at every level; deflection in character.
- **Herdr CLI output changing** → pure parser is tolerant, fixtures, warning card on parse failure;
  the module hides rather than crashes.
- **Herdr briefs reading secrets** → only the last lines, only visible/blocked, token-pattern
  stripping, 8 s cache, `brief` off switch; no full transcript.
- **Island keyboard stealing** → existing scene clause; closed island claims nothing; input only
  while Chat is open.
- **Pill/Sigil divergence** → both read the shared view; `pillface` becomes a view, not a second
  brain.
- **Settings drift** → generated scene, append-only setters, defaults validated; tests assert order.

## 19. What is left to the builder

- Exact Pleamar component syntax for `BmoModule` and the island; reuse `BmoFace`, `IslandFrame`,
  `IsleHead`, `IsleRule`, `IsleBtn` and the existing input pattern.
- Charge/overcharge timing constants (`CHARGE_MS`, the 6 s overcharge) if testing shows a better
  balance.
- Exact font sizes/paddings and the final 380×460 / 420×460 island dimensions; keep them inside the
  screen and the bar's anchor rules.
- The precise JSON prompt text and the allowlist entries, provided the tiers, path rules and
  confirmation behavior above are kept.
- Whether `bmo-actions.json` keeps 50 or 100 entries; undo depth for files (design says one backup).
- The Herdr vendor-mark set; use the agent name and a simple glyph if no icon exists.
- The test names; follow the existing `section:` style in `tests/unit/run.lua`.
