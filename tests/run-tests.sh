#!/bin/bash
# Parser tests for apply-udev-fix.sh.
#
# Sources the script with ISM_FIX_SOURCE_ONLY=1 so no system paths are touched,
# points UDEV_RULE_FILE at a fixture, and checks what ParseDellRule derived.
# Run: ./tests/run-tests.sh   (no root, no dcism, no systemd required)

set -u

TESTS_DIR=$(cd -- "$(dirname -- "$0")" && pwd -P)
SCRIPT="${TESTS_DIR}/../apply-udev-fix.sh"
FIXTURES="${TESTS_DIR}/fixtures"

PASS=0
FAIL=0

Report()
{
    if [ "$1" = "pass" ]; then
        PASS=$((PASS + 1))
        printf 'ok   %s\n' "$2"
    else
        FAIL=$((FAIL + 1))
        printf 'FAIL %s\n' "$2"
        [ $# -gt 2 ] && printf '%s\n' "$3" | sed 's/^/       /'
    fi
}

# Parse a fixture in a subshell, print "RC=<rc>" then the plan (or the error).
# ParseDellRule fills shell arrays, so it must not be run inside a command
# substitution — its output goes to a temp file instead.
ParseFixture()
{
    (
        UDEV_RULE_FILE="${FIXTURES}/$1"
        SERVICE_DIR="/etc/systemd/system"
        ISM_FIX_SOURCE_ONLY=1
        export UDEV_RULE_FILE SERVICE_DIR ISM_FIX_SOURCE_ONLY
        # shellcheck disable=SC1090
        . "$SCRIPT"
        LOG=$(mktemp)
        ParseDellRule > "$LOG" 2>&1
        RC=$?
        echo "RC=$RC"
        cat "$LOG"
        rm -f "$LOG"
        [ "$RC" -eq 0 ] && ShowPlan 2>&1
        exit 0
    )
}

AssertContains()
{
    NAME="$1"; FIXTURE="$2"; NEEDLE="$3"
    OUT=$(ParseFixture "$FIXTURE")
    if printf '%s\n' "$OUT" | grep -qF -- "$NEEDLE"; then
        Report pass "$NAME"
    else
        Report fail "$NAME" "expected to find: $NEEDLE
--- actual ---
$OUT"
    fi
}

AssertNotContains()
{
    NAME="$1"; FIXTURE="$2"; NEEDLE="$3"
    OUT=$(ParseFixture "$FIXTURE")
    if printf '%s\n' "$OUT" | grep -qF -- "$NEEDLE"; then
        Report fail "$NAME" "did not expect: $NEEDLE
--- actual ---
$OUT"
    else
        Report pass "$NAME"
    fi
}

AssertRc()
{
    NAME="$1"; FIXTURE="$2"; WANT="$3"
    OUT=$(ParseFixture "$FIXTURE")
    GOT=$(printf '%s\n' "$OUT" | sed -n 's/^RC=//p')
    if [ "$GOT" = "$WANT" ]; then
        Report pass "$NAME"
    else
        Report fail "$NAME" "want RC=$WANT, got RC=$GOT
--- actual ---
$OUT"
    fi
}

echo "== 5.4.2 rule form =="
AssertRc        "5.4.2: parses"            ism-5.4.2.rules 0
AssertContains  "5.4.2: keeps match keys"  ism-5.4.2.rules \
    'SUBSYSTEM=="usb", ATTR{idVendor}=="413c", ATTR{idProduct}=="a102", ATTR{manufacturer}=="Dell(TM)", ACTION=="add", TAG+="systemd", ENV{SYSTEMD_WANTS}="dcism-usbnic-hotplug.service"'
AssertContains  "5.4.2: touch command"     ism-5.4.2.rules \
    'ExecStart=-/bin/touch /opt/dell/srvadmin/iSM/etc/ini/usbnicconfig.ini'
AssertContains  "5.4.2: start command"     ism-5.4.2.rules \
    'ExecStart=-/etc/init.d/dcismeng start'
AssertContains  "5.4.2: daemon survives unit exit" ism-5.4.2.rules 'RemainAfterExit=yes'

echo "== line continuation + /bin/sh -c =="
AssertRc        "continuation: parses"     continuation-and-shell.rules 0
AssertContains  "continuation: sh -c not double-wrapped" continuation-and-shell.rules \
    "ExecStart=-/bin/sh -c 'echo 1 > /opt/dell/srvadmin/iSM/var/usbnic.flag'"
AssertContains  "continuation: second command" continuation-and-shell.rules \
    'ExecStart=-/usr/sbin/dcism-usbnic --start'
AssertContains  "continuation: product id a103" continuation-and-shell.rules \
    'ATTR{idProduct}=="a103"'

echo "== 6.1.0.0 rule form (real hardware) =="
AssertRc        "6.1.0.0: parses"          ism-6.1.0.0.rules 0
AssertContains  "6.1.0.0: same match keys merge into one unit" ism-6.1.0.0.rules \
    'Rule lines converted: 1'
AssertNotContains "6.1.0.0: no second unit" ism-6.1.0.0.rules \
    'dcism-usbnic-hotplug-2.service'
AssertContains  "6.1.0.0: touch ordered before daemon start" ism-6.1.0.0.rules \
    'ExecStart=-/bin/touch /opt/dell/srvadmin/iSM/etc/ini/usbnicconfig.ini
ExecStart=-/etc/init.d/dcismeng start &'
AssertContains  "6.1.0.0: merge reported in notes" ism-6.1.0.0.rules \
    'merged into dcism-usbnic-hotplug.service'
AssertContains  "6.1.0.0: single handoff rule line" ism-6.1.0.0.rules \
    'ATTR{manufacturer}=="Dell(TM)", ACTION=="add", TAG+="systemd", ENV{SYSTEMD_WANTS}="dcism-usbnic-hotplug.service"'

echo "== multiple rule lines =="
AssertRc        "add+remove: parses"       add-and-remove.rules 0
AssertContains  "add+remove: remove line preserved verbatim" add-and-remove.rules \
    'ACTION=="remove", RUN+="/etc/init.d/dcismeng stop"'
AssertContains  "add+remove: add line converted" add-and-remove.rules \
    'ACTION=="add", TAG+="systemd", ENV{SYSTEMD_WANTS}="dcism-usbnic-hotplug.service"'
AssertContains  "two adds: second unit gets its own name" two-add-lines.rules \
    'dcism-usbnic-hotplug-2.service'
AssertContains  "two adds: both commands present" two-add-lines.rules \
    'ExecStart=-/usr/sbin/dcism-usbnic --start'
AssertNotContains "two adds: first line not dropped" two-add-lines.rules \
    'Rule lines converted: 1'

echo "== udev quoting forms =="
AssertContains  "e\"\" escaped quotes decoded" escaped-quotes.rules \
    'ExecStart=-/bin/sh -c "echo 1 > /sys/x"'
AssertContains  "RUN{program}+= recognised"  run-program-form.rules \
    'ExecStart=-/etc/init.d/dcismeng start'

echo "== refusals =="
AssertRc        "%-specifier refused"      udev-specifier.rules 1
AssertContains  "%-specifier explains why" udev-specifier.rules "contains '%'"
AssertRc        "\$-substitution refused"  udev-substitution.rules 1
AssertContains  "\$-substitution explains why" udev-substitution.rules "contains '\$'"
AssertRc        "relative path refused"    relative-path.rules 1
AssertRc        "already-patched refused"  already-patched.rules 1
AssertContains  "already-patched explains why" already-patched.rules "applied already"
AssertRc        "no RUN+= refused"         no-run.rules 1
AssertRc        "missing file refused"     does-not-exist.rules 1

echo "== apply path =="

# Sandbox: real rule/unit paths redirected into a temp tree, and dpkg-divert /
# systemctl / udevadm / systemd-analyze replaced by stubs. DIVERT_MODE and
# RELOAD_MODE let a test force a failure.
MakeSandbox()
{
    SB=$(mktemp -d)
    mkdir -p "$SB/bin" "$SB/units" "$SB/rules"
    cat > "$SB/bin/dpkg-divert" << 'EOF'
#!/bin/bash
case "$1" in
    --list) [ -f "${2}.distrib" ] && echo "local diversion of $2 to ${2}.distrib"; exit 0 ;;
esac
for A in "$@"; do case "$A" in /*) TARGET="$A" ;; esac; done
[ "${DIVERT_MODE:-ok}" = "fail" ] && { echo "dpkg-divert: stub failure" >&2; exit 1; }
mv "$TARGET" "${TARGET}.distrib"
EOF
    cat > "$SB/bin/systemctl" << 'EOF'
#!/bin/bash
if [ "$1" = "daemon-reload" ] && [ "${RELOAD_MODE:-ok}" = "fail" ]; then
    echo "Failed to reload daemon: stub failure" >&2
    exit 1
fi
exit 0
EOF
    cat > "$SB/bin/udevadm" << 'EOF'
#!/bin/bash
exit 0
EOF
    cat > "$SB/bin/systemd-analyze" << 'EOF'
#!/bin/bash
exit 0
EOF
    chmod +x "$SB/bin"/*
    printf '%s\n' "$SB"
}

# Run the full apply path against a fixture inside a sandbox; echo the sandbox dir.
RunApply()
{
    SB=$(MakeSandbox)
    cp "${FIXTURES}/$1" "$SB/rules/95-iSM-usbnic.rules"
    [ $# -gt 1 ] && touch "$SB/units/$2"
    (
        PATH="$SB/bin:$PATH"
        UDEV_RULE_FILE="$SB/rules/95-iSM-usbnic.rules"
        SERVICE_DIR="$SB/units"
        ISM_FIX_SOURCE_ONLY=1
        export PATH UDEV_RULE_FILE SERVICE_DIR ISM_FIX_SOURCE_ONLY
        # shellcheck disable=SC1090
        . "$SCRIPT"
        ParseDellRule > /dev/null 2>&1 && ApplyDebianUdevFix
    ) > "$SB/apply.log" 2>&1
    echo "RC=$?" >> "$SB/apply.log"
    printf '%s\n' "$SB"
}

AssertFile()
{
    NAME="$1"; FILE="$2"; NEEDLE="$3"
    if [ -f "$FILE" ] && grep -qF -- "$NEEDLE" "$FILE"; then
        Report pass "$NAME"
    else
        Report fail "$NAME" "expected '$NEEDLE' in $FILE
--- actual ---
$(cat "$FILE" 2>&1)"
    fi
}

SB=$(RunApply ism-5.4.2.rules)
AssertFile "apply: unit written"        "$SB/units/dcism-usbnic-hotplug.service" 'ExecStart=-/etc/init.d/dcismeng start'
AssertFile "apply: rule rewritten"      "$SB/rules/95-iSM-usbnic.rules" 'ENV{SYSTEMD_WANTS}="dcism-usbnic-hotplug.service"'
AssertFile "apply: original diverted"   "$SB/rules/95-iSM-usbnic.rules.distrib" 'RUN+="/etc/init.d/dcismeng start"'
AssertFile "apply: reports success"     "$SB/apply.log" 'RC=0'
rm -rf "$SB"

SB=$(RunApply ism-5.4.2.rules dcism-usbnic-hotplug-2.service)
if [ -f "$SB/units/dcism-usbnic-hotplug-2.service" ]; then
    Report fail "apply: stale unit removed" "$(cat "$SB/apply.log")"
else
    Report pass "apply: stale unit removed"
fi
rm -rf "$SB"

# daemon-reload failure must abort before the original rule is diverted away.
SB=$(MakeSandbox)
cp "${FIXTURES}/ism-5.4.2.rules" "$SB/rules/95-iSM-usbnic.rules"
(
    PATH="$SB/bin:$PATH"
    UDEV_RULE_FILE="$SB/rules/95-iSM-usbnic.rules"
    SERVICE_DIR="$SB/units"
    ISM_FIX_SOURCE_ONLY=1
    RELOAD_MODE=fail
    export PATH UDEV_RULE_FILE SERVICE_DIR ISM_FIX_SOURCE_ONLY RELOAD_MODE
    # shellcheck disable=SC1090
    . "$SCRIPT"
    ParseDellRule > /dev/null 2>&1 && ApplyDebianUdevFix
) > "$SB/apply.log" 2>&1
echo "RC=$?" >> "$SB/apply.log"
AssertFile "reload failure: reported"        "$SB/apply.log" 'daemon-reload failed'
AssertFile "reload failure: nonzero exit"    "$SB/apply.log" 'RC=1'
AssertFile "reload failure: rule untouched"  "$SB/rules/95-iSM-usbnic.rules" 'RUN+="/etc/init.d/dcismeng start"'
if [ -f "$SB/rules/95-iSM-usbnic.rules.distrib" ]; then
    Report fail "reload failure: nothing diverted" "$(cat "$SB/apply.log")"
else
    Report pass "reload failure: nothing diverted"
fi
rm -rf "$SB"

echo ""
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
