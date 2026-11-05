# setup/ — shareable desktop baseline

This directory contains the shareable desktop configuration that can be copied onto another machine. It is intentionally not a backup of the author's private state.

## What is intentionally excluded

- Live settings, notes, and board/task state inside `setup/home/.local/share/pleamar/mooi/`
- Identity/avatar/banner images and other personal profile assets
- Caches, generated state, and credentials
- Any file that looks like a token or private key

The capture script keeps only config, package lists, fonts, themes and the neutral starter files needed for a machine to boot into a working setup. Personal state stays local unless you explicitly choose to copy it.

## On a new machine

1. Install EndeavourOS (or Arch), with SDDM or no login screen, and log in.
2. `git clone git@github.com:bushninjadots/mooi.git ~/Projects/mooi`
3. `~/Projects/mooi/setup/install.sh`
4. Copy wallpapers into `~/Pictures/wallpapers` if you want them.
5. Log out and choose the Hyprland session.

`install.sh` asks for sudo. What it replaces in your home is moved, not deleted, to `~/.setup-backup-<date>/`.

## Keeping it current

Before committing a desktop change, run:

    setup/capture.sh && git add -A setup && git commit -m "setup: captured"

This capture intentionally writes neutral starter state, not your live board, notes or profile data.
