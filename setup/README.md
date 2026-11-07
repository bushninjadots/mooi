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

## Login screen

The login screen is **greetd** running [sysc-greet](https://github.com/Nomadcxx/sysc-greet)'s
Hyprland greeter, in place of sddm. `install.sh` installs `sysc-greet-hyprland` from the AUR,
writes `/etc/greetd/config.toml`:

    [terminal]
    vt = 1

    [default_session]
    command = "start-hyprland -- --config /etc/greetd/hyprland-greeter-config.lua"
    user = "greeter"

creates the `greeter` account with its cache, disables `sddm` if it is enabled, and enables
`greetd`. The greeter's own Lua config comes from the package and starts fullscreen kitty with the
greeter on Hyprland 0.55+, asking Hyprland to quit when kitty exits. Its preferences (theme,
border, background, wallpaper) are saved in `/var/cache/sysc-greet/`: F1 changes them at the
greeter, and `sysc-greet --test` runs it in a terminal without ending your session.

The greeter wears mooi's palette. sysc-greet chooses a theme by name: it reads
`/var/lib/sysc-greet/shell-theme/theme` and looks that name up among the themes in
`/usr/share/sysc-greet/themes`. `install.sh` makes that folder yours and points a `mooi.toml` there
at it, and `mooi greet-theme` writes it out of the palette — `theme-sync` calls that too, so a new
wallpaper recolours the login screen as well, with no password. Its F1 → Themes → Follow sysc-shell
is on by default; picking a theme there opts out.

The step is a script of its own: `setup/greeter.sh` sets the login screen up again on its own, and
`setup/greeter.sh --dry-run` (or `install.sh --dry-run`) writes it all into a scratch folder, printing
every command that would need root instead of running it — that is how the config it writes is tested
without root (`tests/setup-greeter.sh`).

To go back to sddm: `sudo systemctl disable greetd && sudo pacman -S sddm && sudo systemctl enable sddm`.

## For the author: keeping it current

    setup/capture.sh && git add -A setup && git commit -m "setup: captured"

The capture copies the desktop's configuration, writes neutral starter state, turns your home path
into `@HOME@` (the installer writes the installing user's home there) and blanks your GitHub login.
It **refuses to finish** if anything left still names you — your `/home/<user>` path, your git name
or email, your GitHub login — or looks like a credential. Your full package lists go to
`setup/personal/`, which is gitignored; `install.sh --personal` restores your exact machine from
your own checkout.
