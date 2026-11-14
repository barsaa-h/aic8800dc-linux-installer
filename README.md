# AIC8800DC Linux WiFi Driver Installer

**One-command installer** for USB WiFi dongles using the AIC8800DC chipset (TP-Link, Mercury, etc.). Works on Ubuntu, Linux Mint, Debian, and any Debian-based Linux.

After running **one command**, the dongle works permanently — survives reboots, kernel updates, and re-plugs.

## Quick Install

```bash
git clone https://github.com/barsaa-h/aic8800dc-linux-installer.git
cd aic8800dc-linux-installer
sudo bash install.sh
```

Then unplug the dongle, plug it back in, wait 15 seconds — WiFi appears in the system tray.

## What It Does

| Step | What happens |
|---|---|
| 1 | Installs build tools (gcc, linux-headers, dkms) |
| 2 | Downloads the AIC8800DC Linux driver from [Kiborgik's patched fork](https://github.com/Kiborgik/aic8800dc-linux-patched) |
| 3 | Patches it for WiFi-only dongles (no Bluetooth variant) |
| 4 | Installs TP-Link/Mercury-specific firmware |
| 5 | Registers with **DKMS** — auto-rebuilds on every kernel update |
| 6 | Installs udev rule for automatic storage-to-WiFi mode switch |
| 7 | Configures auto-load on boot |

## Uninstall

```bash
cd aic8800dc-linux-installer
sudo bash uninstall.sh
```

## Supported Dongles

- TP-Link TL-WN722N v4/v5 (AIC8800DC)
- Mercury MW300UH v2 (AIC8800DC)
- Any USB dongle with `ID 2357:0147` or `ID a69c:5721`

## How It Works

This chipset is **not supported in the mainline Linux kernel**. Its driver must be built from source and installed once per computer. This project automates that into a single command.

The driver is built and signed via **DKMS**, which means when your kernel updates (e.g., from 6.8 to 6.11), the module rebuilds automatically. You never touch it again.

## License

The installer script is MIT. The driver source is from [AIC semiconductor](https://github.com/15554/aic8800dc-linux-patched) under their own license (GPL). Firmware files are redistributable per AIC's terms.

## Basic diagnostics

If the Wi-Fi adapter is not detected or installation fails, these read-only commands can help collect information before troubleshooting:

```bash
lsusb
uname -r
dkms status
```

- `lsusb` lists connected USB devices, including their vendor and product IDs.
- `uname -r` shows the currently running Linux kernel version.
- `dkms status` reports installed DKMS modules, if DKMS is installed.

These commands do not install or remove drivers. This section documents troubleshooting only; it does not change the installer or guarantee hardware compatibility.
