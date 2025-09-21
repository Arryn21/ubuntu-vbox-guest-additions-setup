# VirtualBox Guest Additions Auto-Setup (Ubuntu, one-shot)

**Goal:** Run a single script inside any Ubuntu guest (18.04 or newer) to make **bidirectional clipboard** (and other integration features) work—no manual steps.

## Features
- Installs build tools + DKMS + kernel headers (handles generic-header fallback)
- Installs Ubuntu's `virtualbox-guest-*` packages
- Falls back to the **official ISO installer** automatically (or use `--download <version>`)
- Starts clipboard client now and ensures **autostart** each login
- Forces **Xorg** (disables Wayland) by default for maximum reliability (use `--keep-wayland` to opt out)
- Reboots automatically when finished (use `--no-reboot` to skip)

## Usage (inside the Ubuntu VM)
```bash
# One and done:
bash setup-vbox-guest-additions.sh

# If you want to pin a GA version:
bash setup-vbox-guest-additions.sh --download 7.1.8

# Keep Wayland (not recommended if clipboard is critical):
bash setup-vbox-guest-additions.sh --keep-wayland

# Skip reboot:
bash setup-vbox-guest-additions.sh --no-reboot
```

## Notes
- You must still have the **host** set to **Shared Clipboard → Bidirectional** in VirtualBox Manager (guest cannot change host settings).
- In terminal: paste with `Ctrl+Shift+V`; GUI apps: `Ctrl+V`.
- The script creates `/etc/xdg/autostart/vboxclient-clipboard.desktop` to guarantee the clipboard client starts on login.
- If ISO install was needed, the script will download from `download.virtualbox.org` and mount it automatically.
