# setup/ — shareable desktop baseline

This directory contains the shareable desktop configuration that can be copied onto another machine. It is intentionally not a backup of the author's private state.

## What is intentionally excluded

- Live settings, notes, and board/task state inside `setup/home/.local/share/pleamar/mooi/`
- Identity/avatar/banner images and other personal profile assets
- Caches, generated state, and credentials
- Any file that looks like a token or private key

The capture script keeps only config, package lists, fonts, themes and the neutral starter files needed for a machine to boot into a working setup. Personal state stays local unless you explicitly choose to copy it.

## On a new machine

1. Install EndeavourOS or Arch (with your graphics driver), and log in.
2. `git clone https://github.com/bushninjadots/mooi.git ~/Projects/mooi`
3. `~/Projects/mooi/setup/install.sh`
4. Put pictures in `~/Pictures/wallpapers`, or choose a folder in Settings → Wallpapers.
5. Log out and choose the Hyprland session.

`install.sh` installs only what mooi needs (`packages.pacman`, `packages.aur`, curated by hand),
asks for sudo, and moves whatever it replaces in your home to `~/.setup-backup-<date>/` instead of
deleting it. Your settings, notes, profile picture, GitHub account and the rest start empty: they
are yours to fill in.

## For the author: keeping it current

    setup/capture.sh && git add -A setup && git commit -m "setup: captured"

The capture copies the desktop's configuration, writes neutral starter state, turns your home path
into `@HOME@` (the installer writes the installing user's home there) and blanks your GitHub login.
It **refuses to finish** if anything left still names you — your `/home/<user>` path, your git name
or email, your GitHub login — or looks like a credential. Your full package lists go to
`setup/personal/`, which is gitignored; `install.sh --personal` restores your exact machine from
your own checkout.
