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

assert_not_contains() {
  local haystack="$1"
  local needle="$2"
  local message="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    fail "$message: unexpectedly found '$needle' in '$haystack'"
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

assert_file_contains() {
  local path="$1"
  local needle="$2"
  local message="$3"
  assert_contains "$(cat "$path")" "$needle" "$message"
}

assert_file_equals() {
  local path="$1"
  local expected="$2"
  local message="$3"
  assert_eq "$expected" "$(cat "$path")" "$message"
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
  local supported_line
  output=$(resolve_package_plan arch core,quickshell)
  supported_line=$(awk -F= '$1 == "SUPPORTED_PACKAGES" { print $2 }' <<<"$output")
  assert_contains "$output" "SUPPORTED_PACKAGES=" "package plan should include supported packages"
  assert_contains "$output" "AUR_PACKAGES=quickshell-git" "arch quickshell group should emit quickshell as an AUR package"
  assert_not_contains "$supported_line" "quickshell-git" "arch quickshell group should not send AUR packages to pacman"

  output=$(resolve_package_plan ubuntu core,quickshell)
  assert_contains "$output" "UNSUPPORTED_GROUPS=quickshell" "ubuntu should mark quickshell unsupported"
}

test_download_with_progress_supports_file_urls() {
  local source_file="$TEST_TMPDIR/source.txt"
  local destination_file="$TEST_TMPDIR/destination.txt"

  printf 'download me\n' > "$source_file"

  download_with_progress "file://$source_file" "$destination_file"

  assert_path_exists "$destination_file" "download_with_progress should write the destination file for file URLs"
  assert_file_equals "$destination_file" 'download me' "download_with_progress should preserve file contents"
}

test_download_with_progress_rejects_unsupported_urls() {
  local output
  local status

  set +e
  output=$(download_with_progress 'ftp://example.com/file.gif' "$TEST_TMPDIR/ignored.txt" 2>&1)
  status=$?
  set -e

  assert_eq '1' "$status" "download_with_progress should fail for unsupported URLs"
  assert_contains "$output" 'Unsupported download URL: ftp://example.com/file.gif' "download_with_progress should explain unsupported URLs"
}

test_download_with_progress_uses_curl_progress_for_https_urls() {
  local stub_dir="$TEST_TMPDIR/curl-stub"
  local curl_log="$TEST_TMPDIR/curl.log"
  local destination_file="$TEST_TMPDIR/https-destination.txt"

  mkdir -p "$stub_dir"

  cat > "$stub_dir/curl" <<EOF
#!/usr/bin/env bash
set -euo pipefail
log_file="$curl_log"
output_path=""
for arg in "\$@"; do
  printf '%s\n' "\$arg" >> "\$log_file"
done
while [[ \$# -gt 0 ]]; do
  case "\$1" in
    -o)
      output_path="\$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done
printf 'downloaded via curl\n' > "\$output_path"
EOF
  chmod +x "$stub_dir/curl"

  PATH="$stub_dir:$PATH" download_with_progress 'https://example.com/file.gif' "$destination_file"

  assert_path_exists "$destination_file" "download_with_progress should write the destination file for https URLs"
  assert_file_equals "$destination_file" 'downloaded via curl' "download_with_progress should use the curl stub to create the downloaded file"
  assert_file_contains "$curl_log" '-fL#' "download_with_progress should enable curl progress output for https URLs"
  assert_file_contains "$curl_log" 'https://example.com/file.gif' "download_with_progress should pass the source URL to curl"
}

test_install_packages_arch_requires_aur_helper_for_aur_packages() {
  local output
  local status

  set +e
  output=$((
    aur_helper_for_arch() {
      return 1
    }
    install_packages arch $'SUPPORTED_PACKAGES=\nAUR_PACKAGES=quickshell-git\nUNSUPPORTED_GROUPS='
  ) 2>&1)
  status=$?
  set -e

  assert_eq '1' "$status" "install_packages should fail when AUR packages are requested without an AUR helper"
  assert_contains "$output" 'AUR packages require paru or yay: quickshell-git' "install_packages should explain the missing AUR helper"
}

test_install_packages_arch_uses_paru_for_aur_packages() {
  local stub_dir="$TEST_TMPDIR/paru-stub"
  local paru_log="$TEST_TMPDIR/paru.log"
  local output

  mkdir -p "$stub_dir"
  cat > "$stub_dir/paru" <<EOF
#!/usr/bin/env bash
set -euo pipefail
for arg in "\$@"; do
  printf '%s\n' "\$arg" >> "$paru_log"
done
EOF
  chmod +x "$stub_dir/paru"

  output=$((
    aur_helper_for_arch() {
      printf 'paru\n'
    }
    PATH="$stub_dir:$PATH" install_packages arch $'SUPPORTED_PACKAGES=\nAUR_PACKAGES=quickshell-git\nUNSUPPORTED_GROUPS='
  ) 2>&1)

  assert_contains "$output" 'Installing AUR packages with paru: quickshell-git' "install_packages should announce AUR helper usage"
  assert_file_contains "$paru_log" '-S' "install_packages should invoke paru with -S"
  assert_file_contains "$paru_log" 'quickshell-git' "install_packages should pass the AUR package to paru"
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

test_list_available_wallpapers_uses_builtin_manifest() {
  local wallpapers

  wallpapers=$(list_available_wallpapers)
  assert_contains "$wallpapers" 'cozy-campfire-by-abi-toads.3840x2160.gif' 'wallpaper discovery should include cozy campfire'
  assert_contains "$wallpapers" 'zelda-pixel-art.3840x2160.gif' 'wallpaper discovery should include zelda pixel art'
}

test_default_wallpaper_selection_prefers_cozy_campfire() {
  local selected

  selected=$(default_wallpaper_basename)
  assert_eq 'cozy-campfire-by-abi-toads.3840x2160.gif' "$selected" 'default wallpaper should preserve the current cozy campfire behavior'
}

test_prompt_for_wallpaper_choice_accepts_numeric_selection() {
  local selected

  selected=$(printf '2\n' | prompt_for_wallpaper_choice 'cozy-campfire-by-abi-toads.3840x2160.gif')
  assert_eq 'zelda-pixel-art.3840x2160.gif' "$selected" 'wallpaper prompt should return the chosen numeric selection'
}

test_wallpaper_url_for_uses_release_assets() {
  local url

  url=$(wallpaper_url_for 'cozy-campfire-by-abi-toads.3840x2160.gif')
  assert_eq 'https://github.com/skyline69/work-setup/releases/download/stuff/cozy-campfire-by-abi-toads.3840x2160.gif' "$url" 'cozy campfire should resolve to the release asset URL'
}

test_deploy_wallpapers_downloads_assets_and_selection_file() {
  local fixture_dir="$TEST_TMPDIR/wallpaper-fixtures"
  local target_home="$TEST_TMPDIR/home"
  local output

  mkdir -p "$fixture_dir"
  printf 'campfire\n' > "$fixture_dir/cozy-campfire-by-abi-toads.3840x2160.gif"
  printf 'zelda\n' > "$fixture_dir/zelda-pixel-art.3840x2160.gif"

  output=$(WORK_SETUP_WALLPAPER_BASE_URL="file://$fixture_dir" deploy_wallpapers "$target_home" 'zelda-pixel-art.3840x2160.gif' 2>&1)

  assert_path_exists "$target_home/.local/share/work-setup/wallpapers/cozy-campfire-by-abi-toads.3840x2160.gif" 'wallpaper deploy should install cozy campfire asset'
  assert_path_exists "$target_home/.local/share/work-setup/wallpapers/zelda-pixel-art.3840x2160.gif" 'wallpaper deploy should install zelda asset'
  assert_file_contains "$target_home/.config/work-setup/wallpaper.env" 'WORK_SETUP_WALLPAPER_BASENAME=zelda-pixel-art.3840x2160.gif' 'wallpaper deploy should persist the selected wallpaper basename'
  assert_contains "$output" 'Downloading wallpaper 1/2: cozy-campfire-by-abi-toads.3840x2160.gif' 'wallpaper deploy should log the first wallpaper download start'
  assert_contains "$output" 'Downloaded wallpaper 2/2: zelda-pixel-art.3840x2160.gif' 'wallpaper deploy should log the last wallpaper download completion'
}

test_main_dry_run_reports_wallpaper_selection() {
  local output

  output=$(installer_main --dry-run --distro arch --groups wallpaper --machine workstation --home "$TEST_TMPDIR/home" --yes 2>&1)
  assert_contains "$output" 'Selected wallpaper:' 'installer summary should mention wallpaper selection'
  assert_contains "$output" 'cozy-campfire-by-abi-toads.3840x2160.gif' 'installer should default to the cozy wallpaper during unattended dry runs'
}

test_main_dry_run_skips_deploy() {
  local calls_file="$TEST_TMPDIR/calls.log"

  (
    install_packages() {
      echo "install:$*" >> "$calls_file"
    }

    deploy_configs() {
      echo "deploy:$*" >> "$calls_file"
    }

    installer_main --dry-run --distro arch --groups core --machine workstation --home "$TEST_TMPDIR/home"
  )

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

test_colorized_log_output_can_be_enabled() {
  local output
  local had_no_color=false
  local original_no_color=''

  if [[ -n "${NO_COLOR+x}" ]]; then
    had_no_color=true
    original_no_color="$NO_COLOR"
    unset NO_COLOR
  fi

  FORCE_COLOR=1
  output=$(log INFO "Styled message")
  unset FORCE_COLOR
  if $had_no_color; then
    NO_COLOR="$original_no_color"
  fi
  assert_contains "$output" $'\033[' 'log output should include ANSI escapes when color is forced'
  assert_contains "$output" 'Styled message' 'log output should include the message body'
}

test_main_dry_run_uses_human_friendly_summary() {
  local output

  output=$(installer_main --dry-run --distro arch --groups core,quickshell --machine workstation --home "$TEST_TMPDIR/home" --yes 2>&1)
  assert_contains "$output" 'Work Setup Installer' 'installer should print a startup banner'
  assert_contains "$output" 'Package Summary' 'installer should print a labeled package summary'
  assert_contains "$output" 'Supported packages:' 'installer should render supported packages in user-facing language'
  assert_not_contains "$output" 'SUPPORTED_PACKAGES=' 'installer should not print raw package-plan variables'
}

test_interactive_prompt_is_styled() {
  local output

  output=$(printf 'n\n' | installer_main --distro arch --groups core --machine workstation --home "$TEST_TMPDIR/home" 2>&1)
  assert_contains "$output" 'Continue with package installation and config deployment?' 'interactive prompt should use the richer confirmation text'
  assert_contains "$output" 'Cancelled by user choice' 'installer should acknowledge user cancellation clearly'
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

test_sigint_during_prompt_exits_cleanly() {
  local output_file="$TEST_TMPDIR/sigint-output.log"
  local fifo="$TEST_TMPDIR/sigint-input.fifo"
  local status

  mkfifo "$fifo"
  exec 3<>"$fifo"

  set +e
  timeout --preserve-status -s INT 0.2 bash "$INSTALLER_PATH" --distro arch --groups core --machine workstation --home "$TEST_TMPDIR/home" < "$fifo" >"$output_file" 2>&1
  status=$?
  set -e

  exec 3>&-

  assert_eq '130' "$status" 'installer should exit with 130 when interrupted'
  assert_contains "$(cat "$output_file")" 'Installation cancelled by Ctrl+C' 'installer should print a dedicated interrupt message'
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
  test_download_with_progress_supports_file_urls
  echo "ok - downloader file urls"
  test_download_with_progress_rejects_unsupported_urls
  echo "ok - downloader unsupported urls"
  test_download_with_progress_uses_curl_progress_for_https_urls
  echo "ok - downloader https curl"
  test_install_packages_arch_requires_aur_helper_for_aur_packages
  echo "ok - aur helper required"
  test_install_packages_arch_uses_paru_for_aur_packages
  echo "ok - aur helper paru"
  test_deploy_configs_creates_backup_and_active_includes
  echo "ok - deploy configs"
  test_list_available_wallpapers_uses_builtin_manifest
  echo "ok - list wallpapers"
  test_default_wallpaper_selection_prefers_cozy_campfire
  echo "ok - default wallpaper selection"
  test_prompt_for_wallpaper_choice_accepts_numeric_selection
  echo "ok - prompt wallpaper choice"
  test_wallpaper_url_for_uses_release_assets
  echo "ok - wallpaper release url"
  test_deploy_wallpapers_downloads_assets_and_selection_file
  echo "ok - deploy wallpapers"
  test_main_dry_run_skips_deploy
  echo "ok - dry run"
  test_main_dry_run_reports_wallpaper_selection
  echo "ok - wallpaper summary"
  test_default_archive_url_uses_repo_fallback
  echo "ok - default archive url"
  test_readme_uses_reachable_bootstrap_url
  echo "ok - README bootstrap url"
  test_colorized_log_output_can_be_enabled
  echo "ok - colorized log output"
  test_main_dry_run_uses_human_friendly_summary
  echo "ok - human friendly summary"
  test_interactive_prompt_is_styled
  echo "ok - styled prompt"
  test_standalone_installer_bootstraps_from_archive
  echo "ok - standalone bootstrap"
  test_stdin_installer_bootstraps_from_archive
  echo "ok - stdin bootstrap"
  test_sigint_during_prompt_exits_cleanly
  echo "ok - sigint handler"
  test_quickshell_installer_delegates_to_root_installer
  echo "ok - quickshell wrapper"
}

run_tests "$@"
