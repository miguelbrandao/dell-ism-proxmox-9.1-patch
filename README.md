# Dell iSM udev Boot Fix — Proxmox VE 9 / Debian 13

Fixes the boot hang caused by Dell's iDRAC Service Module (`dcism`) on Proxmox VE 9.
No Dell installer included — apply this **after** installing iSM.

Targets **dcism 6.1.0.0-4104.ubuntu24** specifically. The rule contents are hardcoded;
the script checks the installed rule still matches before touching anything and stops
if it doesn't. For other versions, read [The Fix](#the-fix) and adapt.

---

## The Problem

Dell's `dcism` package is built for Ubuntu. Its udev rule uses blocking `RUN+=`
directives to start the iSM daemon when the iDRAC USB NIC (`413c:a102`) appears:

1. `95-iSM-usbnic.rules` invokes `/etc/init.d/dcismeng start` inside a udev worker.
2. On Debian 13 / Proxmox 9 that worker stalls 60+ seconds.
3. `systemd-udev-settle.service` (pulled in by `zfs-import-cache.service`) waits for
   the udev queue to drain, then times out after ~180 s.
4. `networking.service` is downstream — dependency fails, `vmbr0` is never created,
   so there is **no host network, no web GUI, no SSH**.

### Symptoms

- `systemctl is-system-running` → `degraded`
- `ip -br a` → no `vmbr0`
- `journalctl -b -u networking.service` → "Dependency failed"
- `systemd-analyze blame` → `systemd-udev-settle.service` taking 2–3 minutes
- `systemctl restart networking` brings interfaces up immediately

---

## The Fix

What 6.1.0.0 ships:

```
# Dell USBNIC Device
SUBSYSTEM=="usb", ATTR{idVendor}=="413c", ATTR{idProduct}=="a102", ATTR{manufacturer}=="Dell(TM)", ACTION=="add", RUN+="/bin/touch /opt/dell/srvadmin/iSM/etc/ini/usbnicconfig.ini"
SUBSYSTEM=="usb", ATTR{idVendor}=="413c", ATTR{idProduct}=="a102", ATTR{manufacturer}=="Dell(TM)", ACTION=="add", RUN+="/etc/init.d/dcismeng start &"
```

Both commands move into one systemd oneshot, and the rule becomes a non-blocking
handoff to it:

1. **Install `/etc/systemd/system/dcism-usbnic-hotplug.service`** — runs the `touch`
   then `dcismeng start`, outside the udev worker, so nothing blocks the udev queue.
2. **Divert the original rule** — `dpkg-divert --local --rename` preserves Dell's file
   as `95-iSM-usbnic.rules.distrib` and stops `dcism` upgrades from restoring it.
3. **Write the replacement rule** — same match keys, plus `TAG+="systemd"` and
   `ENV{SYSTEMD_WANTS}+=`, handing off asynchronously.

### Four details that each cost a boot to learn

- **One unit, not two.** Dell splits the work across two rule lines with identical
  match keys. udev ran them sequentially in a single worker, so the `touch` always
  preceded the daemon start. A unit per line would start in parallel and lose that.
- **`ENV{SYSTEMD_WANTS}+=`, not `=`.** `=` assigns. With one rule line per unit, the
  second line's assignment discarded the first line's unit and it never ran.
- **`RemainAfterExit=yes`.** With `no`, the unit goes inactive once the last
  `ExecStart` returns, and systemd's default `KillMode=control-group` kills the daemon
  `dcismeng` just forked into its cgroup.
- **No trailing `&`.** udev runs `RUN+=` without a shell, so Dell's `&` reached the
  init script as a literal argument and was ignored — it never backgrounded anything.
  systemd treats it the same way. Dropped because it reads as something it isn't.

Ordering inside the script matters too: the unit is written and `daemon-reload` runs
*before* the diversion, so a failure leaves Dell's working rule in place rather than no
rule at all.

The iSM daemon (`dsm_ism_srvmgrd`), all iSM features, the `dcismeng` init script, and
OS-to-iDRAC pass-through are untouched and keep working.

---

## Usage

```bash
git clone https://github.com/miguelbrandao/dell-ism-proxmox-9.1-patch.git
cd dell-ism-proxmox-9.1-patch
chmod +x apply-udev-fix.sh

sudo ./apply-udev-fix.sh --dry-run    # print the current rule and every change
sudo ./apply-udev-fix.sh --apply
reboot
```

| Mode | Effect |
|---|---|
| *(no arguments)* | print usage and exit — never changes anything |
| `--dry-run` | print the installed rule and both files that would be written |
| `--apply` | install the unit, divert Dell's rule, write the replacement |
| `--revert` | restore Dell's original rule and remove the unit |

`--apply` is explicit on purpose: this rewrites a udev rule the host network depends on
at boot, so a bare invocation shows usage instead.

Requires root and Debian. Refuses to run if `95-iSM-usbnic.rules` is missing, or if it
doesn't look like the 6.1.0.0 rule — it prints the file so you can check it yourself.
Safe to re-run: the diversion is idempotent, and once applied both `--dry-run` and the
version check read the preserved `.distrib` original.

### Verify after reboot

```bash
systemctl is-system-running          # 'running', not 'degraded'
ip -br a                             # vmbr0 UP with its address
systemctl status dcismeng            # active (running)
systemd-analyze blame | grep udev    # settle no longer takes minutes
```

`dcism-usbnic-hotplug.service` should read `active (exited)` — a oneshot that finished.
`inactive (dead)` with a dead daemon would be the cgroup-kill failure mode.

### Undo

```bash
sudo ./apply-udev-fix.sh --revert
```

Removes the replacement rule, undoes the diversion so Dell's original comes back from
`.distrib`, deletes the unit, and reloads systemd and udev. Restores Dell's original
rule — and the boot hang. Safe to run twice; it says so and stops if there is nothing
diverted.

### Locked out already?

Get a console via the iDRAC Virtual Console (independent of host network), then
`ifreload -a` to bring `vmbr0` back up, apply the fix, and reboot. Manual bring-up only
lasts for the current boot.

---

## Tested On

| Component | Version |
|---|---|
| Proxmox VE | 9.x |
| Debian | 13 (Trixie) |
| dcism | 6.1.0.0-4104.ubuntu24 |
| Hardware | Dell PowerEdge with iDRAC |

---

## Notes

- **Duplicate daemon.** `dcismeng.service` ships enabled and starts the daemon, while
  Dell's udev rule starts it again through `/etc/init.d/dcismeng`. The init script's
  `dsm_ism_srvmgrd` lands in the hotplug unit's cgroup where `dcismeng.service` can't
  see it, so both start one and the two contend for the OS-to-iDRAC pass-through
  channel — the loser logs `ISM0006`. Check with `pgrep -a dsm_ism_srvmgrd`; expect
  one. This predates the fix and is Dell's, not the script's. Pick an owner if it
  bothers you.
- Where to get iSM: Dell's support site /
  `https://linux.dell.com/repo/community/openmanage/iSM/`. On Debian 13 use the
  **ubuntu24** build and `dpkg -i` it directly — Dell's `setup.sh` does not recognise
  Debian 13.
- If your node has **no ZFS pools**, removing `zfsutils-linux` also breaks the
  `systemd-udev-settle` dependency chain and works around the hang. Do **not** do this
  if any storage is on ZFS.

  ```bash
  # Optional, only when ZFS is definitely unused on this node
  apt remove --purge zfsutils-linux zfs-zed
  ```

---

## License

MIT.
