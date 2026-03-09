#!/usr/bin/env bash
set -euo pipefail

SCRIPT_PATH="${BASH_SOURCE[0]-}"
RUNNING_FROM_STDIN=false

if [[ -n "$SCRIPT_PATH" && "$SCRIPT_PATH" != "bash" ]]; then
  SCRIPT_DIR=$(cd "$(dirname "$SCRIPT_PATH")" && pwd)
else
  SCRIPT_DIR=$(pwd)
  RUNNING_FROM_STDIN=true
fi

REPO_ROOT="$SCRIPT_DIR"
DEFAULT_GROUPS="core,quickshell,fonts,media,wallpaper,apps"
INSTALL_MODE="symlink"
AUTO_CONFIRM=false
DRY_RUN=false
SELECTED_DISTRO="auto"
SELECTED_GROUPS="$DEFAULT_GROUPS"
SELECTED_WALLPAPER=''
DEFAULT_ARCHIVE_URL="https://github.com/skyline69/work-setup/archive/refs/heads/main.tar.gz"
ARCHIVE_URL="${WORK_SETUP_ARCHIVE_URL:-}"
DEFAULT_WALLPAPER_BASENAME='cozy-campfire-by-abi-toads.3840x2160.gif'

COLOR_RESET=''
COLOR_BOLD=''
COLOR_INFO=''
COLOR_WARN=''
COLOR_ERROR=''
COLOR_SUCCESS=''
COLOR_ACCENT=''

setup_colors() {
  local use_color=false

  if [[ -n "${NO_COLOR:-}" ]]; then
    use_color=false
  elif [[ -n "${FORCE_COLOR:-}" && "${FORCE_COLOR:-}" != "0" ]]; then
    use_color=true
  elif [[ -t 1 || -t 2 ]]; then
    use_color=true
  fi

  if $use_color; then
    COLOR_RESET=$'\033[0m'
    COLOR_BOLD=$'\033[1m'
    COLOR_INFO=$'\033[38;5;111m'
    COLOR_WARN=$'\033[38;5;221m'
    COLOR_ERROR=$'\033[38;5;203m'
    COLOR_SUCCESS=$'\033[38;5;150m'
    COLOR_ACCENT=$'\033[38;5;117m'
  else
    COLOR_RESET=''
    COLOR_BOLD=''
    COLOR_INFO=''
    COLOR_WARN=''
    COLOR_ERROR=''
    COLOR_SUCCESS=''
    COLOR_ACCENT=''
  fi
}

style_for_level() {
  case "$1" in
    INFO) printf '%s' "$COLOR_INFO" ;;
    WARN) printf '%s' "$COLOR_WARN" ;;
    ERROR) printf '%s' "$COLOR_ERROR" ;;
    SUCCESS) printf '%s' "$COLOR_SUCCESS" ;;
    BOOTSTRAP) printf '%s' "$COLOR_ACCENT" ;;
    *) printf '%s' "$COLOR_BOLD" ;;
  esac
}

bootstrap_log() {
  local style
  setup_colors
  style=$(style_for_level BOOTSTRAP)
  printf '%b[%s]%b %s\n' "${COLOR_BOLD}${style}" "BOOTSTRAP" "$COLOR_RESET" "$1" >&2
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

restore_bootstrap_stdin_if_needed() {
  local tty_path="${WORK_SETUP_TTY_PATH:-/dev/tty}"

  if [[ -t 0 ]]; then
    return 0
  fi

  if [[ -z "${WORK_SETUP_TTY_PATH:-}" && ! -t 1 && ! -t 2 ]]; then
    return 0
  fi

  if [[ ! -r "$tty_path" ]]; then
    return 0
  fi

  bootstrap_log "Restoring stdin from $tty_path for interactive commands"
  exec < "$tty_path"
}

has_local_source_tree() {
  if $RUNNING_FROM_STDIN; then
    return 1
  fi

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

download_with_progress() {
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
        curl -fL# "$source_url" -o "$destination"
      elif command -v wget >/dev/null 2>&1; then
        wget --progress=bar:force:noscroll -O "$destination" "$source_url"
      else
        log ERROR "Neither curl nor wget is available for downloading $source_url" >&2
        return 1
      fi
      ;;
    *)
      log ERROR "Unsupported download URL: $source_url" >&2
      return 1
      ;;
  esac
}

wallpaper_url_for() {
  local wallpaper_basename="$1"

  if [[ -n "${WORK_SETUP_WALLPAPER_BASE_URL:-}" ]]; then
    printf '%s/%s\n' "${WORK_SETUP_WALLPAPER_BASE_URL%/}" "$wallpaper_basename"
    return 0
  fi

  case "$wallpaper_basename" in
    cozy-campfire-by-abi-toads.3840x2160.gif)
      printf '%s\n' 'https://github.com/skyline69/work-setup/releases/download/stuff/cozy-campfire-by-abi-toads.3840x2160.gif'
      ;;
    zelda-pixel-art.3840x2160.gif)
      printf '%s\n' 'https://github.com/skyline69/work-setup/releases/download/stuff/zelda-pixel-art.3840x2160.gif'
      ;;
    *)
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

  restore_bootstrap_stdin_if_needed
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
  local level="$1"
  local message="$2"
  local style

  setup_colors
  style=$(style_for_level "$level")
  printf '%b[%s]%b %s\n' "${COLOR_BOLD}${style}" "$level" "$COLOR_RESET" "$message"
}

print_banner() {
  setup_colors
  printf '\n'
  printf '%b%s%b\n' "${COLOR_BOLD}${COLOR_ACCENT}" "== Work Setup Installer ==" "$COLOR_RESET"
  printf '%s\n' "Hyprland + Quickshell bootstrap and config deploy"
  printf '\n'
}

print_section() {
  setup_colors
  printf '\n%b%s%b\n' "${COLOR_BOLD}${COLOR_ACCENT}" "$1" "$COLOR_RESET"
}

format_csv_as_list() {
  local csv="$1"

  if [[ -z "$csv" ]]; then
    printf 'none'
    return 0
  fi

  awk -v csv="$csv" 'BEGIN {
    n = split(csv, parts, ",")
    for (i = 1; i <= n; i++) {
      if (parts[i] == "") {
        continue
      }
      if (printed > 0) {
        printf ", "
      }
      printf "%s", parts[i]
      printed++
    }
    if (printed == 0) {
      printf "none"
    }
  }'
}

print_package_summary() {
  local distro="$1"
  local groups_csv="$2"
  local package_plan="$3"
  local selected_wallpaper="${4:-}"
  local packages_line unsupported_line

  packages_line=$(awk -F= '$1 == "SUPPORTED_PACKAGES" { print $2 }' <<<"$package_plan")
  unsupported_line=$(awk -F= '$1 == "UNSUPPORTED_GROUPS" { print $2 }' <<<"$package_plan")

  print_section "Package Summary"
  printf 'Distro: %s\n' "$distro"
  printf 'Groups: %s\n' "$(format_csv_as_list "$groups_csv")"
  printf 'Supported packages: %s\n' "${packages_line:-none}"
  printf 'Unsupported groups: %s\n' "$(format_csv_as_list "$unsupported_line")"
  if [[ -n "$selected_wallpaper" ]]; then
    printf 'Selected wallpaper: %s\n' "$selected_wallpaper"
  fi
}

confirm_installation() {
  local reply

  print_section "Ready To Install"
  printf 'Continue with package installation and config deployment? [y/N]: '
  if ! read -r reply; then
    printf '\n'
    log WARN "Cancelled because confirmation was not received"
    return 1
  fi

  [[ "$reply" =~ ^[Yy]$ ]]
}

handle_interrupt() {
  printf '\n'
  log WARN "Installation cancelled by Ctrl+C"
  exit 130
}

trap handle_interrupt INT

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

csv_has_value() {
  local csv="$1"
  local expected="$2"
  local entry

  while IFS= read -r entry; do
    [[ "$entry" == "$expected" ]] && return 0
  done < <(split_csv "$csv")

  return 1
}

list_available_wallpapers() {
  printf '%s\n' \
    'cozy-campfire-by-abi-toads.3840x2160.gif' \
    'zelda-pixel-art.3840x2160.gif'
}

wallpaper_exists() {
  local wallpaper_basename="$1"

  list_available_wallpapers | grep -Fxq "$wallpaper_basename"
}

default_wallpaper_basename() {
  local fallback

  if wallpaper_exists "$DEFAULT_WALLPAPER_BASENAME"; then
    printf '%s\n' "$DEFAULT_WALLPAPER_BASENAME"
    return 0
  fi

  fallback=$(list_available_wallpapers | head -n 1 || true)
  if [[ -n "$fallback" ]]; then
    printf '%s\n' "$fallback"
  fi
}

prompt_for_wallpaper_choice() {
  local default_wallpaper="$1"
  local reply index
  local -a wallpapers=()

  mapfile -t wallpapers < <(list_available_wallpapers)
  if [[ "${#wallpapers[@]}" -eq 0 ]]; then
    return 0
  fi

  while true; do
    setup_colors
    printf '\n%b%s%b\n' "${COLOR_BOLD}${COLOR_ACCENT}" "Wallpaper Choice" "$COLOR_RESET" >&2
    for index in "${!wallpapers[@]}"; do
      if [[ "${wallpapers[$index]}" == "$default_wallpaper" ]]; then
        printf '%s. %s (default)\n' "$((index + 1))" "${wallpapers[$index]}" >&2
      else
        printf '%s. %s\n' "$((index + 1))" "${wallpapers[$index]}" >&2
      fi
    done

    printf 'Selection [1-%s, Enter for default]: ' "${#wallpapers[@]}" >&2
    if ! read -r reply; then
      printf '\n' >&2
      printf '%s\n' "$default_wallpaper"
      return 0
    fi

    if [[ -z "$reply" ]]; then
      printf '%s\n' "$default_wallpaper"
      return 0
    fi

    if [[ "$reply" =~ ^[0-9]+$ ]] && (( reply >= 1 && reply <= ${#wallpapers[@]} )); then
      printf '%s\n' "${wallpapers[$((reply - 1))]}"
      return 0
    fi

    printf 'Invalid selection. Choose a number between 1 and %s.\n' "${#wallpapers[@]}" >&2
  done
}

resolve_selected_wallpaper() {
  local requested_wallpaper="$1"
  local prompt_for_choice="$2"
  local default_wallpaper

  default_wallpaper=$(default_wallpaper_basename)
  if [[ -z "$default_wallpaper" ]]; then
    return 0
  fi

  if [[ -n "$requested_wallpaper" ]]; then
    if ! wallpaper_exists "$requested_wallpaper"; then
      log ERROR "Unknown wallpaper: $requested_wallpaper" >&2
      return 1
    fi

    printf '%s\n' "$requested_wallpaper"
    return 0
  fi

  if $prompt_for_choice; then
    prompt_for_wallpaper_choice "$default_wallpaper"
    return 0
  fi

  printf '%s\n' "$default_wallpaper"
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

aur_packages_for_group() {
  local distro="$1"
  local group="$2"

  "aur_packages_for_group_${distro}" "$group"
}

resolve_package_plan() {
  local distro="$1"
  local groups_csv="$2"
  local -a supported_packages=()
  local -a aur_packages=()
  local -a unsupported_groups=()
  local group

  while IFS= read -r group; do
    if package_group_supported "$distro" "$group"; then
      while IFS= read -r pkg; do
        [[ -n "$pkg" ]] || continue
        supported_packages+=("$pkg")
      done < <(packages_for_group "$distro" "$group")
      while IFS= read -r pkg; do
        [[ -n "$pkg" ]] || continue
        aur_packages+=("$pkg")
      done < <(aur_packages_for_group "$distro" "$group")
    else
      unsupported_groups+=("$group")
    fi
  done < <(split_csv "$groups_csv")

  printf 'SUPPORTED_PACKAGES=%s\n' "$(printf '%s\n' "${supported_packages[@]}" | awk '!seen[$0]++' | join_by_space)"
  printf 'AUR_PACKAGES=%s\n' "$(printf '%s\n' "${aur_packages[@]}" | awk '!seen[$0]++' | join_by_space)"
  printf 'UNSUPPORTED_GROUPS=%s\n' "$(printf '%s\n' "${unsupported_groups[@]}" | join_by_comma)"
}

aur_helper_for_arch() {
  if command -v paru >/dev/null 2>&1; then
    printf 'paru\n'
    return 0
  fi

  if command -v yay >/dev/null 2>&1; then
    printf 'yay\n'
    return 0
  fi

  return 1
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

wallpaper_target_dir_for() {
  local target_home="$1"
  printf '%s/.local/share/work-setup/wallpapers\n' "$target_home"
}

wallpaper_selection_file_for() {
  local target_home="$1"
  printf '%s/.config/work-setup/wallpaper.env\n' "$target_home"
}

deploy_wallpapers() {
  local target_home="$1"
  local selected_wallpaper="$2"
  local target_dir
  local selection_file
  local selection_dir
  local selected_path
  local staging_dir
  local wallpaper_basename
  local wallpaper_url
  local index=0
  local total

  if [[ -z "$selected_wallpaper" ]]; then
    log WARN "Skipping wallpaper deploy; no wallpaper selected"
    return 0
  fi

  target_dir=$(wallpaper_target_dir_for "$target_home")
  selection_file=$(wallpaper_selection_file_for "$target_home")
  selection_dir=$(dirname "$selection_file")
  total=$(list_available_wallpapers | sed '/^$/d' | wc -l | tr -d ' ')

  mkdir -p "$(dirname "$target_dir")" "$selection_dir"
  staging_dir=$(mktemp -d)
  trap 'rm -rf "$staging_dir"' RETURN

  while IFS= read -r wallpaper_basename; do
    [[ -n "$wallpaper_basename" ]] || continue
    index=$((index + 1))
    wallpaper_url=$(wallpaper_url_for "$wallpaper_basename") || {
      log ERROR "Missing release asset URL for wallpaper: $wallpaper_basename" >&2
      return 1
    }

    log INFO "Downloading wallpaper ${index}/${total}: $wallpaper_basename"
    download_with_progress "$wallpaper_url" "$staging_dir/$wallpaper_basename"
    log SUCCESS "Downloaded wallpaper ${index}/${total}: $wallpaper_basename"
  done < <(list_available_wallpapers)

  backup_if_present "$target_dir"
  mv "$staging_dir" "$target_dir"
  trap - RETURN
  selected_path="$target_dir/$selected_wallpaper"
  [[ -f "$selected_path" ]] || {
    log ERROR "Selected wallpaper was not deployed: $selected_path" >&2
    return 1
  }

  cat > "$selection_file" <<EOF
WORK_SETUP_WALLPAPER_BASENAME=$(printf '%q' "$selected_wallpaper")
WORK_SETUP_WALLPAPER_PATH=$(printf '%q' "$selected_path")
EOF

  log INFO "Installed wallpapers to $target_dir"
  log INFO "Selected wallpaper: $selected_wallpaper"
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
  local packages_line aur_packages_line unsupported_line
  local package_manager
  local aur_helper=''
  local -a packages=()
  local -a aur_packages=()

  packages_line=$(awk -F= '$1 == "SUPPORTED_PACKAGES" { print $2 }' <<<"$package_plan")
  aur_packages_line=$(awk -F= '$1 == "AUR_PACKAGES" { print $2 }' <<<"$package_plan")
  unsupported_line=$(awk -F= '$1 == "UNSUPPORTED_GROUPS" { print $2 }' <<<"$package_plan")
  package_manager=$(package_manager_for "$distro")

  if [[ -n "$unsupported_line" ]]; then
    log WARN "Unsupported groups on $distro: $unsupported_line"
  fi

  [[ -n "$packages_line" ]] && read -r -a packages <<<"$packages_line"
  [[ -n "$aur_packages_line" ]] && read -r -a aur_packages <<<"$aur_packages_line"
  if $DRY_RUN; then
    if [[ "${#packages[@]}" -gt 0 ]]; then
      log INFO "Dry run: $package_manager ${packages[*]}"
    fi
    if [[ "$distro" == arch && "${#aur_packages[@]}" -gt 0 ]]; then
      aur_helper=$(aur_helper_for_arch || true)
      if [[ -z "$aur_helper" ]]; then
        aur_helper='paru'
      fi
      log INFO "Dry run: $aur_helper ${aur_packages[*]}"
    fi
    if [[ "${#packages[@]}" -eq 0 && "${#aur_packages[@]}" -eq 0 ]]; then
      log WARN "No supported packages resolved for $distro"
    fi
    return 0
  fi

  case "$distro" in
    arch)
      if [[ "${#packages[@]}" -gt 0 ]]; then
        log INFO "Installing pacman packages: ${packages[*]}"
        sudo -v
        sudo pacman -S --needed --noconfirm "${packages[@]}"
      fi
      if [[ "${#aur_packages[@]}" -gt 0 ]]; then
        aur_helper=$(aur_helper_for_arch) || {
          log ERROR "AUR packages require paru or yay: ${aur_packages[*]}" >&2
          return 1
        }
        log INFO "Installing AUR packages with $aur_helper: ${aur_packages[*]}"
        "$aur_helper" -S --needed --noconfirm "${aur_packages[@]}"
      fi
      ;;
    fedora)
      if [[ "${#packages[@]}" -eq 0 ]]; then
        log WARN "No supported packages resolved for $distro"
        return 0
      fi
      log INFO "Installing dnf packages: ${packages[*]}"
      sudo dnf install -y "${packages[@]}"
      ;;
    ubuntu)
      if [[ "${#packages[@]}" -eq 0 ]]; then
        log WARN "No supported packages resolved for $distro"
        return 0
      fi
      log INFO "Installing apt packages: ${packages[*]}"
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
  --wallpaper <basename>
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
  local wallpaper_selected=false
  local prompt_for_wallpaper=false

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
      --wallpaper)
        SELECTED_WALLPAPER="$2"
        shift 2
        ;;
      --wallpaper=*)
        SELECTED_WALLPAPER="${arg#--wallpaper=}"
        shift
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

  print_banner

  if csv_has_value "$SELECTED_GROUPS" wallpaper; then
    wallpaper_selected=true
    if ! $AUTO_CONFIRM; then
      prompt_for_wallpaper=true
    fi

    SELECTED_WALLPAPER=$(resolve_selected_wallpaper "$SELECTED_WALLPAPER" "$prompt_for_wallpaper")
  fi

  log INFO "Resolving package plan for distro=$SELECTED_DISTRO groups=$SELECTED_GROUPS"
  package_plan=$(resolve_package_plan "$SELECTED_DISTRO" "$SELECTED_GROUPS")
  print_package_summary "$SELECTED_DISTRO" "$SELECTED_GROUPS" "$package_plan" "$SELECTED_WALLPAPER"

  if ! $AUTO_CONFIRM && ! $DRY_RUN; then
    if ! confirm_installation; then
      log INFO "Cancelled by user choice"
      return 0
    fi
  fi

  install_packages "$SELECTED_DISTRO" "$package_plan"
  if $DRY_RUN; then
    if $wallpaper_selected && [[ -n "$SELECTED_WALLPAPER" ]]; then
      log INFO "Dry run: would install wallpapers to $(wallpaper_target_dir_for "$target_home")"
    fi
    log INFO "Dry run: skipping config deployment"
    return 0
  fi

  deploy_configs "$REPO_ROOT" "$target_home" "$machine_name" "$INSTALL_MODE"
  if $wallpaper_selected; then
    deploy_wallpapers "$target_home" "$SELECTED_WALLPAPER"
  fi

  log SUCCESS "Install complete"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
