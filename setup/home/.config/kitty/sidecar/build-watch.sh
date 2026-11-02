#!/usr/bin/env bash
# build monitor — launched by `map alt+t` in its own tab.
# shows recent workflow runs of the active project, auto-refreshing.
set -u
. "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"

refresh=$SIDECAR_REFRESH
[ "$refresh" -ge 15 ] || refresh=15

proj=$(sc_resolve_project 2>/dev/null) || proj=
repo=
[ -n "$proj" ] && repo=$(sc_repo_remote "$proj" 2>/dev/null) || repo=

draw() {
  clear
  printf '%s╭─ %sbuild-watch%s ' "$ST" "$FG" "$R"
  printf '%s· %s · every %ss · %s%s\n' "$ST" "${repo:-no github repo}" "$refresh" "$(date +%H:%M:%S)" "$R"
  printf '%s╰%s\n' "$ST" "$(printf '─%.0s' $(seq 1 60))"
  if [ -z "$repo" ]; then
    printf '%sno github repo at %s%s\n' "$ST" "${proj:-$PWD}" "$R"
    return
  fi
  if ! sc_gh_ok; then
    printf '%sgh not authenticated — run: gh auth login%s\n' "$RED" "$R"
    return
  fi
  if ! out=$(gh run list --repo "$repo" --limit 15 \
      --json databaseId,workflowName,status,conclusion,headBranch,createdAt 2>&1); then
    printf '%sgh run list failed: %s%s\n' "$RED" "$(printf '%s' "$out" | head -n2 | sc_sane)" "$R"
    return
  fi
  printf '%s' "$out" | jq -r \
    --arg g "$GRN" --arg b "$RED" --arg c "$CYN" --arg o "$ST" --arg r "$R" '
    def glyph:
      if .conclusion == "success" then "\($g)✓\($r)"
      elif (.conclusion == "failure" or .conclusion == "timed_out" or .conclusion == "startup_failure") then "\($b)✗\($r)"
      elif .conclusion == "cancelled" then "\($o)⊘\($r)"
      elif .status == "in_progress" then "\($c)▸\($r)"
      elif .status == "queued" or .status == "waiting" or .status == "pending" or .status == "requested" then "\($c)…\($r)"
      elif .conclusion == "neutral" or .conclusion == "skipped" then "\($o)○\($r)"
      else "\($o)·\($r)" end;
    def age:
      (now - (try (.createdAt | fromdateiso8601) catch 0)) as $d
      | if $d < 0 then "?" elif $d < 3600 then "\($d/60|floor)m"
        elif $d < 86400 then "\($d/3600|floor)h" else "\($d/86400|floor)d" end;
    to_entries[] | .value
    | "\(glyph) \(.databaseId | tostring | ("      " + .)[-6:])  \(.workflowName[0:38])"
    + "  \(.headBranch[0:20]) · \(.status)\(if .conclusion then "/" + .conclusion else "" end) · \(age)"
  ' | sc_sane
  [ "$(printf '%s' "$out" | jq 'length')" = 0 ] && printf '%sno workflow runs%s\n' "$ST" "$R"
}

printf 'r refresh · w watch run · q quit (auto refresh every %ss)\n' "$refresh"
while true; do
  draw
  if read -r -t "$refresh" -n 1 key; then
    case $key in
      q) exit 0 ;;
      r) continue ;;
      w)
        printf '\nwatch run id: '
        read -r id
        case $id in
          ''|*[!0-9]*) continue ;;
        esac
        [ -n "$repo" ] && gh run watch "$id" --repo "$repo" || true
        printf '\n%s· enter to return%s' "$ST" "$R"; read -r _
        ;;
    esac
  fi
done
