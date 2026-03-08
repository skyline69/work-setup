#!/usr/bin/env bash
set -euo pipefail

selection_file="${XDG_CONFIG_HOME:-$HOME/.config}/work-setup/wallpaper.env"

if [[ ! -f "$selection_file" ]]; then
  exit 0
fi

# shellcheck source=/dev/null
source "$selection_file"

wallpaper_path="${WORK_SETUP_WALLPAPER_PATH:-}"
if [[ -z "$wallpaper_path" || ! -f "$wallpaper_path" ]]; then
  exit 0
fi

if command -v awww-daemon >/dev/null 2>&1 && command -v awww >/dev/null 2>&1; then
  if ! pgrep -x awww-daemon >/dev/null 2>&1; then
    awww-daemon >/dev/null 2>&1 &
    sleep 0.5
  fi

  exec awww img "$wallpaper_path"
fi

if command -v hyprpaper >/dev/null 2>&1 && command -v hyprctl >/dev/null 2>&1; then
  if ! pgrep -x hyprpaper >/dev/null 2>&1; then
    hyprpaper >/dev/null 2>&1 &
  fi

  for _ in $(seq 1 10); do
    if hyprctl hyprpaper reload ",$wallpaper_path" >/dev/null 2>&1; then
      exit 0
    fi

    sleep 0.2
  done
fi

exit 0
