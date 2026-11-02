# setup/ — this desktop, to rebuild it on another machine

Everything the desktop is made of, beyond mooi's own code, kept here so a new machine can be made the
same as this one.

## On a new machine

1. Install EndeavourOS (or Arch), with sddm or no login screen at all, and log in.
2. `git clone git@github.com:bushninjadots/mooi.git ~/Projects/mooi`
3. `~/Projects/mooi/setup/install.sh`
4. Copy your wallpapers into `~/Pictures/wallpapers` (not in the repo: 8 GB).
5. Log out, choose the Hyprland session. mooi starts with it.

`install.sh` asks for sudo. What it replaces in your home is moved, not deleted, to
`~/.setup-backup-<date>/`. `--no-packages` lays down the files only.

## Keeping it current

Before committing, whenever the desktop changed (Hyprland settings, mooi's Settings, a new package):

    setup/capture.sh && git add -A setup && git commit -m "setup: captured"

## What is here

| | |
|---|---|
| `home/.config/` | `hypr` (without its 80 MB `wallpapers/` and unread `legacy/`), `qs-wallpaperpicker` (Skwd Wall), `desktop-widgets`, `wallpaper-styles`, `kitty`, `matugen`, `environment.d`, `pleamar` (without its unused `shells/`), `gtk-3.0`, `gtk-4.0`, `qt5ct`, `qt6ct` |
| `home/.local/share/pleamar/mooi/` | mooi's state you chose: `settings.json`, the board, notes, the stash, environments, signals, workspaces, the equaliser, where the Nexus, player and notch sit, BMO's place, your identity pictures and theme |
| `home/.local/share/fonts/`, `home/.icons/`, `home/.themes/` | hand-installed fonts (mooi's Share Tech Mono and Exo 2 among them), the phinger cursors, the GTK theme |
| `home/.gsettings` | icon theme, cursor, GTK theme, colour scheme, font |
| `packages.pacman`, `packages.aur` | what was installed by hand (`pacman -Qqen`, `pacman -Qqem`) |
| `pleamar.ref` | the pleamar repository and the exact commit this desktop ran on; `install.sh` builds that one |

## Not here

- **Wallpapers** (`~/Pictures/wallpapers`, 8 GB, and the 80 MB in `~/.config/hypr/wallpapers`): back them up separately.
- **Caches mooi rebuilds by itself**: thumbnails, covers, lyrics, the palette (made from the wallpaper), weather.
- **Credentials**: `capture.sh` refuses to capture anything that looks like a token or private key. Log in
  again to GitHub (`gh auth login`), Claude and the rest.
- **System files**: `/etc/kernel/cmdline` (this one has `amdgpu.dcdebugmask=0x10`, PSR off, against the
  freezes), `/etc/pacman.conf`'s extra repositories (`[endeavouros]`, `[blackarch]`; packages only they
  offer are listed as not installed at the end), the boot loader, the login screen's theme.
- **Iosevka Nerd Font** (690 MB): installed as the `ttf-iosevka-nerd` package instead.
- **Monitors**: `hypr/config/monitor.lua` and `display-config` name this laptop's screen (`eDP-1`);
  another machine's may differ.
