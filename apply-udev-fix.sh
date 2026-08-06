#!/bin/bash
###############################################################################
# Dell iSM udev boot fix — Proxmox VE 9 (Debian 13), dcism 6.1.0.0-4104.ubuntu24
#
# Problem:
#   dcism ships /etc/udev/rules.d/95-iSM-usbnic.rules, which starts the iSM
#   daemon with blocking RUN+= directives from a udev worker when the iDRAC USB
#   NIC appears. On Debian 13 that worker stalls 60+ seconds, systemd-udev-settle
#   (pulled in by zfs-import-cache.service) times out after ~180s,
#   networking.service fails its dependency, and vmbr0 is never created — no
#   host network, no web GUI, no SSH.
#
# Fix:
#   Move the two commands out of the udev worker into a systemd oneshot, and
#   replace the rule with a non-blocking handoff to it.
#
# The rule this targets, verbatim from a 6.1.0.0-4104 install:
#
#   # Dell USBNIC Device
#   SUBSYSTEM=="usb", ATTR{idVendor}=="413c", ATTR{idProduct}=="a102", \
#     ATTR{manufacturer}=="Dell(TM)", ACTION=="add", \
#     RUN+="/bin/touch /opt/dell/srvadmin/iSM/etc/ini/usbnicconfig.ini"
#   SUBSYSTEM=="usb", ATTR{idVendor}=="413c", ATTR{idProduct}=="a102", \
#     ATTR{manufacturer}=="Dell(TM)", ACTION=="add", \
#     RUN+="/etc/init.d/dcismeng start &"
#
#   Two lines, same match keys, one command each. Three things follow from that,
#   each of which cost a boot to learn:
#
#   - One unit, not two. udev ran both lines sequentially in a single worker, so
#     the touch always preceded the daemon start. Two units would start in
#     parallel and lose that ordering.
#   - ENV{SYSTEMD_WANTS}+= , not '='. '=' assigns: with a rule line each, the
#     second line's assignment discarded the first line's unit and it never ran.
#   - No trailing '&'. udev runs RUN+= without a shell, so the '&' was passed to
#     the init script as a literal argument and ignored — it never backgrounded
#     anything. systemd would treat it the same way; it is dropped because it
#     reads as something it isn't.
#
# Usage: sudo ./apply-udev-fix.sh
###############################################################################

set -e

UDEV_RULE="/etc/udev/rules.d/95-iSM-usbnic.rules"
UNIT="/etc/systemd/system/dcism-usbnic-hotplug.service"
STALE_UNIT="/etc/systemd/system/dcism-usbnic-hotplug-2.service"

[ "$(id -u)" -eq 0 ] || { echo "ERROR: must run as root."; exit 1; }
[ -f /etc/debian_version ] || { echo "ERROR: not a Debian-based system."; exit 1; }

# Parse source is the diverted original once the fix has been applied before.
ORIGINAL="$UDEV_RULE"
[ -f "${UDEV_RULE}.distrib" ] && ORIGINAL="${UDEV_RULE}.distrib"

[ -f "$ORIGINAL" ] || {
    echo "ERROR: $UDEV_RULE not found — install the dcism package first."
    exit 1
}

# This script hardcodes one version's rule, so check the installed one still
# looks like it before overwriting anything.
if ! grep -q 'idProduct}=="a102"' "$ORIGINAL" || ! grep -q 'dcismeng start' "$ORIGINAL"; then
    echo "ERROR: $ORIGINAL is not the rule this script was written for."
    echo "       Expected iSM 6.1.0.0-4104 (413c:a102, /etc/init.d/dcismeng start)."
    echo "       Review it by hand:"
    sed 's/^/         | /' "$ORIGINAL"
    exit 1
fi

echo "Applying dcism udev boot fix..."

# 1. The oneshot handler. RemainAfterExit=yes matters: with 'no' the unit goes
#    inactive as soon as the last ExecStart returns, and systemd's default
#    KillMode=control-group kills the daemon dcismeng just forked into its cgroup.
cat > "$UNIT" << 'SERVICEEOF'
[Unit]
Description=Dell iSM USB NIC hotplug handler
Documentation=https://github.com/miguelbrandao/dell-ism-proxmox-9.1-patch
After=systemd-udevd.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=-/bin/touch /opt/dell/srvadmin/iSM/etc/ini/usbnicconfig.ini
ExecStart=-/etc/init.d/dcismeng start
SERVICEEOF

# An earlier version of this script split the two rule lines into two units.
rm -f "$STALE_UNIT"

systemctl daemon-reload

# 2. Divert Dell's rule so package upgrades cannot restore the blocking version.
#    After daemon-reload, so a failure above leaves the working rule in place.
if ! dpkg-divert --list "$UDEV_RULE" | grep -q "$UDEV_RULE"; then
    dpkg-divert --local --rename --add "$UDEV_RULE" > /dev/null
fi

# 3. Non-blocking replacement: both original lines collapse into this one.
cat > "$UDEV_RULE" << 'RULEEOF'
# Dell USBNIC Device — patched for Debian/Proxmox systemd compatibility.
# Dell's original used blocking RUN+= which hangs udev-settle on Debian and
# leaves the host with no network at boot. Its two rule lines are merged here;
# their commands now live in dcism-usbnic-hotplug.service.
# Original preserved by dpkg-divert at 95-iSM-usbnic.rules.distrib
SUBSYSTEM=="usb", ATTR{idVendor}=="413c", ATTR{idProduct}=="a102", ATTR{manufacturer}=="Dell(TM)", ACTION=="add", TAG+="systemd", ENV{SYSTEMD_WANTS}+="dcism-usbnic-hotplug.service"
RULEEOF

udevadm control --reload-rules

cat << EOF
Fix applied.
  - Installed: $UNIT
  - Diverted:  ${UDEV_RULE}.distrib (original preserved)
  - Replaced:  $UDEV_RULE (non-blocking systemd handoff)

Reboot, then verify:
  systemctl is-system-running    # running, not degraded
  ip -br a                       # vmbr0 UP with its address
  systemctl status dcismeng      # active (running)

Note: dcismeng.service is enabled and starts the daemon too, so both it and this
unit start one at boot, in separate cgroups, neither aware of the other. Two
dsm_ism_srvmgrd processes then contend for the OS-to-iDRAC pass-through channel
and the loser logs ISM0006. Check with:
  pgrep -a dsm_ism_srvmgrd       # expect one
EOF
