# shared helpers for the kitty github sidecar. sourced, not executed.
# shellcheck shell=bash

SC_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SC_STATE="$SC_DIR/state"
mkdir -p "$SC_STATE"

# --- settings ---------------------------------------------------------------
SIDECAR_PCT=32
SIDECAR_REFRESH=45
SIDECAR_LIMIT=30
SIDECAR_SCAN_DEPTH=5
SIDECAR_SCAN_TTL=600
if [ -f "$SC_DIR/sidecar.conf" ]; then
  # shellcheck disable=SC1091
  . "$SC_DIR/sidecar.conf"
fi
sc_int() { # var default min max
  local v=${!1:-}
  case $v in ''|*[!0-9]*) v=$2;; esac
  [ "$v" -lt "$3" ] && v=$3
  [ "$v" -gt "$4" ] && v=$4
  printf -v "$1" '%s' "$v"
}
sc_int SIDECAR_PCT 32 25 45
sc_int SIDECAR_REFRESH 45 0 3600
sc_int SIDECAR_LIMIT 30 5 100
sc_int SIDECAR_SCAN_DEPTH 5 2 8
sc_int SIDECAR_SCAN_TTL 600 30 86400

# --- palette (mooi: graphite, steel, oxidised green) -------------------------
R=$'\033[0m'; DIM=$'\033[2m'; BOLD=$'\033[1m'
GRN=$'\033[38;2;152;212;164m'; CYN=$'\033[38;2;162;206;217m'
ST=$'\033[38;2;139;147;138m'; FG=$'\033[38;2;223;228;220m'
RED=$'\033[38;2;204;139;139m'; YLW=$'\033[38;2;214;198;140m'

# --- views ------------------------------------------------------------------
SC_VIEWS=(prmine prrev issues repo runs local proj)
sc_get_view() {
  local v
  v=$(cat "$SC_STATE/view" 2>/dev/null) || v=
  case " ${SC_VIEWS[*]} " in
    *" $v "*) printf %s "$v" ;;
    *) printf prmine ;;
  esac
}
sc_set_view() {
  case " ${SC_VIEWS[*]} " in
    *" $1 "*) printf %s "$1" > "$SC_STATE/view.tmp" && mv -f "$SC_STATE/view.tmp" "$SC_STATE/view" ;;
  esac
}
sc_get_flag() { # file default
  local v
  v=$(cat "$SC_STATE/$1" 2>/dev/null) || v=
  [ -n "$v" ] && printf %s "$v" || printf %s "$2"
}
sc_set_flag() { # file value
  printf %s "$2" > "$SC_STATE/$1.tmp" && mv -f "$SC_STATE/$1.tmp" "$SC_STATE/$1"
}

# --- projects ---------------------------------------------------------------
sc_get_project() {
  local p
  p=$(cat "$SC_STATE/project" 2>/dev/null) || return 1
  [ -n "$p" ] && [ -d "$p" ] && [ -e "$p/.git" ] || return 1
  printf %s "$p"
}
sc_set_project() {
  [ -d "$1" ] && [ -e "$1/.git" ] || return 1
  printf %s "$1" > "$SC_STATE/project.tmp" && mv -f "$SC_STATE/project.tmp" "$SC_STATE/project"
}

sc_repo_remote() { # dir -> owner/repo (github only) or fail
  local dir=$1 url
  url=$(git -C "$dir" remote get-url origin 2>/dev/null) || return 1
  case $url in
    *github.com[:/]*) url=${url##*github.com[:/]} ;;
    *) return 1 ;;
  esac
  url=${url%.git} url=${url%/}
  case $url in */*) printf %s "$url"; return 0 ;; esac
  return 1
}

sc_projects() { # path \t owner/repo \t branch, cached scan
  local cache="$SC_STATE/projects"
  if [ -f "$cache" ]; then
    local age=$(( $(date +%s) - $(stat -c %Y "$cache") ))
    if [ "$age" -lt "$SIDECAR_SCAN_TTL" ]; then cat "$cache"; return; fi
  fi
  local tmp="$cache.tmp" d r b
  : > "$tmp"
  while IFS= read -r -d '' g; do
    d=$(dirname -- "$g")
    [ "$d" = "$HOME" ] && continue
    r=$(sc_repo_remote "$d") || continue
    b=$(git -C "$d" branch --show-current 2>/dev/null) || b=
    printf '%s\t%s\t%s\n' "$d" "$r" "$b" >> "$tmp"
  done < <(find "$HOME" -maxdepth "$SIDECAR_SCAN_DEPTH" \
      \( -name .git -print0 -prune \) -o \
      \( -path "$HOME/.cache" -o -path "$HOME/.cache/*" \
      -o -path "$HOME/.local/share/flatpak" -o -path "$HOME/.local/share/flatpak/*" \
      -o -path "$HOME/.local/share/containers" -o -path "$HOME/.local/share/containers/*" \
      -o -name node_modules -o -name .cache \) -prune -o \
      -false 2>/dev/null | head -z -n 500)
  mv -f "$tmp" "$cache"
  cat "$cache"
}

sc_find_local() { # owner/repo -> first local path or ""
  sc_projects | awk -F'\t' -v r="$1" '$2 == r { print $1; exit }'
}

sc_resolve_project() {
  local p
  if p=$(sc_get_project); then printf %s "$p"; return 0; fi
  if p=$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null) && sc_repo_remote "$p" >/dev/null; then
    printf %s "$p"; return 0
  fi
  p=$(sc_projects | head -n1 | cut -f1)
  [ -n "$p" ] || return 1
  printf %s "$p"
}

# --- list cache -------------------------------------------------------------
sc_cache_file() { printf '%s/cache.%s' "$SC_STATE" "$1"; }
sc_lookup() { # key (view:N) -> full tsv row
  local key=$1 v=${1%%:*} cf
  cf=$(sc_cache_file "$v")
  [ -f "$cf" ] || return 1
  awk -F'\t' -v k="$key" '$1 == k { print; f = 1; exit } END { exit !f }' "$cf"
}

# --- kitty remote control ---------------------------------------------------
sc_self() { printf '%s' "${KITTY_WINDOW_ID:-}"; }
sc_main_window_id() { # other (non-sidecar) window in my tab
  local me; me=$(sc_self); [ -n "$me" ] || return 1
  kitty @ ls 2>/dev/null | jq -r --argjson me "$me" '
    first(
      .[] as $ow | $ow.tabs[] as $tab
      | select(any($tab.windows[]; .id == $me))
      | $tab.windows[]
      | select(.id != $me and ((.title // "") != "gh-sidecar"))
      | .id
    ) // empty'
}
sc_sidecar_other() { # "id is_active" of another gh-sidecar in my tab, or ""
  local me; me=$(sc_self); [ -n "$me" ] || return 1
  kitty @ ls 2>/dev/null | jq -r --argjson me "$me" '
    first(
      .[] as $ow | $ow.tabs[] as $tab
      | select(any($tab.windows[]; .id == $me))
      | $tab.windows[]
      | select(.id != $me and ((.title // "") == "gh-sidecar"))
      | "\(.id) \(.is_active)"
    ) // empty'
}

# --- misc -------------------------------------------------------------------
sc_sane() { LC_ALL=C sed -e 's/[\x00-\x09\x0b-\x1f\x7f]//g'; }
sc_wcut() { cut -c1-"${1:-72}"; }
sc_note() { printf '%s\n' "$1" > "$SC_STATE/err"; }
sc_age() { # iso8601 -> 3m 2h 5d
  local t now d
  t=$(date -d "$1" +%s 2>/dev/null) || { printf '?'; return; }
  now=$(date +%s); d=$((now - t))
  if [ "$d" -lt 0 ] || [ "$d" -gt 315360000 ]; then printf '?'
  elif [ "$d" -lt 60 ]; then printf '%ss' "$d"
  elif [ "$d" -lt 3600 ]; then printf '%sm' "$((d / 60))"
  elif [ "$d" -lt 86400 ]; then printf '%sh' "$((d / 3600))"
  else printf '%sd' "$((d / 86400))"; fi
}
sc_gh_ok() { gh auth status >/dev/null 2>&1; }
