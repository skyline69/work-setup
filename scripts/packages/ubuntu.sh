#!/usr/bin/env bash

package_group_supported_ubuntu() {
  case "$1" in
    core|fonts|media|wallpaper|apps)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

packages_for_group_ubuntu() {
  case "$1" in
    core)
      printf '%s\n' hyprland hyprlock xdg-desktop-portal-hyprland rofi-wayland alacritty brightnessctl
      ;;
    fonts)
      printf '%s\n' fonts-noto fonts-noto-color-emoji
      ;;
    media)
      printf '%s\n' playerctl easyeffects
      ;;
    wallpaper)
      printf '%s\n' hyprpaper
      ;;
    apps)
      printf '%s\n' dolphin chromium-browser
      ;;
    *)
      return 1
      ;;
  esac
}

aur_packages_for_group_ubuntu() {
  return 0
}

cargo_packages_for_group_ubuntu() {
  return 0
}
