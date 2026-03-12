# Dell iDRAC iSM 5.4.2 — Proxmox 9.1 / Debian 13 Install Fix

## Overview

The official `dcism` 5.4.2 package from Dell is built and tested against **Ubuntu 24**.
When installed on **Proxmox VE 9.1 (Debian 13)**, it causes all network interfaces to
fail to come up at boot due to a blocking udev rule that was not updated for systemd-based
Debian environments.

This repo contains a patched version of Dell's `dcism-setup.sh` installer that
automatically detects Debian-based systems and applies the necessary fix after installation.

---

## The Problem

### Root cause chain

1. `dcism` ships `/etc/udev/rules.d/95-iSM-usbnic.rules` which uses blocking `RUN+=`
   directives to start the iSM daemon via `/etc/init.d/dcismeng` when the iDRAC USB NIC
   (`413c:a102`) is detected at boot.

2. On Debian 13 / Proxmox 9, this blocks the udev worker for 60+ seconds because
   `dcismeng start` is slow to complete in a udev worker context.

3. `systemd-udev-settle.service` (pulled in by `zfs-import-cache.service`) waits for
   the udev queue to drain and times out after 180 seconds.

4. `networking.service` is downstream of this chain — all interfaces remain down until
   the timeout expires or networking is manually restarted.

### Symptoms

- Network interfaces not up after boot on Proxmox
- `systemd-analyze blame` shows `systemd-udev-settle.service` taking 2-3 minutes
- Running `systemctl restart networking` brings interfaces up immediately
- `journalctl -b | grep udev` shows the iDRAC USB NIC worker taking 60+ seconds

### Why it works on Ubuntu 24

On Ubuntu 24 (the target platform for this package), `systemd-udev-settle` behaves
differently and the timing of `init.d` calls from udev is less likely to cause a hang.
Dell has not published a Debian-native package.

---

## The Fix

The patched `setup.sh` appends an `ApplyDebianUdevFix()` function that runs automatically
after the standard Dell installer completes on any Debian-based OS. It performs three steps:

### 1. Install a systemd oneshot handler service

Creates `/etc/systemd/system/dcism-usbnic-hotplug.service` which performs the same two
actions as the original udev rules — touching the USB NIC flag file and starting the daemon
— but runs outside the udev worker context via systemd, so it does not block udev queue
draining.

### 2. Replace the blocking udev rule

Overwrites `/etc/udev/rules.d/95-iSM-usbnic.rules` with a non-blocking equivalent that
uses `TAG+="systemd"` and `ENV{SYSTEMD_WANTS}` to hand off to the oneshot service
asynchronously.

### 3. Protect against future package upgrades with dpkg-divert

Uses `dpkg-divert` to prevent future `dcism` upgrades from silently restoring the broken
original rule. The original file is preserved as `95-iSM-usbnic.rules.distrib`.

---

## Download

Download the official iSM package from Dell:

**[Dell EMC iDRAC Service Module for Linux, v5.4.2.0 | Driver Details | Dell US](https://www.dell.com/support/home/en-us/drivers/driversdetails?driverid=tv5f8)**

## Installation

1. Download and extract the iSM package from Dell:
   ```bash
   tar -xvzf OM-iSM-Dell-Web-LX-*.tar.gz
   cd OM-iSM-Dell-Web-LX-*/
   ```

2. Replace the stock `setup.sh` with the patched version from this repo:
   ```bash
   cp /path/to/repo/setup.sh ./setup.sh
   chmod +x ./setup.sh
   ```

3. Run the installer as normal:
   ```bash
   sudo bash setup.sh
   ```

The Debian/Proxmox udev fix is applied automatically at the end of installation.
On non-Debian systems the fix step is skipped entirely and the installer behaves
identically to the stock Dell version.

---

## Tested On

| Component | Version |
|---|---|
| Proxmox VE | 9.1 |
| Debian | 13 (Trixie) |
| dcism | 5.4.2.0-4048.ubuntu24 |
| Hardware | Dell PowerEdge R440 |

---

## Files

| File | Description |
|---|---|
| `setup.sh` | Patched Dell iSM installer with Debian udev fix appended |
| `README.md` | This file |

---

## Notes

- The fix only modifies the udev rule and adds a systemd service. The iSM daemon itself
  (`dsm_ism_srvmgrd`), all iSM features, and the `dcismeng` init script are untouched.
- iSM OS-to-iDRAC passthrough and USB NIC hotplug reconnection continue to work correctly
  via the new systemd oneshot service.
- If your node has no ZFS pools but `zfsutils-linux` is installed, removing it will also
  eliminate the `zfs-import-cache.service` dependency on `systemd-udev-settle` entirely,
  which is a further cleanup but not required for the fix to work.

```bash
# Optional cleanup if ZFS is not in use on this node
apt remove --purge zfsutils-linux zfs-zed
```

---

## License

The patched portions of `setup.sh` unique to this fix are released under MIT.
The original Dell `dcism-setup.sh` content remains subject to Dell's license agreement.
