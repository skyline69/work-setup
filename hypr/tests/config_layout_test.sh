#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

fail() {
  echo "not ok - $*"
  exit 1
}

assert_file_contains() {
  local path="$1"
  local needle="$2"
  if ! grep -Fqx "$needle" "$path"; then
    fail "$path missing line: $needle"
  fi
}

assert_path_exists() {
  [[ -e "$1" ]] || fail "missing path $1"
}

main() {
  local host_name
  host_name=$(uname -n)

  assert_path_exists "$ROOT_DIR/common/environment.conf"
  assert_path_exists "$ROOT_DIR/common/autostart.conf"
  assert_path_exists "$ROOT_DIR/common/programs.conf"
  assert_path_exists "$ROOT_DIR/machines/$host_name/monitors.conf"
  assert_path_exists "$ROOT_DIR/active/monitors.conf"
  assert_path_exists "$ROOT_DIR/active/environment.conf"
  assert_path_exists "$ROOT_DIR/active/autostart.conf"
  assert_path_exists "$ROOT_DIR/active/programs.conf"

  assert_file_contains "$ROOT_DIR/monitors.conf" 'source = ~/.config/hypr/active/monitors.conf'
  assert_file_contains "$ROOT_DIR/environment.conf" 'source = ~/.config/hypr/common/environment.conf'
  assert_file_contains "$ROOT_DIR/environment.conf" 'source = ~/.config/hypr/active/environment.conf'
  assert_file_contains "$ROOT_DIR/autostart.conf" 'source = ~/.config/hypr/common/autostart.conf'
  assert_file_contains "$ROOT_DIR/autostart.conf" 'source = ~/.config/hypr/active/autostart.conf'
  assert_file_contains "$ROOT_DIR/programs.conf" 'source = ~/.config/hypr/common/programs.conf'
  assert_file_contains "$ROOT_DIR/programs.conf" 'source = ~/.config/hypr/active/programs.conf'

  echo 'ok - config layout'
}

main "$@"
