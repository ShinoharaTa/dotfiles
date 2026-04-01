#!/bin/bash
# Claude Code status line — htop style
set -euo pipefail

input=$(cat)
WIDTH=80

# ── Colors ──
GREEN="\033[32m"
YELLOW="\033[33m"
RED="\033[31m"
CYAN="\033[36m"
DIM="\033[2m"
RESET="\033[0m"

color_for_pct() {
  local pct=$1
  if (( pct >= 80 )); then printf '%s' "$RED"
  elif (( pct >= 50 )); then printf '%s' "$YELLOW"
  else printf '%s' "$GREEN"
  fi
}

# ── Directory & Git ──
current_dir=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // ""')
repo_path=$(echo "$current_dir" | sed "s|^$HOME/||; s|^$HOME|~|")

branch_name=""
git_dirty=""
if git -C "$current_dir" rev-parse --git-dir > /dev/null 2>&1; then
  branch_name=$(git -C "$current_dir" -c core.fsmonitor= symbolic-ref --short HEAD 2>/dev/null \
                || git -C "$current_dir" rev-parse --short HEAD 2>/dev/null || true)
  if ! git -C "$current_dir" diff --quiet 2>/dev/null || ! git -C "$current_dir" diff --cached --quiet 2>/dev/null; then
    git_dirty="*"
  fi
fi

# ── Context window ──
used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // "0"')
printf -v used_int "%.0f" "$used_pct" 2>/dev/null || used_int="${used_pct%%.*}"

# ── Usage API (OAuth, cached 360s) ──
CACHE_FILE="/tmp/claude-usage-cache.json"
CACHE_TTL=360

fetch_usage() {
  local token
  token=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null || true)
  [ -z "$token" ] && return 1
  local access_token
  access_token=$(echo "$token" | jq -r '.claudeAiOauth.accessToken // .accessToken // .access_token // empty' 2>/dev/null || true)
  [ -z "$access_token" ] && return 1
  local response
  response=$(curl -sf --max-time 5 \
    -H "Authorization: Bearer ${access_token}" \
    -H "anthropic-beta: oauth-2025-04-20" \
    "https://api.anthropic.com/api/oauth/usage" 2>/dev/null) || return 1
  local now
  now=$(date +%s)
  echo "$response" | jq --arg ts "$now" '. + {cached_at: ($ts | tonumber)}' > "$CACHE_FILE" 2>/dev/null
  echo "$response"
}

get_usage() {
  local now
  now=$(date +%s)
  if [ -f "$CACHE_FILE" ]; then
    local cached_at
    cached_at=$(jq -r '.cached_at // 0' "$CACHE_FILE" 2>/dev/null || echo "0")
    local age=$(( now - cached_at ))
    if (( age < CACHE_TTL )); then
      jq -r 'del(.cached_at)' "$CACHE_FILE" 2>/dev/null
      return 0
    fi
  fi
  fetch_usage
}

iso_to_epoch() {
  local stripped="${1%%.*}"
  TZ=UTC date -j -f "%Y-%m-%dT%H:%M:%S" "$stripped" +%s 2>/dev/null || echo ""
}

format_5h_reset() {
  local epoch
  epoch=$(iso_to_epoch "$1")
  [ -z "$epoch" ] && return
  LC_ALL=en_US.UTF-8 TZ="Asia/Tokyo" date -r "$epoch" +"%-l%p" 2>/dev/null | sed 's/AM/am/;s/PM/pm/'
}

format_7d_reset() {
  local epoch
  epoch=$(iso_to_epoch "$1")
  [ -z "$epoch" ] && return
  local m d
  m=$(TZ="Asia/Tokyo" date -r "$epoch" +"%m" 2>/dev/null | sed 's/^0/ /')
  d=$(TZ="Asia/Tokyo" date -r "$epoch" +"%d" 2>/dev/null | sed 's/^0/ /')
  printf '%s/%s' "$m" "$d"
}

usage_json=$(get_usage 2>/dev/null || true)

five_int=0; five_reset_str=""
seven_int=0; seven_reset_str=""

if [ -n "$usage_json" ]; then
  five_util=$(echo "$usage_json" | jq -r '.five_hour.utilization // empty' 2>/dev/null)
  if [ -n "$five_util" ]; then
    printf -v five_int "%.0f" "$five_util" 2>/dev/null || five_int="${five_util%%.*}"
    five_reset=$(echo "$usage_json" | jq -r '.five_hour.resets_at // empty' 2>/dev/null)
    [ -n "$five_reset" ] && five_reset_str=$(format_5h_reset "$five_reset" || true)
  fi
  seven_util=$(echo "$usage_json" | jq -r '.seven_day.utilization // empty' 2>/dev/null)
  if [ -n "$seven_util" ]; then
    printf -v seven_int "%.0f" "$seven_util" 2>/dev/null || seven_int="${seven_util%%.*}"
    seven_reset=$(echo "$usage_json" | jq -r '.seven_day.resets_at // empty' 2>/dev/null)
    [ -n "$seven_reset" ] && seven_reset_str=$(format_7d_reset "$seven_reset" || true)
  fi
fi

# ════════════════════════════════════════════
# Build output
# Label width: "Limit" = 5 chars → "Label: " = 7 chars fixed
# ════════════════════════════════════════════
LBL_W=7  # "Dir  : " "Ctx  : " "Limit: " all 7 chars

# --- Line 1: Dir ---
dir_val="${repo_path}"
[ -n "$branch_name" ] && dir_val+=" (${branch_name}${git_dirty})"
printf '%b%-5s%b: %b%s%b' "$DIM" "Dir" "$RESET" "$CYAN" "$dir_val" "$RESET"

# --- Line 2: Ctx ---
# Bar fills: WIDTH - LBL_W - 2 (brackets) - 5 (" XXX%") = 66
ctx_bar_w=$(( WIDTH - LBL_W - 2 - 5 ))
ctx_filled=$(( used_int * ctx_bar_w / 100 ))
(( ctx_filled > ctx_bar_w )) && ctx_filled=$ctx_bar_w
ctx_empty=$(( ctx_bar_w - ctx_filled ))
ctx_color=$(color_for_pct "$used_int")
printf -v ctx_pct "%4s" "${used_int}%"

printf '\n%b%-5s%b: [' "$DIM" "Ctx" "$RESET"
printf '%b' "$ctx_color"
for ((i=0; i<ctx_filled; i++)); do printf '|'; done
printf '%b' "$RESET"
printf '%*s' "$ctx_empty" ""
printf '] %b%s%b' "$ctx_color" "$ctx_pct" "$RESET"

# --- Line 3: Limit ---
# "Limit: 5h (9am ) [||||||||||||||||||] 20% 7d (3/22 ) [|||||||||||||||||||] 30%"
# 5h reset: max 4 chars (e.g. "12pm") → "(XXXX)" = 6 chars
# 7d reset: max 5 chars (e.g. "12/22") → "(XXXXX)" = 7 chars
# pct: 3 digits right-aligned + "%" = 4 chars
# Fixed: 7 + 3+6+2 + 2+4 + 1 + 3+7+2 + 2+4 = 43 → bars = 80-43 = 37

if [ -n "$five_reset_str" ]; then
  printf -v five_reset_part "(%4s)" "$five_reset_str"
else
  five_reset_part="      "
fi
if [ -n "$seven_reset_str" ]; then
  printf -v seven_reset_part "(%5s)" "$seven_reset_str"
else
  seven_reset_part="       "
fi

total_bar=$(( WIDTH - 43 ))
five_bar_w=$(( total_bar / 2 ))
seven_bar_w=$(( total_bar - five_bar_w ))

printf '\n%b%-5s%b: ' "$DIM" "Limit" "$RESET"

# 5h segment: "5h (9am ) [||||              ] 20%"
five_filled=$(( five_int * five_bar_w / 100 ))
(( five_filled > five_bar_w )) && five_filled=$five_bar_w
five_empty=$(( five_bar_w - five_filled ))
five_color=$(color_for_pct "$five_int")
printf -v five_pct "%3d%%" "$five_int"

printf '5h %s [' "$five_reset_part"
printf '%b' "$five_color"
for ((i=0; i<five_filled; i++)); do printf '|'; done
printf '%b' "$RESET"
printf '%*s' "$five_empty" ""
printf '] %b%s%b ' "$five_color" "$five_pct" "$RESET"

# 7d segment: "7d (3/22 ) [||||||||||||||||||] 30%"
seven_filled=$(( seven_int * seven_bar_w / 100 ))
(( seven_filled > seven_bar_w )) && seven_filled=$seven_bar_w
seven_empty=$(( seven_bar_w - seven_filled ))
seven_color=$(color_for_pct "$seven_int")
printf -v seven_pct "%3d%%" "$seven_int"

printf '7d %s [' "$seven_reset_part"
printf '%b' "$seven_color"
for ((i=0; i<seven_filled; i++)); do printf '|'; done
printf '%b' "$RESET"
printf '%*s' "$seven_empty" ""
printf '] %b%s%b' "$seven_color" "$seven_pct" "$RESET"
