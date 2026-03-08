#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
INSTALLER_PATH="$ROOT_DIR/install.sh"

if [[ ! -f "$INSTALLER_PATH" ]]; then
  echo "not ok - installer script missing at $INSTALLER_PATH"
  exit 1
fi

# shellcheck source=/dev/null
source "$INSTALLER_PATH"
installer_main() {
  main "$@"
}

TEST_TMPDIR=$(mktemp -d)
trap 'rm -rf "$TEST_TMPDIR"' EXIT

fail() {
  echo "not ok - $*"
  exit 1
}

assert_eq() {
  local expected="$1"
  local actual="$2"
  local message="$3"
  if [[ "$expected" != "$actual" ]]; then
    fail "$message: expected '$expected' got '$actual'"
  fi
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local message="$3"
  if [[ "$haystack" != *"$needle"* ]]; then
    fail "$message: missing '$needle' in '$haystack'"
  fi
}

assert_path_exists() {
  local path="$1"
  local message="$2"
  [[ -e "$path" ]] || fail "$message: missing path $path"
}

assert_symlink_target() {
  local path="$1"
  local expected="$2"
  local message="$3"
  local actual
  actual=$(readlink "$path")
  assert_eq "$expected" "$actual" "$message"
}

test_detect_distro_from_os_release() {
  local os_release="$TEST_TMPDIR/os-release"
  cat > "$os_release" <<'EOS'
ID=fedora
NAME=Fedora Linux
EOS

  local detected
  detected=$(detect_distro "$os_release")
  assert_eq "fedora" "$detected" "detect_distro should read ID from os-release"
}

test_resolve_package_plan_includes_supported_and_unsupported() {
  local output
  output=$(resolve_package_plan arch core,quickshell)
  assert_contains "$output" "SUPPORTED_PACKAGES=" "package plan should include supported packages"
  assert_contains "$output" "quickshell-git" "arch quickshell group should include aur package"

  output=$(resolve_package_plan ubuntu core,quickshell)
  assert_contains "$output" "UNSUPPORTED_GROUPS=quickshell" "ubuntu should mark quickshell unsupported"
}

test_deploy_configs_creates_backup_and_active_includes() {
  local repo_root="$TEST_TMPDIR/repo"
  local target_home="$TEST_TMPDIR/home"
  mkdir -p "$repo_root/hypr/machines/workstation" "$repo_root/quickshell" "$target_home/.config/hypr" "$target_home/.config/quickshell"

  cat > "$repo_root/hypr/hyprland.conf" <<'EOS'
source = ~/.config/hypr/common.conf
EOS
  cat > "$repo_root/hypr/machines/workstation/monitors.conf" <<'EOS'
monitor=,preferred,auto,1
EOS
  cat > "$repo_root/hypr/machines/workstation/environment.conf" <<'EOS'
env = XDG_CURRENT_DESKTOP,Hyprland
EOS
  cat > "$repo_root/hypr/machines/workstation/autostart.conf" <<'EOS'
exec-once = hypridle
EOS
  cat > "$repo_root/hypr/machines/workstation/programs.conf" <<'EOS'
$terminal = alacritty
EOS
  cat > "$repo_root/quickshell/shell.qml" <<'EOS'
import QtQuick
EOS
  cat > "$target_home/.config/hypr/existing.conf" <<'EOS'
old
EOS

  deploy_configs "$repo_root" "$target_home" "workstation" "symlink"

  assert_path_exists "$target_home/.config/hypr.backup" "deploy should back up existing hypr config"
  assert_symlink_target "$target_home/.config/hypr" "$repo_root/hypr" "deploy should symlink hypr config"
  assert_symlink_target "$target_home/.config/quickshell" "$repo_root/quickshell" "deploy should symlink quickshell config"
  assert_path_exists "$repo_root/hypr/active/monitors.conf" "deploy should create active includes"
  assert_contains "$(cat "$repo_root/hypr/active/monitors.conf")" 'source = ~/.config/hypr/machines/workstation/monitors.conf' "active include should point at selected machine"
}

test_main_dry_run_skips_deploy() {
  local calls_file="$TEST_TMPDIR/calls.log"

  install_packages() {
    echo "install:$*" >> "$calls_file"
  }

  deploy_configs() {
    echo "deploy:$*" >> "$calls_file"
  }

  installer_main --dry-run --distro arch --groups core --machine workstation --home "$TEST_TMPDIR/home"

  assert_path_exists "$calls_file" "dry-run should still resolve package installation"
  assert_contains "$(cat "$calls_file")" "install:arch" "dry-run should report package installation plan"
  if grep -Fq "deploy:" "$calls_file"; then
    fail "dry-run should not deploy configs"
  fi
}



test_default_archive_url_uses_repo_fallback() {
  local resolved
  WORK_SETUP_ARCHIVE_URL=''     resolved=$(default_archive_url)
  assert_eq 'https://github.com/skyline69/work-setup/archive/refs/heads/main.tar.gz' "$resolved" 'default archive URL should point at the GitHub repo archive'
}

test_readme_uses_reachable_bootstrap_url() {
  local readme
  readme=$(cat "$ROOT_DIR/README.md")

  assert_contains "$readme" 'https://raw.githubusercontent.com/skyline69/work-setup/main/install.sh' 'README should publish a reachable raw installer URL'
}

test_standalone_installer_bootstraps_from_archive() {
  local fixture_root="$TEST_TMPDIR/archive-fixture/work-setup"
  local standalone_dir="$TEST_TMPDIR/standalone"
  local archive_path="$TEST_TMPDIR/work-setup.tar.gz"
  local output

  mkdir -p "$fixture_root/hypr/machines/workstation" "$fixture_root/quickshell" "$fixture_root/scripts/packages" "$fixture_root/scripts" "$standalone_dir"
  cp "$INSTALLER_PATH" "$standalone_dir/install.sh"
  cp "$ROOT_DIR/scripts/packages"/*.sh "$fixture_root/scripts/packages/"

  cat > "$fixture_root/install.sh" <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
printf 'fixture installer invoked\n'
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
exec "$SCRIPT_DIR/scripts/bootstrap-target.sh" "$@"
EOS
  chmod +x "$fixture_root/install.sh"

  cat > "$fixture_root/scripts/bootstrap-target.sh" <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
printf 'bootstrap target ran with %s\n' "$*"
EOS
  chmod +x "$fixture_root/scripts/bootstrap-target.sh"

  tar -C "$TEST_TMPDIR/archive-fixture" -czf "$archive_path" work-setup

  output=$(bash "$standalone_dir/install.sh" --archive-url "file://$archive_path" --dry-run --distro arch --machine workstation --yes 2>&1)
  assert_contains "$output" 'bootstrap target ran with --archive-url file://' "standalone installer should re-exec extracted archive installer"
}

test_stdin_installer_bootstraps_from_archive() {
  local fixture_root="$TEST_TMPDIR/stdin-archive-fixture/work-setup"
  local archive_path="$TEST_TMPDIR/stdin-work-setup.tar.gz"
  local output

  mkdir -p "$fixture_root/hypr/machines/workstation" "$fixture_root/quickshell" "$fixture_root/scripts/packages" "$fixture_root/scripts"
  cp "$ROOT_DIR/scripts/packages"/*.sh "$fixture_root/scripts/packages/"

  cat > "$fixture_root/install.sh" <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
printf 'stdin fixture installer invoked\n'
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
exec "$SCRIPT_DIR/scripts/bootstrap-target.sh" "$@"
EOS
  chmod +x "$fixture_root/install.sh"

  cat > "$fixture_root/scripts/bootstrap-target.sh" <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
printf 'stdin bootstrap target ran with %s\n' "$*"
EOS
  chmod +x "$fixture_root/scripts/bootstrap-target.sh"

  tar -C "$TEST_TMPDIR/stdin-archive-fixture" -czf "$archive_path" work-setup

  output=$(bash -s -- --archive-url "file://$archive_path" --dry-run --distro arch --machine workstation --yes < "$INSTALLER_PATH" 2>&1)
  assert_contains "$output" 'stdin bootstrap target ran with --archive-url file://' "stdin installer should bootstrap from archive"
}

test_quickshell_installer_delegates_to_root_installer() {
  local output
  output=$(bash "$ROOT_DIR/quickshell/install.sh" --dry-run --distro arch --groups core --machine workstation --home "$TEST_TMPDIR/home" --yes 2>&1)
  assert_contains "$output" '[INFO] Resolving package plan for distro=arch groups=core' 'quickshell installer should delegate to root installer'
}

run_tests() {
  test_detect_distro_from_os_release
  echo "ok - detect distro"
  test_resolve_package_plan_includes_supported_and_unsupported
  echo "ok - package plan"
  test_deploy_configs_creates_backup_and_active_includes
  echo "ok - deploy configs"
  test_main_dry_run_skips_deploy
  echo "ok - dry run"
  test_default_archive_url_uses_repo_fallback
  echo "ok - default archive url"
  test_readme_uses_reachable_bootstrap_url
  echo "ok - README bootstrap url"
  test_standalone_installer_bootstraps_from_archive
  echo "ok - standalone bootstrap"
  test_stdin_installer_bootstraps_from_archive
  echo "ok - stdin bootstrap"
  test_quickshell_installer_delegates_to_root_installer
  echo "ok - quickshell wrapper"
}

run_tests "$@"
