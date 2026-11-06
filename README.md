# mooi

A fluid, keyboard-first desktop shell for Hyprland, rendered with [Pleamar](https://github.com/k4ditano/pleamar).

This repo intentionally ships a shareable desktop snapshot, not the live personal state of the author. The setup capture excludes notes, board/task data, identity assets, caches and credentials; install on a fresh machine as a starting point, then log in again to your own services.

Status: the shell is built and in use, and the current setup snapshot is intentionally neutral rather than a copy of any one machine's private state.

## Keys

| | |
| --- | --- |
| Super+Alt+Space | the command membrane |
| Super+Alt+Shift+Space | stop mooi |
| Super+Shift+B | start or restart mooi |

## Commands

```sh
bin/mooi session | toggle | stop | status
bin/mooi open | system | overview
bin/mooi theme-sync
bin/mooi theme-watch
bin/mooi run [--safe]
bin/mooi refresh
bin/mooi settings | edit
bin/mooi check
```

Needs `pleamar` 0.7.11, `hyprctl`, `jq`, `lua5.4` and `wpctl`/`brightnessctl` for the tests.

## A new machine

On a fresh EndeavourOS/Arch install: clone this repo to `~/Projects/mooi` and run
`setup/install.sh`. It installs what mooi needs and a neutral desktop configuration; nothing of the
author's comes with it — no settings, notes, pictures, accounts or package choices beyond mooi's
own. See [setup/README.md](setup/README.md).
