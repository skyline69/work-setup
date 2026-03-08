#!/usr/bin/env bash

package_group_supported_arch() {
  case "$1" in
    core|fonts|media|wallpaper|apps|quickshell)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

packages_for_group_arch() {
  case "$1" in
    core)
      printf '%s\n' hyprland hyprlock hypridle xdg-desktop-portal-hyprland rofi-wayland alacritty brightnessctl
      ;;
    fonts)
      printf '%s\n' noto-fonts noto-fonts-emoji ttf-nerd-fonts-symbols-mono
      ;;
    media)
      printf '%s\n' playerctl easyeffects
      ;;
    wallpaper)
      printf '%s\n' awww hyprpaper
      ;;
    apps)
      printf '%s\n' dolphin chromium
      ;;
    quickshell)
      printf '%s\n' quickshell-git
      ;;
    *)
      return 1
      ;;
  esac
}

