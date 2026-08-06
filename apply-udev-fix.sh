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
#   Two lines, same match keys, one command each — so both commands go into one
#   unit, in order. The trailing '&' is dropped: udev runs RUN+= without a shell,
#   so it was a literal argument the init script ignored, never backgrounding.
#
# Usage:
#   sudo ./apply-udev-fix.sh --dry-run    print what would change, touch nothing
#   sudo ./apply-udev-fix.sh --apply      apply the fix
#   sudo ./apply-udev-fix.sh --revert     restore Dell's rule (boot hang returns)
###############################################################################

set -e

UDEV_RULE="/etc/udev/rules.d/95-iSM-usbnic.rules"
UNIT="/etc/systemd/system/dcism-usbnic-hotplug.service"
STALE_UNIT="/etc/systemd/system/dcism-usbnic-hotplug-2.service"

Usage()
{
    cat << USAGEEOF
Dell iSM udev boot fix — Proxmox VE 9 (Debian 13), dcism 6.1.0.0-4104.ubuntu24

Moves the iSM daemon start out of the udev worker into a systemd oneshot, so
udev-settle stops timing out and networking.service comes up at boot.

Usage: $0 <mode>

  --dry-run   print the current rule and everything that would change, write nothing
  --apply     apply the fix (reboot afterwards)
  --revert    restore Dell's original rule — the boot hang comes back

Run as root. --apply is deliberately explicit: this rewrites a udev rule that
the host network depends on at boot.
USAGEEOF
}

case "${1:-}" in
    --dry-run)  MODE="dry-run" ;;
    --apply)    MODE="apply" ;;
    --revert)   MODE="revert" ;;
    "")         Usage; exit 0 ;;
    *)          echo "Unknown option: $1"; echo ""; Usage; exit 2 ;;
esac

[ "$(id -u)" -eq 0 ] || { echo "ERROR: must run as root."; exit 1; }
[ -f /etc/debian_version ] || { echo "ERROR: not a Debian-based system."; exit 1; }

IsDiverted()
{
    dpkg-divert --list "$UDEV_RULE" | grep -q "$UDEV_RULE"
}

# ---------------------------------------------------------------------------
# Revert: undo in reverse. The replacement rule goes first — dpkg-divert refuses
# to move the original back over a file already sitting at that path.
# ---------------------------------------------------------------------------
if [ "$MODE" = "revert" ]; then
    if ! IsDiverted; then
        echo "Nothing to revert: $UDEV_RULE is not diverted."
        echo "The fix was never applied here, or was already reverted."
        # A leftover unit with the diversion gone means a half-reverted state;
        # clean it rather than leaving something that still starts the daemon.
        if [ -f "$UNIT" ] || [ -f "$STALE_UNIT" ]; then
            rm -f "$UNIT" "$STALE_UNIT"
            systemctl daemon-reload
            echo "Removed a leftover hotplug unit."
        fi
        exit 0
    fi

    rm -f "$UDEV_RULE"
    dpkg-divert --local --rename --remove "$UDEV_RULE" > /dev/null
    rm -f "$UNIT" "$STALE_UNIT"
    systemctl daemon-reload
    udevadm control --reload-rules

    echo "Reverted."
    echo "  - Restored: $UDEV_RULE (Dell's original, blocking RUN+=)"
    echo "  - Removed:  $UNIT"
    echo ""
    echo "The boot hang comes back on the next reboot."
    exit 0
fi

# Once applied, the diverted copy is the original; check that instead.
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

# The two files this installs. Functions so --dry-run can print exactly what
# --apply would write.

# dcismeng forks dsm_ism_srvmgrd into this unit's cgroup. With RemainAfterExit=no
# the unit goes inactive as soon as the last ExecStart returns, and systemd's
# default KillMode=control-group should then take the daemon with it. The cgroup
# placement is confirmed; the kill is documented behaviour rather than something
# tested here — 'yes' is the cautious setting.
UnitContents()
{
    cat << 'SERVICEEOF'
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
}

RuleContents()
{
    cat << 'RULEEOF'
# Dell USBNIC Device — patched for Debian/Proxmox systemd compatibility.
# Dell's original used blocking RUN+= which hangs udev-settle on Debian and
# leaves the host with no network at boot. Its two rule lines are merged here;
# their commands now live in dcism-usbnic-hotplug.service.
# Original preserved by dpkg-divert at 95-iSM-usbnic.rules.distrib
SUBSYSTEM=="usb", ATTR{idVendor}=="413c", ATTR{idProduct}=="a102", ATTR{manufacturer}=="Dell(TM)", ACTION=="add", TAG+="systemd", ENV{SYSTEMD_WANTS}+="dcism-usbnic-hotplug.service"
RULEEOF
}

if [ "$MODE" = "dry-run" ]; then
    echo "Dry run — nothing will be changed."
    echo ""
    echo "Rule this would replace ($ORIGINAL):"
    grep -v '^[[:space:]]*#' "$ORIGINAL" | grep -v '^[[:space:]]*$' | sed 's/^/  | /' || true
    echo ""
    echo "--- would write $UNIT ---"
    UnitContents
    echo "--- would write $UDEV_RULE ---"
    RuleContents
    echo ""
    echo "Would also:"
    if IsDiverted; then
        echo "  - leave the existing diversion of $UDEV_RULE in place"
    else
        echo "  - dpkg-divert --local --rename --add $UDEV_RULE"
    fi
    [ -f "$STALE_UNIT" ] && echo "  - remove $STALE_UNIT (left by an older version of this script)"
    echo "  - systemctl daemon-reload; udevadm control --reload-rules"
    exit 0
fi

echo "Applying dcism udev boot fix..."

# 1. The oneshot handler.
UnitContents > "$UNIT"

# An earlier version of this script split the two rule lines into two units.
rm -f "$STALE_UNIT"

systemctl daemon-reload

# 2. Divert Dell's rule so package upgrades cannot restore the blocking version.
#    After daemon-reload, so a failure above leaves the working rule in place.
IsDiverted || dpkg-divert --local --rename --add "$UDEV_RULE" > /dev/null

# 3. Non-blocking replacement: both original lines collapse into this one.
RuleContents > "$UDEV_RULE"

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
EOF
