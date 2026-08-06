# Dell iSM udev Boot Fix — Proxmox VE 9 / Debian 13

A single standalone script that fixes the boot hang caused by Dell's iDRAC Service
Module (`dcism`) on Debian-based systems. No Dell installer included — apply this
**after** installing iSM by whatever means you prefer.

**Version-agnostic.** Nothing about the device IDs or file paths is hardcoded. The
script reads the rule your installed `dcism` package actually shipped, reuses its
device match keys verbatim, and converts its `RUN+=` commands into `ExecStart=`
lines. So it adapts to whatever 5.4.x, 6.1.x or later ships, instead of assuming
one version's `413c:a102` and `usbnicconfig.ini` paths.

It prints everything it derived from your install before writing anything.

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

Move the daemon start out of the udev worker and into systemd. Four steps:

0. **Read Dell's own rule** — parse `95-iSM-usbnic.rules` (joining line continuations,
   skipping comments), splitting each rule line into its device match keys and its
   `RUN+=` commands. Everything below is generated from that, not from constants.
   Both `RUN+="…"` and the C-escaped `RUN+=e"…"` form are understood, as is
   `RUN{program}+=`.
1. **Install a systemd oneshot handler per matched device** —
   `/etc/systemd/system/dcism-usbnic-hotplug.service` runs Dell's own commands, in order,
   outside the udev worker, so nothing blocks the udev queue. Rule lines sharing the same
   match keys are **merged into one unit**: iSM 6.1.0.0 splits a single device's work
   across two lines (`touch` on one, `dcismeng start` on the next), and udev ran those
   sequentially in one worker. Separate units would start in parallel and lose that
   ordering. A genuinely different device match gets its own unit (`-2`, `-3`…).
   Each command becomes `ExecStart=-…`; the `-`
   mirrors udev, where every `RUN+=` fires regardless of the previous one's exit status.
   The unit is `RemainAfterExit=yes` — with `no` it would go inactive the moment the
   last command returned, and systemd's default `KillMode=control-group` would take the
   daemon it just forked down with it.
2. **Divert the original rule** — `dpkg-divert --local --rename` preserves Dell's file
   as `95-iSM-usbnic.rules.distrib` and stops future `dcism` upgrades from restoring it.
   The diverted copy stays the parse source on later runs.
3. **Write the replacement rule** — converted lines keep their match keys and get
   `TAG+="systemd"` + `ENV{SYSTEMD_WANTS}`, handing off asynchronously. Every other line
   of Dell's file, including non-`add` lines such as `ACTION=="remove"` cleanup, is
   copied through verbatim — those never run at boot, so they are not the problem.

Everything that can fail happens *before* the diversion, so a failed `daemon-reload` or
an unloadable generated unit leaves the host with Dell's working rule still in place
rather than no rule at all.

A trailing `&` is dropped, and the drop is reported. iSM 6.1.0.0 ships
`RUN+="/etc/init.d/dcismeng start &"`, but udev runs `RUN+=` without a shell, so that
`&` never backgrounded anything — it reached the init script as a literal argument,
which ignored it. systemd behaves identically, so keeping it would change nothing
today; it is dropped because it reads as backgrounding and would break the first time
a command checked its arguments.

The script refuses rather than half-applying. A `RUN` command containing `%` or `$` is
not translatable — systemd re-expands both in `ExecStart`, and udev expands its own
`%k` / `$env{}` before running — so it stops and tells you to convert that rule by hand
instead of installing something subtly broken.

The iSM daemon (`dsm_ism_srvmgrd`), all iSM features, the `dcismeng` init script, and
OS-to-iDRAC pass-through are untouched and keep working.

---

## Usage

```bash
git clone https://github.com/miguelbrandao/dell-ism-proxmox-9.1-patch.git
cd dell-ism-proxmox-9.1-patch
chmod +x apply-udev-fix.sh

sudo ./apply-udev-fix.sh
reboot
```

Refuses to run unless: root, `/etc/debian_version` exists, and Dell's
`95-iSM-usbnic.rules` is present with a parseable `RUN+=` rule. Safe to re-run —
idempotent. It prints the derived match keys, the commands, and both generated files
before writing anything, so you can confirm they match your iSM version before
rebooting.

To undo by hand: `rm` the rule, `dpkg-divert --local --rename --remove` it to restore
Dell's original, delete `dcism-usbnic-hotplug.service`, then `systemctl daemon-reload`
and `udevadm control --reload-rules`. The boot hang comes back.

### Verify after reboot

```bash
systemctl is-system-running          # 'running', not 'degraded'
ip -br a                             # vmbr0 UP with its address
systemctl status dcismeng            # active (running)
systemd-analyze blame | grep udev    # settle no longer takes minutes
```

### Locked out already?

Get a console via the iDRAC Virtual Console (independent of host network), then
`ifreload -a` to bring `vmbr0` back up, apply the fix, and reboot. Manual bring-up
only lasts for the current boot.

---

## Tested On

| Component | Version | Status |
|---|---|---|
| Proxmox VE | 9.1 / 9.x | fix verified on hardware (upstream) |
| Debian | 13 (Trixie) | fix verified on hardware (upstream) |
| dcism | 5.4.2.0-4048.ubuntu24 | rule form covered by tests; fix verified on hardware |
| dcism | 6.1.0.0-4104.ubuntu24 | real rule file captured as a test fixture and parsed correctly; boot not yet verified on hardware |
| Hardware | Dell PowerEdge R440 | verified |

Because the rule is parsed at runtime rather than assumed, other iSM versions should
work — but "should" is not "verified". The plan the script prints before writing is
there so you can check it against your own version first.

### Tests

```bash
./tests/run-tests.sh     # no root, no dcism, no systemd required
```

43 assertions over fixtures in [tests/fixtures/](tests/fixtures/): the 5.4.2 rule form,
the real 6.1.0.0 rule (two lines, same match keys — asserts they merge into one unit
with the `touch` still ordered before `dcismeng start`), a variant with different USB IDs
and paths plus a line continuation and a `/bin/sh -c` command, an `ACTION=="remove"` line
placed before the `add` line, two genuinely different `add` lines, the `e"…"` and
`RUN{program}+=` forms, and every refusal path (`%`, `$`, relative path, already patched,
no `RUN+=`, missing file). The apply path is covered too, in a sandbox
with stubbed `dpkg-divert` / `systemctl` / `udevadm`: unit written, rule rewritten,
original diverted, stale units cleaned, and a forced `daemon-reload` failure leaving the
original rule undiverted.

---

## Notes

- Where to get iSM: Dell's support site / `https://linux.dell.com/repo/community/openmanage/iSM/`.
  On Debian 13 use the **ubuntu24** build and `dpkg -i` it directly — Dell's `setup.sh`
  does not recognise Debian 13.
- If your node has **no ZFS pools**, removing `zfsutils-linux` also breaks the
  `systemd-udev-settle` dependency chain and works around the hang. Do **not** do this
  if any storage is on ZFS.

  ```bash
  # Optional, only when ZFS is definitely unused on this node
  apt remove --purge zfsutils-linux zfs-zed
  ```

---

## Files

| File | Description |
|---|---|
| `apply-udev-fix.sh` | The fix. Parses Dell's rule, generates the units, applies. |
| `tests/run-tests.sh` | Parser and apply-path tests. |
| `tests/fixtures/` | Rule files the tests parse. |

---

## License

MIT.
