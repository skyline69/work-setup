#!/usr/bin/env bash

package_group_supported_fedora() {
  case "$1" in
    core|fonts|media|wallpaper|apps)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

packages_for_group_fedora() {
  case "$1" in
    core)
      printf '%s\n' hyprland hyprlock hypridle xdg-desktop-portal-hyprland rofi-wayland alacritty brightnessctl
      ;;
    fonts)
      printf '%s\n' google-noto-sans-fonts google-noto-emoji-fonts
      ;;
    media)
      printf '%s\n' playerctl easyeffects
      ;;
    wallpaper)
      printf '%s\n' hyprpaper
      ;;
    apps)
      printf '%s\n' dolphin chromium
      ;;
    *)
      return 1
      ;;
  esac
}

aur_packages_for_group_fedora() {
  return 0
}
