#!/bin/sh
# The login screen step without root (D190): `setup/greeter.sh --dry-run` writes the greetd config,
# the greeter's theme and its link into a scratch folder, keeps a foreign config beside the new one,
# prints every command that would need root instead of running it, and a second run changes nothing.
# `setup/install.sh --dry-run` reaches the same step and stops there — no packages, no files, no sudo.
# sudo is a stub that logs and fails, so any real attempt shows up as a failed run and a non-empty log.
# Nothing of the real /etc, /var or home is read or written.
# Run from anywhere: tests/setup-greeter.sh
set -u
root=$(cd "$(dirname "$0")/.." && pwd)
command -v jq >/dev/null 2>&1 || { echo "setup-greeter: jq is required"; exit 2; }
t=$(mktemp -d); trap 'chmod -R u+rwX "$t" 2>/dev/null; rm -rf "$t"' EXIT
mkdir -p "$t/bin" "$t/home" "$t/data/pleamar/mooi" "$t/state" "$t/config" "$t/run"
# the stub: it must never be reached, and if it is, the test says so
printf '#!/bin/sh\necho "sudo $*" >> "%s/sudo.log"\nexit 1\n' "$t" > "$t/bin/sudo"
chmod +x "$t/bin/sudo"
PATH="$t/bin:$PATH"; export PATH
export HOME="$t/home" XDG_DATA_HOME="$t/data" XDG_CONFIG_HOME="$t/config" \
    XDG_STATE_HOME="$t/state" XDG_RUNTIME_DIR="$t/run"
printf '{"version":1,"mode":"dark","colours":{"surface_dim":"#101418","surface_container_high":"#283039","outline":"#8b96a3","on_surface":"#e3e6ea","on_surface_variant":"#bcc4ce","primary":"#7fc8a9","secondary":"#7aa7d9","tertiary":"#d9a86c","error":"#ffb4ab"}}' \
    > "$XDG_DATA_HOME/pleamar/mooi/palette.json"
fail=0; n=0
ok()    { n=$((n + 1)); echo "  ok    $1"; }
bad()   { n=$((n + 1)); fail=$((fail + 1)); echo "  FAIL  $1"; }
is()    { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 ('$2', expected '$3')"; fi; }
has()   { if grep -q -- "$2" "$3" 2>/dev/null; then ok "$1"; else bad "$1 ($3 has no '$2')"; fi; }
hasnot() { if grep -q -- "$2" "$3" 2>/dev/null; then bad "$1 ($3 has '$2')"; else ok "$1"; fi; }
su()    { if [ -s "$t/sudo.log" ]; then bad "$1 (sudo was called: $(cat "$t/sudo.log"))"; else ok "$1"; fi; }

r=$t/root
mkdir -p "$r/etc/greetd"
printf '[default_session]\ncommand = "agreety --cmd /bin/sh"\nuser = "greeter"\n' > "$r/etc/greetd/config.toml"

echo "a dry run writes the login screen's files into the scratch folder"
out=$(MOOI_GREETER_ROOT="$r" sh "$root/setup/greeter.sh" --dry-run 2>&1); code=$?
is "it exits 0" "$code" "0"
case $out in *"a dry run into $r"*) ok "it says where it is writing" ;; *) bad "it says where it is writing ('$out')" ;; esac
su "nothing was run as root"

echo "the greetd config is the one the greeter needs"
cfg=$r/etc/greetd/config.toml
has "the terminal" '^\[terminal\]$' "$cfg"
has "on VT 1" '^vt = 1$' "$cfg"
has "the session" '^\[default_session\]$' "$cfg"
has "is sysc-greet's Hyprland session" '^command = "start-hyprland -- --config /etc/greetd/hyprland-greeter-config.lua"$' "$cfg"
has "as the greeter user" '^user = "greeter"$' "$cfg"
hasnot "no agreety is left behind" 'agreety' "$cfg"
is "the config is only the greeter" "$(wc -l < "$cfg")" "6"

echo "a foreign config is kept beside the new one, not thrown away"
before=$(ls "$r/etc/greetd" | grep -c '^config.toml.before-mooi-')
is "one copy of the old one" "$before" "1"
old=$(ls "$r/etc/greetd" | grep '^config.toml.before-mooi-' | head -1)
has "with its own contents" 'agreety --cmd /bin/sh' "$r/etc/greetd/$old"

echo "the greeter's theme is written where it looks for it, and named"
td=$r/var/lib/sysc-greet/shell-theme
is "mooi's primary came through" "$(sed -n 's/^primary = "\(.*\)"$/\1/p' "$td/mooi.toml")" "#7fc8a9"
is "eleven roles" "$(grep -c '^[a-z_]* = "#[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]"$' "$td/mooi.toml")" "11"
is "and the name the greeter follows" "$(cat "$td/theme")" "Mooi"
link=$r/usr/share/sysc-greet/themes/mooi.toml
if [ -L "$link" ]; then ok "a link makes it one of the greeter's themes"; else bad "a link makes it one of the greeter's themes"; fi
is "the link points at that theme" "$(readlink "$link")" "$td/mooi.toml"

echo "what would need root is printed, not done"
case $out in *"would: sudo systemctl disable sddm"*) ok "it says sddm would be disabled" ;; *) bad "it says sddm would be disabled" ;; esac
case $out in *"would: sudo systemctl enable greetd"*) ok "and greetd enabled" ;; *) bad "and greetd enabled" ;; esac
# greetd's own package may already have made the account: then there is nothing to say, and saying
# nothing is right. The line is required only where the account is missing.
if id greeter >/dev/null 2>&1; then
    case $out in *"would: sudo useradd"*) bad "no account is made when greeter already exists" ;; *) ok "no account is made when greeter already exists" ;; esac
else
    case $out in *"would: sudo useradd"*) ok "it says the greeter account it would make" ;; *) bad "it says the greeter account it would make" ;; esac
fi
case $out in *"would: look for /etc/greetd/hyprland-greeter-config.lua"*) ok "and the compositor config it would check" ;; *) bad "and the compositor config it would check" ;; esac

echo "a second run changes nothing"
cfgsum=$(cksum "$cfg")
out2=$(MOOI_GREETER_ROOT="$r" sh "$root/setup/greeter.sh" --dry-run 2>&1); code=$?
is "it exits 0 again" "$code" "0"
is "the config is byte for byte the same" "$(cksum "$cfg")" "$cfgsum"
is "no second copy of the old config" "$(ls "$r/etc/greetd" | grep -c '^config.toml.before-mooi-')" "1"
su "and still nothing was run as root"

echo "install.sh --dry-run reaches the same step and stops there"
r2=$t/root2
out3=$(MOOI_GREETER_ROOT="$r2" sh "$root/setup/install.sh" --dry-run 2>&1); code=$?
is "it exits 0" "$code" "0"
has "the config is written there too" '^user = "greeter"$' "$r2/etc/greetd/config.toml"
case $out3 in *"a dry run into $r2"*) ok "and it is the greeter's step that ran" ;; *) bad "and it is the greeter's step that ran ('$out3')" ;; esac
su "no packages, no sudo, nothing installed"

echo
echo "$n checks, $fail failed"
[ "$fail" -eq 0 ]
