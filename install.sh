#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT="$SCRIPT_DIR"
DEFAULT_GROUPS="core,quickshell,fonts,media,wallpaper,apps"
INSTALL_MODE="symlink"
AUTO_CONFIRM=false
DRY_RUN=false
SELECTED_DISTRO="auto"
SELECTED_GROUPS="$DEFAULT_GROUPS"
DEFAULT_ARCHIVE_URL="https://github.com/skyline69/work-setup/archive/refs/heads/main.tar.gz"
ARCHIVE_URL="${WORK_SETUP_ARCHIVE_URL:-}"

bootstrap_log() {
  printf '[BOOTSTRAP] %s\n' "$1" >&2
}

parse_archive_url_arg() {
  local expect_value=false
  local arg

  for arg in "$@"; do
    if $expect_value; then
      printf '%s\n' "$arg"
      return 0
    fi

    case "$arg" in
      --archive-url)
        expect_value=true
        ;;
      --archive-url=*)
        printf '%s\n' "${arg#--archive-url=}"
        return 0
        ;;
    esac
  done

  return 1
}

default_archive_url() {
  if [[ -n "${WORK_SETUP_ARCHIVE_URL:-}" ]]; then
    printf '%s
' "$WORK_SETUP_ARCHIVE_URL"
    return 0
  fi

  printf '%s
' "$DEFAULT_ARCHIVE_URL"
}

has_local_source_tree() {
  [[ -d "$SCRIPT_DIR/hypr" ]] && [[ -d "$SCRIPT_DIR/quickshell" ]] && [[ -f "$SCRIPT_DIR/scripts/packages/arch.sh" ]]
}

download_archive() {
  local source_url="$1"
  local destination="$2"

  case "$source_url" in
    file://*)
      cp "${source_url#file://}" "$destination"
      ;;
    /*)
      cp "$source_url" "$destination"
      ;;
    http://*|https://*)
      if command -v curl >/dev/null 2>&1; then
        curl -fsSL "$source_url" -o "$destination"
      elif command -v wget >/dev/null 2>&1; then
        wget -qO "$destination" "$source_url"
      else
        bootstrap_log "Neither curl nor wget is available for downloading $source_url"
        return 1
      fi
      ;;
    *)
      bootstrap_log "Unsupported archive URL: $source_url"
      return 1
      ;;
  esac
}

find_extracted_repo_root() {
  local search_root="$1"
  local candidate

  while IFS= read -r candidate; do
    candidate=$(dirname "$candidate")
    if [[ -d "$candidate/hypr" ]] && [[ -d "$candidate/quickshell" ]] && [[ -f "$candidate/scripts/packages/arch.sh" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done < <(find "$search_root" -maxdepth 4 -type f -name install.sh | sort)

  return 1
}

bootstrap_from_archive_if_needed() {
  local parsed_archive_url=""
  local bootstrap_dir archive_path extracted_root

  if parsed_archive_url=$(parse_archive_url_arg "$@"); then
    ARCHIVE_URL="$parsed_archive_url"
  fi

  if has_local_source_tree; then
    return 0
  fi

  if [[ -z "$ARCHIVE_URL" ]]; then
    ARCHIVE_URL=$(default_archive_url)
  fi

  bootstrap_dir=$(mktemp -d)
  archive_path="$bootstrap_dir/work-setup.tar.gz"
  bootstrap_log "Downloading archive from $ARCHIVE_URL"
  download_archive "$ARCHIVE_URL" "$archive_path"
  tar -xzf "$archive_path" -C "$bootstrap_dir"

  extracted_root=$(find_extracted_repo_root "$bootstrap_dir") || {
    bootstrap_log "Could not find a valid extracted work-setup tree in $ARCHIVE_URL"
    exit 1
  }

  bootstrap_log "Re-executing installer from $extracted_root"
  exec "$extracted_root/install.sh" "$@"
}

bootstrap_from_archive_if_needed "$@"

# shellcheck source=/dev/null
source "$SCRIPT_DIR/scripts/packages/arch.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/scripts/packages/fedora.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/scripts/packages/ubuntu.sh"

log() {
  printf '[%s] %s\n' "$1" "$2"
}

detect_distro() {
  local os_release="${1:-/etc/os-release}"
  local distro

  distro=$(awk -F= '$1 == "ID" { gsub(/"/, "", $2); print $2 }' "$os_release")
  if [[ -z "$distro" ]]; then
    log ERROR "Unable to detect distro from $os_release" >&2
    return 1
  fi

  printf '%s\n' "$distro"
}

split_csv() {
  local csv="$1"
  tr ',' '\n' <<<"$csv" | sed '/^$/d'
}

join_by_space() {
  paste -sd' ' -
}

join_by_comma() {
  paste -sd',' -
}

package_group_supported() {
  local distro="$1"
  local group="$2"

  "package_group_supported_${distro}" "$group"
}

packages_for_group() {
  local distro="$1"
  local group="$2"

  "packages_for_group_${distro}" "$group"
}

resolve_package_plan() {
  local distro="$1"
  local groups_csv="$2"
  local -a supported_packages=()
  local -a unsupported_groups=()
  local group

  while IFS= read -r group; do
    if package_group_supported "$distro" "$group"; then
      while IFS= read -r pkg; do
        [[ -n "$pkg" ]] || continue
        supported_packages+=("$pkg")
      done < <(packages_for_group "$distro" "$group")
    else
      unsupported_groups+=("$group")
    fi
  done < <(split_csv "$groups_csv")

  printf 'SUPPORTED_PACKAGES=%s\n' "$(printf '%s\n' "${supported_packages[@]}" | awk '!seen[$0]++' | join_by_space)"
  printf 'UNSUPPORTED_GROUPS=%s\n' "$(printf '%s\n' "${unsupported_groups[@]}" | join_by_comma)"
}

backup_path_for() {
  local path="$1"
  local backup="${path}.backup"

  if [[ ! -e "$backup" ]]; then
    printf '%s\n' "$backup"
    return 0
  fi

  printf '%s.%s\n' "$backup" "$(date +%Y%m%d%H%M%S)"
}

backup_if_present() {
  local path="$1"
  local backup

  [[ -e "$path" ]] || return 0

  backup=$(backup_path_for "$path")
  mv "$path" "$backup"
  log INFO "Backed up $path to $backup"
}

link_or_copy() {
  local source_path="$1"
  local target_path="$2"
  local mode="$3"

  rm -rf "$target_path"
  case "$mode" in
    symlink)
      ln -s "$source_path" "$target_path"
      ;;
    copy)
      cp -a "$source_path" "$target_path"
      ;;
    *)
      log ERROR "Unsupported deploy mode: $mode" >&2
      return 1
      ;;
  esac
}

write_active_include() {
  local hypr_repo="$1"
  local machine_name="$2"
  local section="$3"
  local machine_file="$hypr_repo/machines/$machine_name/$section.conf"
  local active_dir="$hypr_repo/active"
  local active_file="$active_dir/$section.conf"

  [[ -f "$machine_file" ]] || {
    log ERROR "Missing machine overlay file: $machine_file" >&2
    return 1
  }

  mkdir -p "$active_dir"
  printf 'source = ~/.config/hypr/machines/%s/%s.conf\n' "$machine_name" "$section" > "$active_file"
}

activate_machine_overlay() {
  local hypr_repo="$1"
  local machine_name="$2"
  local section

  for section in monitors environment autostart programs; do
    write_active_include "$hypr_repo" "$machine_name" "$section"
  done
}

deploy_configs() {
  local repo_root="$1"
  local target_home="$2"
  local machine_name="$3"
  local mode="${4:-symlink}"
  local hypr_repo="$repo_root/hypr"
  local quickshell_repo="$repo_root/quickshell"
  local config_root="$target_home/.config"

  mkdir -p "$config_root"
  activate_machine_overlay "$hypr_repo" "$machine_name"

  backup_if_present "$config_root/hypr"
  link_or_copy "$hypr_repo" "$config_root/hypr" "$mode"

  if [[ -d "$quickshell_repo" ]]; then
    backup_if_present "$config_root/quickshell"
    link_or_copy "$quickshell_repo" "$config_root/quickshell" "$mode"
  else
    log WARN "Skipping quickshell deploy; repo directory not found at $quickshell_repo"
  fi
}

package_manager_for() {
  case "$1" in
    arch)
      printf 'pacman\n'
      ;;
    fedora)
      printf 'dnf\n'
      ;;
    ubuntu)
      printf 'apt-get\n'
      ;;
    *)
      return 1
      ;;
  esac
}

install_packages() {
  local distro="$1"
  local package_plan="$2"
  local packages_line unsupported_line
  local package_manager
  local -a packages=()

  packages_line=$(awk -F= '$1 == "SUPPORTED_PACKAGES" { print $2 }' <<<"$package_plan")
  unsupported_line=$(awk -F= '$1 == "UNSUPPORTED_GROUPS" { print $2 }' <<<"$package_plan")
  package_manager=$(package_manager_for "$distro")

  if [[ -n "$unsupported_line" ]]; then
    log WARN "Unsupported groups on $distro: $unsupported_line"
  fi

  if [[ -z "$packages_line" ]]; then
    log WARN "No supported packages resolved for $distro"
    return 0
  fi

  read -r -a packages <<<"$packages_line"
  if $DRY_RUN; then
    log INFO "Dry run: $package_manager ${packages[*]}"
    return 0
  fi

  case "$distro" in
    arch)
      sudo pacman -S --needed --noconfirm "${packages[@]}"
      ;;
    fedora)
      sudo dnf install -y "${packages[@]}"
      ;;
    ubuntu)
      sudo apt-get update
      sudo apt-get install -y "${packages[@]}"
      ;;
  esac
}

usage() {
  cat <<USAGE
Usage: $(basename "$0") [options]

Options:
  --archive-url <url-or-file>
  --distro <auto|arch|fedora|ubuntu>
  --groups <comma-separated groups>
  --no-quickshell
  --copy
  --symlink
  --dry-run
  --yes
  --machine <hostname>
  --home <path>
  -h, --help

Environment:
  WORK_SETUP_ARCHIVE_URL  Override archive URL or local file path used when install.sh runs without the full repo tree.
USAGE
}

main() {
  local machine_name="${HOSTNAME:-$(uname -n)}"
  local target_home="$HOME"
  local arg
  local package_plan

  while [[ $# -gt 0 ]]; do
    arg="$1"
    case "$arg" in
      --archive-url)
        ARCHIVE_URL="$2"
        shift 2
        ;;
      --archive-url=*)
        ARCHIVE_URL="${arg#--archive-url=}"
        shift
        ;;
      --distro)
        SELECTED_DISTRO="$2"
        shift 2
        ;;
      --groups)
        SELECTED_GROUPS="$2"
        shift 2
        ;;
      --no-quickshell)
        SELECTED_GROUPS=$(split_csv "$SELECTED_GROUPS" | grep -vx 'quickshell' | join_by_comma || true)
        shift
        ;;
      --copy)
        INSTALL_MODE="copy"
        shift
        ;;
      --symlink)
        INSTALL_MODE="symlink"
        shift
        ;;
      --dry-run)
        DRY_RUN=true
        shift
        ;;
      --yes)
        AUTO_CONFIRM=true
        shift
        ;;
      --machine)
        machine_name="$2"
        shift 2
        ;;
      --home)
        target_home="$2"
        shift 2
        ;;
      -h|--help)
        usage
        return 0
        ;;
      *)
        log ERROR "Unknown option: $arg" >&2
        usage >&2
        return 1
        ;;
    esac
  done

  if [[ "$SELECTED_DISTRO" == "auto" ]]; then
    SELECTED_DISTRO=$(detect_distro)
  fi

  log INFO "Resolving package plan for distro=$SELECTED_DISTRO groups=$SELECTED_GROUPS"
  package_plan=$(resolve_package_plan "$SELECTED_DISTRO" "$SELECTED_GROUPS")
  printf '%s\n' "$package_plan"

  if ! $AUTO_CONFIRM && ! $DRY_RUN; then
    read -r -p "Proceed with package installation and config deployment? [y/N] " reply
    [[ "$reply" =~ ^[Yy]$ ]] || {
      log INFO "Aborted"
      return 0
    }
  fi

  install_packages "$SELECTED_DISTRO" "$package_plan"
  if $DRY_RUN; then
    log INFO "Dry run: skipping config deployment"
    return 0
  fi

  deploy_configs "$REPO_ROOT" "$target_home" "$machine_name" "$INSTALL_MODE"

  log INFO "Install complete"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
