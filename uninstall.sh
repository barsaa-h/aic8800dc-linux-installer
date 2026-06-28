#!/usr/bin/env bash
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'
info() { echo -e "${GREEN}[INFO]${NC} $*"; }
err() { echo -e "${RED}[ERR]${NC} $*"; exit 1; }

DKMS_NAME="aic8800dc"
DKMS_VERSION="6.4.3.0-patched.3"

[[ $EUID -eq 0 ]] || err "Run with sudo: sudo bash uninstall.sh"

info "Removing DKMS module..."
dkms remove -m "$DKMS_NAME" -v "$DKMS_VERSION" --all 2>/dev/null || true
rm -rf "/usr/src/${DKMS_NAME}-${DKMS_VERSION}"

info "Removing firmware..."
rm -rf /lib/firmware/aic8800DC

info "Removing config files..."
rm -f /etc/modules-load.d/aic8800.conf
rm -f /etc/initramfs-tools/modules.d/aic8800
rm -f /etc/udev/rules.d/aic.rules
rm -f /etc/usb_modeswitch.d/a69c:5721

info "Unloading modules..."
modprobe -r aic8800_fdrv 2>/dev/null || true
modprobe -r aic_load_fw 2>/dev/null || true

udevadm control --reload-rules 2>/dev/null || true
update-initramfs -u 2>/dev/null || true

info "Done. Dongle will no longer work as WiFi on this system."
info "Reboot recommended to fully clean up."
