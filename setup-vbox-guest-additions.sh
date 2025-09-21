#!/usr/bin/env bash
# setup-vbox-guest-additions.sh
# One-shot automation to make VirtualBox Guest Additions (including bidirectional clipboard) work
# on Ubuntu guests (18.04+ through current). Run this INSIDE the Ubuntu VM.
#
# What it does automatically:
#   - Detect VirtualBox guest environment
#   - Install build tools, DKMS, and correct kernel headers
#   - Install Ubuntu's virtualbox-guest-* packages
#   - (If needed) download & run the official Guest Additions ISO installer (auto version unless provided)
#   - Ensure services are running (vboxservice, VBoxClient --clipboard)
#   - Create a fallback autostart for the clipboard client
#   - Force Xorg (disable Wayland) for maximum compatibility (can be disabled with --keep-wayland)
#   - Reboot (can be disabled with --no-reboot)
#
# Usage:
#   bash setup-vbox-guest-additions.sh
#   bash setup-vbox-guest-additions.sh --download 7.1.8     # pin a GA version to download
#   bash setup-vbox-guest-additions.sh --keep-wayland       # do NOT force Xorg
#   bash setup-vbox-guest-additions.sh --no-reboot          # skip reboot
#
# Notes:
#   - Host VM setting "Shared Clipboard: Bidirectional" must be enabled in VirtualBox Manager.
#     (We cannot change host settings from the guest.)
#
set -euo pipefail

RED=$'\e[31m'; GREEN=$'\e[32m'; YELLOW=$'\e[33m'; BLUE=$'\e[34m'; BOLD=$'\e[1m'; RESET=$'\e[0m'
say() { echo "${BLUE}${BOLD}[*]${RESET} $*"; }
ok()  { echo "${GREEN}${BOLD}[OK]${RESET} $*"; }
warn(){ echo "${YELLOW}${BOLD}[!]${RESET} $*"; }
die() { echo "${RED}${BOLD}[X]${RESET} $*" >&2; exit 1; }

AUTO_REBOOT=1
DOWNLOAD_VER=""
FORCE_XORG=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-reboot) AUTO_REBOOT=0; shift;;
    --download) DOWNLOAD_VER="${2:-}"; [[ -z "$DOWNLOAD_VER" ]] && die "--download requires a version (e.g. 7.1.8)"; shift 2;;
    --keep-wayland) FORCE_XORG=0; shift;;
    -h|--help) echo "Usage: $0 [--download <ver>] [--keep-wayland] [--no-reboot]"; exit 0;;
    *) die "Unknown argument: $1";;
  esac
done

# 0) Verify we're in a VirtualBox guest
if [[ -r /sys/class/dmi/id/product_name ]]; then
  PROD=$(</sys/class/dmi/id/product_name || true)
  if ! echo "$PROD" | grep -qi "VirtualBox"; then
    warn "This doesn't look like a VirtualBox guest (product: $PROD). Continuing anyway."
  fi
fi

# 1) Update apt + install prerequisites
say "Updating apt and installing build prerequisites..."
export DEBIAN_FRONTEND=noninteractive
sudo apt-get update -y
# Many Ubuntu versions name headers as linux-headers-$(uname -r). If this fails, try generic headers.
if ! sudo apt-get install -y build-essential dkms linux-headers-$(uname -r) curl ca-certificates; then
  warn "Could not install headers for running kernel; attempting generic headers..."
  sudo apt-get install -y build-essential dkms linux-headers-generic curl ca-certificates || true
fi

# 2) Install Ubuntu's packaged Guest Additions (preferred path)
say "Installing Ubuntu's VirtualBox guest packages..."
sudo apt-get install -y virtualbox-guest-utils virtualbox-guest-dkms virtualbox-guest-x11 || warn "Package install had issues; will attempt ISO method."

# 3) Try to load modules and start services
say "Ensuring services and modules are active..."
if command -v systemctl >/dev/null 2>&1; then
  sudo systemctl enable vboxservice.service >/dev/null 2>&1 || true
  sudo systemctl restart vboxservice.service || true
fi
sudo modprobe vboxguest 2>/dev/null || true
sudo modprobe vboxsf 2>/dev/null || true
sudo modprobe vboxvideo 2>/dev/null || true

# 4) If vboxguest still not present, fall back to ISO install
need_iso=0
if ! lsmod | grep -q '^vboxguest'; then
  need_iso=1
fi

# Helper to run ISO installer from a mount
run_iso_installer() {
  local MNT="$1"
  local RUN="$MNT/VBoxLinuxAdditions.run"
  if [[ -x "$RUN" ]]; then
    say "Running Guest Additions installer from: $RUN"
    sudo sh "$RUN" || die "ISO installer failed."
    ok "ISO installer completed."
    return 0
  fi
  return 1
}

# Attempt ISO install if requested or needed
if [[ -n "$DOWNLOAD_VER" || "$need_iso" -eq 1 ]]; then
  if [[ -z "$DOWNLOAD_VER" ]]; then
    # If VBoxControl exists, try to match that version; else fallback to a known stable env var.
    if command -v VBoxControl >/dev/null 2>&1; then
      DOWNLOAD_VER="$(VBoxControl --version 2>/dev/null | cut -d'_' -f1 | tr -d '\r\n' || true)"
    fi
    DOWNLOAD_VER="${DOWNLOAD_VER:-7.1.8}"
    warn "Falling back to ISO method. Version: $DOWNLOAD_VER"
  else
    say "Using requested GA version: $DOWNLOAD_VER"
  fi
  ISO_URL="https://download.virtualbox.org/virtualbox/${DOWNLOAD_VER}/VBoxGuestAdditions_${DOWNLOAD_VER}.iso"
  ISO_PATH="/tmp/VBoxGuestAdditions_${DOWNLOAD_VER}.iso"
  say "Downloading GA ISO from: $ISO_URL"
  curl -L -o "$ISO_PATH" "$ISO_URL" || die "Failed to download $ISO_URL"
  ISO_MOUNT="/mnt/vbox_ga"
  sudo mkdir -p "$ISO_MOUNT"
  sudo mount -o loop,ro "$ISO_PATH" "$ISO_MOUNT" || die "Failed to mount ISO"
  run_iso_installer "$ISO_MOUNT" || die "Installer not found inside ISO"
  sudo umount "$ISO_MOUNT" || true
fi

# 5) Start clipboard client NOW and add a robust autostart fallback
say "Starting clipboard integration client..."
if command -v VBoxClient >/dev/null 2>&1; then
  # Kill any stale client and start anew
  pkill -x VBoxClient 2>/dev/null || true
  (VBoxClient --clipboard >/dev/null 2>&1 &) || true
else
  warn "VBoxClient not found in PATH yet (will be available after reboot if ISO install just occurred)."
fi

# Autostart (in case the distro packages didn't create one)
AUTOSTART_DIR="/etc/xdg/autostart"
sudo mkdir -p "$AUTOSTART_DIR"
sudo bash -c "cat > ${AUTOSTART_DIR}/vboxclient-clipboard.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=VirtualBox Clipboard
Exec=sh -c 'pgrep -x VBoxClient >/dev/null || (VBoxClient --clipboard &)'
OnlyShowIn=GNOME;Unity;X-Cinnamon;MATE;XFCE;LXQt;LXDE;
X-GNOME-Autostart-Phase=Initialization
X-GNOME-Autostart-enabled=true
NoDisplay=true
EOF

ok "Autostart entry ensured at ${AUTOSTART_DIR}/vboxclient-clipboard.desktop"

# 6) Force Xorg for maximum compatibility (unless user opts out)
if [[ "$FORCE_XORG" -eq 1 ]]; then
  if [[ -f /etc/gdm3/custom.conf ]]; then
    say "Forcing Xorg (disabling Wayland) in /etc/gdm3/custom.conf"
    sudo sed -i 's/^#\?WaylandEnable=.*/WaylandEnable=false/g' /etc/gdm3/custom.conf || true
    if ! grep -q '^WaylandEnable=false' /etc/gdm3/custom.conf; then
      echo "WaylandEnable=false" | sudo tee -a /etc/gdm3/custom.conf >/dev/null
    fi
  fi
else
  warn "Keeping Wayland as requested (--keep-wayland). Clipboard might be less reliable under Wayland."
fi

# 7) Final verification hints
echo
if lsmod | grep -q '^vboxguest'; then
  ok "vboxguest kernel module is loaded."
else
  warn "vboxguest module is not loaded yet; reboot will usually fix this."
fi
if pgrep -x VBoxClient >/dev/null 2>&1; then
  ok "VBoxClient is running for clipboard."
else
  warn "VBoxClient is not running yet; it will start on next login due to autostart."
fi

echo
ok "All done. A reboot/login cycle ensures everything is cleanly started."
echo "   - Make sure host VM setting 'Shared Clipboard: Bidirectional' is enabled."
echo "   - Terminal paste: Ctrl+Shift+V; GUI apps: Ctrl+V."
echo

if [[ "$AUTO_REBOOT" -eq 1 ]]; then
  say "Rebooting in 5 seconds... (use --no-reboot to skip)"
  sleep 5 || true
  sudo reboot
else
  warn "Skipping reboot. Please reboot this VM manually to finalize."
fi
