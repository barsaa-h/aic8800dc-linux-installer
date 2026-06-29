#!/usr/bin/env bash
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info() { echo -e "${GREEN}[INFO]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
err() { echo -e "${RED}[ERR]${NC} $*"; exit 1; }

VERSION="1.0.0"
DRIVER_REPO="https://github.com/Kiborgik/aic8800dc-linux-patched.git"
DRIVER_DIR="/tmp/aic8800dc-build"
DKMS_NAME="aic8800dc"
DKMS_VERSION="6.4.3.0-patched.3"

cd "$(dirname "$0")"
PROJECT_DIR="$PWD"

info "AIC8800DC WiFi Driver Installer v${VERSION}"
info "========================================"

# --- Check root ---
[[ $EUID -eq 0 ]] || err "Run with sudo: sudo bash install.sh"

# --- Install dependencies ---
info "Installing build dependencies..."
apt-get update -qq
apt-get install -y -qq build-essential linux-headers-$(uname -r) dkms git usb-modeswitch udev eject 2>/dev/null

# --- Clone or pull driver source ---
if [[ -d "$DRIVER_DIR" ]]; then
    info "Updating existing driver source..."
    git -C "$DRIVER_DIR" pull --ff-only 2>/dev/null || true
else
    info "Downloading driver source..."
    git clone --depth 1 "$DRIVER_REPO" "$DRIVER_DIR"
fi

# --- Apply interface fix ---
info "Patching driver for WiFi-only dongles..."
patch_file="$DRIVER_DIR/drivers/aic8800/aic8800_fdrv/aicwf_usb.c"
if grep -q 'bNumInterfaces != 3' "$patch_file" && ! grep -q 'bNumInterfaces != 1' "$patch_file"; then
    sed -i 's/bNumInterfaces != 3/bNumInterfaces != 3 \&\& usb->actconfig->desc.bNumInterfaces != 1/' "$patch_file"
fi

# --- Fix USB unplug crash (missing URB cancellation) ---
info "Fixing USB unplug crash..."
if grep -q '//aicwf_usb_cancel_all_urbs' "$patch_file"; then
    sed -i 's|//aicwf_usb_cancel_all_urbs(usb_dev);//AIDEN|aicwf_usb_cancel_all_urbs(usb_dev);|' "$patch_file"
fi

# --- Install firmware ---
info "Installing firmware..."
mkdir -p /lib/firmware/aic8800DC
cp -r "$PROJECT_DIR/firmware/aic8800DC/"* /lib/firmware/aic8800DC/

# --- Install udev rule ---
info "Installing udev rule..."
cp "$PROJECT_DIR/tools/aic.rules" /etc/udev/rules.d/aic.rules
udevadm control --reload-rules 2>/dev/null || true

# --- Configure usb_modeswitch ---
info "Configuring usb_modeswitch..."
mkdir -p /etc/usb_modeswitch.d
cat > /etc/usb_modeswitch.d/a69c:5721 << 'EOF'
# AIC8800DC (TP-Link/Mercury) - switch from storage to WiFi
TargetVendor=0x2357
TargetProduct=0x0147
MessageEndpoint=0x01
MessageContent="5553424312345678000000000000061b000000020000000000000000000000"
EOF

# --- Set up DKMS ---
info "Setting up DKMS source..."
DKMS_SRC="/usr/src/${DKMS_NAME}-${DKMS_VERSION}"
rm -rf "$DKMS_SRC"
cp -r "$DRIVER_DIR" "$DKMS_SRC"

# Write proper dkms.conf
cat > "$DKMS_SRC/dkms.conf" << DKMS
PACKAGE_NAME="${DKMS_NAME}"
PACKAGE_VERSION="${DKMS_VERSION}"
BUILT_MODULE_NAME[0]="aic_load_fw"
BUILT_MODULE_LOCATION[0]="drivers/aic8800/aic_load_fw/"
BUILT_MODULE_NAME[1]="aic8800_fdrv"
BUILT_MODULE_LOCATION[1]="drivers/aic8800/aic8800_fdrv/"
DEST_MODULE_LOCATION[0]="/updates/dkms"
DEST_MODULE_LOCATION[1]="/updates/dkms"
MAKE[0]="make -C \\\$kernel_source_path M=\\\$dkms_tree/\\\$PACKAGE_NAME/\\\$PACKAGE_VERSION/build/drivers/aic8800/aic_load_fw modules"
MAKE[1]="make -C \\\$kernel_source_path M=\\\$dkms_tree/\\\$PACKAGE_NAME/\\\$PACKAGE_VERSION/build/drivers/aic8800/aic8800_fdrv modules"
CLEAN="make -C \\\$kernel_source_path M=\\\$dkms_tree/\\\$PACKAGE_NAME/\\\$PACKAGE_VERSION/build/drivers/aic8800/aic8800_fdrv clean"
AUTOINSTALL="yes"
REMAKE_INITRD="yes"
DKMS

# --- Build & install via DKMS ---
info "Building driver (this takes 1-2 minutes)..."
dkms remove -m "$DKMS_NAME" -v "$DKMS_VERSION" --all 2>/dev/null || true
dkms add "$DKMS_SRC"
dkms build -m "$DKMS_NAME" -v "$DKMS_VERSION"

# --- Handle Secure Boot signing ---
if mokutil --sb-state 2>/dev/null | grep -qi "enabled"; then
    info "Secure Boot detected. Signing modules..."
    if [[ -f /var/lib/shim-signed/mok/MOK.priv ]] && [[ -f /var/lib/shim-signed/mok/MOK.der ]]; then
        for mod in aic_load_fw aic8800_fdrv; do
            kmodsign sha512 /var/lib/shim-signed/mok/MOK.priv \
                /var/lib/shim-signed/mok/MOK.der \
                /var/lib/dkms/${DKMS_NAME}/${DKMS_VERSION}/build/drivers/aic8800/*/${mod}.ko 2>/dev/null || true
        done
        info "Modules signed with existing MOK key."
    else
        warn "Secure Boot is enabled but no MOK key found."
        warn "After install, run: sudo mokutil --import /var/lib/shim-signed/mok/MOK.der"
        warn "Then reboot and enroll the key."
    fi
fi

dkms install -m "$DKMS_NAME" -v "$DKMS_VERSION"

# --- Configure auto-load ---
info "Configuring auto-load..."
echo -e "aic_load_fw\naic8800_fdrv" > /etc/modules-load.d/aic8800.conf

# Add to initramfs
mkdir -p /etc/initramfs-tools/modules.d
echo -e "aic_load_fw\naic8800_fdrv" > /etc/initramfs-tools/modules.d/aic8800
update-initramfs -u 2>/dev/null

# --- Load modules ---
modprobe aic_load_fw 2>/dev/null || true
modprobe aic8800_fdrv 2>/dev/null || true

echo ""
info "========================================"
info "Installation complete!"
info ""
info "Next steps:"
info "  1. Unplug the dongle"
info "  2. Plug it back in"
info "  3. Wait 15 seconds"
info "  4. Connect to WiFi from system tray"
info ""
info "The driver will survive kernel updates (DKMS)."
info "To remove: sudo bash uninstall.sh"
info "========================================"
