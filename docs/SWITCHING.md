# Running mooi

mooi is the whole desktop. There is no other shell beside it: ArchEclipse was uninstalled on
2026-10-21 (D48), and the launcher's beside and takeover modes were removed in D133.

- At login `~/.config/hypr/config/custom/mooi.lua` runs `bin/mooi session`.
- `bin/mooi session` (also `start`, and **Super+Shift+B**) takes a fresh snapshot of `shell/`, starts
  the keeper and the theme watch, and restarts mooi if it is already running.
- The keeper restarts the scene after a crash. After three quick crashes it gives up **and says so in
  a critical notification**; Super+Shift+B starts it again.
- `bin/mooi stop` (**Super+Alt+Shift+Space**) stops mooi, its keeper and the theme watch.
- `bin/mooi refresh` copies the repo into the running snapshot and restarts the scene; the keeper stays.
- `bin/mooi status` says whether the keeper and the scene run.

The keeper's pid is in `$XDG_RUNTIME_DIR/mooi/keep.pid` (tmpfs, gone at logout). The scene runs with
`MOOI_MODE=session`; a bare `bin/mooi run` has no `MOOI_MODE` and so does not claim notifications.

## The keys mooi takes

mooi.lua binds mooi's own keys (Settings → Keys) and gives it the keys that reached ArchEclipse's
panels: **Super+A** search · **Super+R** the system panel · **Super+L** notices · **Super+Shift+V**
clipboard · **Super+Escape** the power menu (wlogout) · **Super+Shift+R** / **Super+Ctrl+Shift+R** record
the screen / an area · **Super+Shift+B** (re)start mooi. The lock and suspend keys and hypridle use
`scripts/lock-session.sh`, and the clipboard history mooi shows is fed by `cliphist` from login.

## Bringing ArchEclipse back

The archive is `~/.local/state/mooi/archive-2026-10-21-archeclipse.tar.gz` (`tar xzf … -C ~`), with the
`exec.lua` / `bind.lua` backups in `~/.local/state/mooi/dotfiles-backup-20261021-uninstall/`. Then
set `"session": { "standalone": false }` in mooi's `settings.json` (the switch left Settings in D134),
and from the next login ArchEclipse starts instead. To switch now: `bin/mooi stop`, then `~/.config/hypr/scripts/bar.sh --force`.

## Pleamar version

`~/.local/bin/pleamar` is **0.4.6**, built from `~/.local/share/pleamar/src/pleamar` (git, tag v0.4.6). The previous binary is `~/.local/bin/pleamar-0.3.7`. Rollback:

```sh
cp ~/.local/bin/pleamar-0.3.7 ~/.local/bin/pleamar
```

Every existing scene (Desk, Polkit, the six Tide variants, Marea) compiled on 0.4.6 before the swap. Desk and Polkit kept running their loaded 0.3.7 and move to 0.4.6 at their next restart (normally the next login).
