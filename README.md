# mooi

A keyboard-first desktop shell for Hyprland, built on [Pleamar](https://github.com/k4ditano/pleamar).

mooi replaces the usual bar-plus-widgets patchwork with one desktop that shares a single look,
colour engine and motion. Your wallpaper sets the palette, and the bar, panels, terminal, GTK/Qt
apps and lock screen all follow it.

## What you get

- **The bar** (Ferrolume): workspaces, media, system stats, tray, weather and notifications, with islands that grow out of it.
- **Control Nexus**: a deck of cards for audio, network, bluetooth, brightness, music, weather and GitHub.
- **Side drawers**: Super+D slides a Dashboard out of the frame's left side (your GitHub, half a year of contributions,
  the system's updates, a quote); Super+N slides your notifications out of the right.
- **Side notch**: a sliver on the screen edge that fans out into Claude chat, music, workspaces, wallpapers and games.
- **Wallpapers**: local folders or Wallhaven, video wallpapers, parallax, and colours pulled from the picture.
- **Music player**: library, lyrics, EQ and visualisers.
- **Desktop widgets**: clock, notes, GitHub, system and calendar.
- **Lock screen**: your colours and wallpaper, PAM password, and media controls.
- **Settings window**: every option in one place, with no config files to edit.
- **BMO**: a small desktop companion.

## Install

On a fresh Arch or EndeavourOS system:

```sh
git clone https://github.com/bushninjadots/mooi.git ~/Projects/mooi
~/Projects/mooi/setup/install.sh
```

Log out and choose the Hyprland session. The installer adds only what mooi needs. Anything in
your home folder that it replaces is moved to `~/.setup-backup-<date>/`, not deleted. You start
from clean defaults: no one else's settings, accounts or pictures.

## Keys

| | |
| --- | --- |
| Super + A | search and apps |
| Super + R | system panel |
| Super + W | wallpapers |
| Super + D | the Dashboard drawer |
| Super + N | the notifications drawer |
| Super + K | every shortcut, in words |
| Super + L | lock |
| Super + Shift + V | clipboard history |
| Super + Shift + R | record the screen |
| Super + Shift + B | restart mooi |

Everything else is in Settings.

## Status

mooi is in daily use but young, and it is built and tested on one machine. Expect rough edges.
To report a problem, open an issue; for anything security-related, see [SECURITY.md](SECURITY.md).
