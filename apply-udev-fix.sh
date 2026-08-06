#!/bin/bash
###############################################################################
# Dell iSM (dcism) udev boot fix for Debian / Proxmox VE
#
# Problem:
#   The dcism package (built for Ubuntu) ships /etc/udev/rules.d/95-iSM-usbnic.rules
#   which uses blocking RUN+= directives to start the iSM daemon from a udev worker
#   when the iDRAC USB NIC is detected. On Debian 13 / Proxmox 9 this blocks the udev
#   worker for 60+ seconds, causing systemd-udev-settle to time out, which delays
#   networking.service and leaves all interfaces down at boot (no vmbr0, no GUI/SSH).
#
# Fix:
#   1. Read the rule the INSTALLED dcism package shipped and extract, per rule line,
#      its device match keys and its RUN+= commands. Nothing about the device IDs or
#      file paths is hardcoded, so this works across iSM versions (5.4.x, 6.1.x, ...).
#   2. Install one systemd oneshot service per converted rule line, running the same
#      commands outside the udev worker context.
#   3. dpkg-divert the rules file so dcism upgrades cannot restore the broken rule,
#      then write a replacement that hands off via SYSTEMD_WANTS. Rule lines that are
#      not ACTION=="add" are copied through untouched — they never run at boot.
#
# The script refuses to convert anything it cannot translate faithfully, rather than
# reporting success over a half-applied fix.
#
# No network access, no package installs. Touches only the paths below.
#
# Usage:
#   sudo ./apply-udev-fix.sh
###############################################################################

set -u

# Overridable for testing; defaults are the real system paths.
UDEV_RULE_FILE="${UDEV_RULE_FILE:-/etc/udev/rules.d/95-iSM-usbnic.rules}"
DIVERTED_RULE_FILE="${UDEV_RULE_FILE}.distrib"
SERVICE_DIR="${SERVICE_DIR:-/etc/systemd/system}"
SERVICE_BASE="dcism-usbnic-hotplug"
DOC_URL="https://github.com/miguelbrandao/dell-ism-proxmox-9.1-patch"

SOURCE_RULE=""
UNIT_NAMES=()
UNIT_BODIES=()
RULE_OUT=()
PLAN_NOTES=()

# ---------------------------------------------------------------------------
# Preflight
# ---------------------------------------------------------------------------
PreflightChecks()
{
    if [ "$(id -u)" -ne 0 ]; then
        echo "ERROR: must run as root."
        return 1
    fi

    if [ ! -f /etc/debian_version ]; then
        echo "ERROR: not a Debian-based system; this fix is not needed here."
        return 1
    fi

    for TOOL in dpkg-divert systemctl udevadm; do
        if ! command -v "$TOOL" > /dev/null 2>&1; then
            echo "ERROR: required tool not found: $TOOL"
            return 1
        fi
    done

    return 0
}

ReportEnvironment()
{
    echo "Detected environment:"
    echo "  OS:      $(. /etc/os-release 2>/dev/null; echo "${PRETTY_NAME:-Debian $(cat /etc/debian_version 2>/dev/null)}")"
    if command -v dpkg-query > /dev/null 2>&1; then
        DCISM_VER=$(dpkg-query -W -f='${Version}' dcism 2>/dev/null)
        echo "  dcism:   ${DCISM_VER:-not installed via dpkg}"
    fi
    echo "  rule:    $SOURCE_RULE"
    echo ""
}

# ---------------------------------------------------------------------------
# Extract the commands from every RUN+= assignment on one rule line, one per
# output line.
#
# Follows udev's own quoting rules: a plain "..." value ends at the next double
# quote with no escape processing, while an e"..." value is C-escaped, so \" and
# \\ are unescaped here. Both RUN+= and RUN{program}+= are recognised.
# ---------------------------------------------------------------------------
ExtractRunCommands()
{
    printf '%s\n' "$1" | awk '
    {
        line = $0
        while (match(line, /RUN(\{[^}]*\})?[ \t]*\+=[ \t]*e?"/)) {
            head = substr(line, RSTART, RLENGTH)
            escaped = (substr(head, length(head) - 1, 1) == "e")
            line = substr(line, RSTART + RLENGTH)

            cmd = ""
            i = 1
            n = length(line)
            while (i <= n) {
                c = substr(line, i, 1)
                if (escaped && c == "\\" && i < n) {
                    nc = substr(line, i + 1, 1)
                    if (nc == "\"" || nc == "\\") { cmd = cmd nc; i += 2; continue }
                }
                if (c == "\"") break
                cmd = cmd c
                i++
            }
            print cmd
            line = substr(line, i + 1)
        }
    }'
}

# ---------------------------------------------------------------------------
# Turn one RUN command into an ExecStart= line, or fail.
#
# The '-' prefix mirrors udev, where every RUN+= fires regardless of the
# previous one's exit status.
#
# Refusals matter here: systemd expands % specifiers and $VAR in ExecStart, and
# udev expands its own %k / $env{} substitutions before running RUN. Neither can
# be reproduced by the other, so a command using either is not translatable and
# the script stops instead of installing something subtly wrong.
# ---------------------------------------------------------------------------
CommandToExecStart()
{
    CMD="$1"

    case "$CMD" in
        /*) ;;
        *)
            echo "ERROR: RUN command is not an absolute path, cannot convert:" >&2
            echo "       $CMD" >&2
            return 1
            ;;
    esac

    case "$CMD" in
        *%*)
            echo "ERROR: RUN command contains '%' (udev or systemd specifier):" >&2
            echo "       $CMD" >&2
            echo "       systemd would re-expand it in ExecStart. Convert this rule by hand." >&2
            return 1
            ;;
        *\$*)
            echo "ERROR: RUN command contains '\$' (udev substitution or shell variable):" >&2
            echo "       $CMD" >&2
            echo "       systemd would re-expand it in ExecStart. Convert this rule by hand." >&2
            return 1
            ;;
    esac

    printf 'ExecStart=-%s\n' "$CMD"
    return 0
}

RenderUnitBody()
{
    UNIT_EXECS="$1"
    cat << SERVICEEOF
[Unit]
Description=Dell iSM USB NIC hotplug handler
Documentation=${DOC_URL}
After=systemd-udevd.service

[Service]
Type=oneshot
# The daemon these commands fork lives in this unit's cgroup. With
# RemainAfterExit=no the unit would go inactive as soon as the last ExecStart
# returned, and systemd's default KillMode=control-group would take the daemon
# down with it.
RemainAfterExit=yes
${UNIT_EXECS}
SERVICEEOF
}

# ---------------------------------------------------------------------------
# Parse the installed Dell rule into the units and rule lines to write.
#
# Source is the diverted original when the fix was applied before, otherwise the
# live rule. Every line is accounted for: ACTION=="add" lines carrying RUN+= are
# converted, everything else is passed through verbatim so nothing is dropped.
# ---------------------------------------------------------------------------
ParseDellRule()
{
    if [ -f "$DIVERTED_RULE_FILE" ]; then
        SOURCE_RULE="$DIVERTED_RULE_FILE"
    elif [ -f "$UDEV_RULE_FILE" ]; then
        SOURCE_RULE="$UDEV_RULE_FILE"
    else
        echo "ERROR: $UDEV_RULE_FILE not found."
        echo "       Install the dcism package first, or this iSM version does not ship"
        echo "       the USB NIC udev rule (in which case the fix is not needed)."
        return 1
    fi

    # Join backslash continuations, drop comments and blank lines.
    RULE_BODY=$(sed -e :a -e '/\\$/N; s/\\[[:space:]]*\n[[:space:]]*//; ta' "$SOURCE_RULE" \
                | grep -v '^[[:space:]]*#' | grep -v '^[[:space:]]*$')

    if [ -z "$RULE_BODY" ]; then
        echo "ERROR: $SOURCE_RULE contains no rules."
        return 1
    fi

    CONVERTED=0
    while IFS= read -r LINE; do
        [ -z "$LINE" ] && continue

        if ! printf '%s\n' "$LINE" | grep -q 'RUN[^=]*+='; then
            RULE_OUT[${#RULE_OUT[@]}]="$LINE"
            continue
        fi

        # Only add-time rules run at boot, and SYSTEMD_WANTS is only honoured for
        # add/change. Anything else keeps Dell's original behaviour.
        if ! printf '%s\n' "$LINE" | grep -q 'ACTION=="add"'; then
            RULE_OUT[${#RULE_OUT[@]}]="$LINE"
            PLAN_NOTES[${#PLAN_NOTES[@]}]="left unchanged (not ACTION==\"add\", never runs at boot): $LINE"
            continue
        fi

        MATCH_KEYS=$(printf '%s\n' "$LINE" \
                     | sed -e 's/[[:space:]]*RUN[^=]*+=.*$//' -e 's/[[:space:]]*,[[:space:]]*$//')
        if [ -z "$MATCH_KEYS" ]; then
            echo "ERROR: could not extract device match keys from:"
            echo "       $LINE"
            return 1
        fi

        UNIT_EXECS=""
        CMD_COUNT=0
        while IFS= read -r CMD; do
            [ -z "$CMD" ] && continue
            EXEC_LINE=$(CommandToExecStart "$CMD") || return 1
            UNIT_EXECS="${UNIT_EXECS}${EXEC_LINE}"$'\n'
            CMD_COUNT=$((CMD_COUNT + 1))
        done <<EOF
$(ExtractRunCommands "$LINE")
EOF

        if [ "$CMD_COUNT" -eq 0 ]; then
            echo "ERROR: found RUN+= but could not extract any command from:"
            echo "       $LINE"
            return 1
        fi

        CONVERTED=$((CONVERTED + 1))
        if [ "$CONVERTED" -eq 1 ]; then
            UNIT_NAME="${SERVICE_BASE}.service"
        else
            UNIT_NAME="${SERVICE_BASE}-${CONVERTED}.service"
        fi

        UNIT_NAMES[${#UNIT_NAMES[@]}]="$UNIT_NAME"
        UNIT_BODIES[${#UNIT_BODIES[@]}]="$(RenderUnitBody "$UNIT_EXECS")"
        RULE_OUT[${#RULE_OUT[@]}]="${MATCH_KEYS}, TAG+=\"systemd\", ENV{SYSTEMD_WANTS}=\"${UNIT_NAME}\""
    done <<EOF
$RULE_BODY
EOF

    if [ "$CONVERTED" -eq 0 ]; then
        if printf '%s\n' "$RULE_BODY" | grep -q "SYSTEMD_WANTS"; then
            echo "ERROR: $SOURCE_RULE already hands off to systemd and carries no"
            echo "       original RUN+= rule to derive commands from."
            echo "       The fix appears to be applied already; nothing to do."
        else
            echo "ERROR: no ACTION==\"add\" rule with RUN+= found in $SOURCE_RULE —"
            echo "       nothing that could hang the boot. Contents:"
            printf '%s\n' "$RULE_BODY" | sed 's/^/       | /'
        fi
        return 1
    fi

    return 0
}

RenderRuleFile()
{
    cat << RULEEOF
# Dell USBNIC Device — patched for Debian/Proxmox systemd compatibility.
# Dell's original rule used blocking RUN+= which hangs udev-settle on Debian and
# leaves the host with no network at boot. Match keys below are copied verbatim
# from that rule; its RUN+= commands now live in ${SERVICE_BASE}*.service.
# Original preserved by dpkg-divert at ${DIVERTED_RULE_FILE}
RULEEOF
    printf '%s\n' ${RULE_OUT[@]+"${RULE_OUT[@]}"}
}

ShowPlan()
{
    echo "Rule lines converted: ${#UNIT_NAMES[@]}"
    echo ""
    I=0
    while [ "$I" -lt "${#UNIT_NAMES[@]}" ]; do
        echo "--- ${SERVICE_DIR}/${UNIT_NAMES[$I]} ---"
        printf '%s\n' "${UNIT_BODIES[$I]}"
        I=$((I + 1))
    done
    echo "--- $UDEV_RULE_FILE ---"
    RenderRuleFile
    if [ "${#PLAN_NOTES[@]}" -gt 0 ]; then
        echo ""
        echo "Notes:"
        printf '  - %s\n' ${PLAN_NOTES[@]+"${PLAN_NOTES[@]}"}
    fi
}

# ---------------------------------------------------------------------------
# Apply
#
# Order matters: everything that can still fail happens before the diversion.
# Once the original rule is diverted away, a later failure would leave the host
# with no working rule at all.
# ---------------------------------------------------------------------------
VerifyUnits()
{
    command -v systemd-analyze > /dev/null 2>&1 || return 0

    STAGE_DIR=$(mktemp -d) || return 0
    I=0
    while [ "$I" -lt "${#UNIT_NAMES[@]}" ]; do
        printf '%s\n' "${UNIT_BODIES[$I]}" > "${STAGE_DIR}/${UNIT_NAMES[$I]}"
        I=$((I + 1))
    done

    VERIFY_OUT=$(systemd-analyze verify "${STAGE_DIR}"/*.service 2>&1)
    VERIFY_RC=$?
    rm -rf "$STAGE_DIR"

    if [ "$VERIFY_RC" -ne 0 ]; then
        echo "ERROR: generated unit failed systemd-analyze verify:"
        printf '%s\n' "$VERIFY_OUT" | sed 's/^/       /'
        return 1
    fi
    return 0
}

RemoveStaleUnits()
{
    for EXISTING in "${SERVICE_DIR}/${SERVICE_BASE}"*.service; do
        [ -f "$EXISTING" ] || continue
        KEEP=0
        for NAME in ${UNIT_NAMES[@]+"${UNIT_NAMES[@]}"}; do
            [ "$(basename "$EXISTING")" = "$NAME" ] && KEEP=1
        done
        if [ "$KEEP" -eq 0 ]; then
            echo "  - Removing stale unit: $EXISTING"
            systemctl disable "$(basename "$EXISTING")" > /dev/null 2>&1
            rm -f "$EXISTING"
        fi
    done
}

ApplyDebianUdevFix()
{
    echo "Applying dcism udev boot fix..."

    VerifyUnits || return 1

    # Step 1: install the oneshot handlers carrying Dell's own commands
    I=0
    while [ "$I" -lt "${#UNIT_NAMES[@]}" ]; do
        if ! printf '%s\n' "${UNIT_BODIES[$I]}" > "${SERVICE_DIR}/${UNIT_NAMES[$I]}"; then
            echo "ERROR: failed to create ${SERVICE_DIR}/${UNIT_NAMES[$I]}"
            return 1
        fi
        I=$((I + 1))
    done
    RemoveStaleUnits

    if ! RELOAD_OUT=$(systemctl daemon-reload 2>&1); then
        echo "ERROR: systemctl daemon-reload failed:"
        printf '%s\n' "$RELOAD_OUT" | sed 's/^/       /'
        echo "       Original udev rule left in place; nothing was diverted."
        return 1
    fi

    # Step 2: divert so dcism upgrades cannot restore the blocking rule
    if ! dpkg-divert --list "$UDEV_RULE_FILE" | grep -q "$UDEV_RULE_FILE"; then
        if ! DIVERT_OUT=$(dpkg-divert --local --rename --add "$UDEV_RULE_FILE" 2>&1); then
            echo "ERROR: dpkg-divert failed for $UDEV_RULE_FILE:"
            printf '%s\n' "$DIVERT_OUT" | sed 's/^/       /'
            return 1
        fi
    fi

    # Step 3: replacement rule
    if ! RenderRuleFile > "$UDEV_RULE_FILE"; then
        echo "ERROR: failed to write fixed udev rule to $UDEV_RULE_FILE"
        return 1
    fi

    if ! UDEV_OUT=$(udevadm control --reload-rules 2>&1); then
        echo "WARNING: 'udevadm control --reload-rules' failed:"
        printf '%s\n' "$UDEV_OUT" | sed 's/^/         /'
        echo "         The new rule is on disk and takes effect at next boot anyway."
    fi

    echo "udev boot fix applied successfully."
    I=0
    while [ "$I" -lt "${#UNIT_NAMES[@]}" ]; do
        echo "  - Installed: ${SERVICE_DIR}/${UNIT_NAMES[$I]}"
        I=$((I + 1))
    done
    echo "  - Diverted:  $DIVERTED_RULE_FILE (original preserved)"
    echo "  - Replaced:  $UDEV_RULE_FILE (non-blocking systemd handoff)"
    echo ""
    echo "Reboot to verify. Expected afterwards:"
    echo "  systemctl is-system-running   -> running (not degraded)"
    echo "  ip -br a                      -> vmbr0 UP with its address"
    echo "  systemctl status dcismeng     -> active (running)"
    return 0
}

# ---------------------------------------------------------------------------
# Sourced by tests/run-tests.sh to exercise the parser directly.
[ "${ISM_FIX_SOURCE_ONLY:-0}" = "1" ] && return 0

if [ $# -ne 0 ]; then
    echo "Usage: $0"
    exit 2
fi

PreflightChecks || exit 1
ParseDellRule  || exit 1
ReportEnvironment
ShowPlan
echo ""
ApplyDebianUdevFix
exit $?
