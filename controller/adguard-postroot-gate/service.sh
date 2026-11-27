#!/system/bin/sh

LOG=/data/local/tmp/adguard-postroot-gate.log
UI_XML=/data/local/tmp/adguard-postroot-ui.xml
MODDIR=${MODDIR:-/data/adb/modules/adguard_postroot_gate}
CONFIG="$MODDIR/automation.conf"
GATE_PACKAGE=com.coolak.samsungbootgate
GATE_SERVICE="$GATE_PACKAGE/.GateVpnService"
ADGUARD_COMPONENT=com.adguard.android/.receiver.AutomationReceiver

exec >"$LOG" 2>&1
echo "controller start $(date)"

if [ "$(id -u)" != "0" ]; then
    echo "root UID is unavailable"
    exit 1
fi
if ! grep -q '^kernelsu ' /proc/modules; then
    echo "KernelSU module is not live"
    exit 1
fi
if [ ! -r "$CONFIG" ]; then
    echo "Automation config is missing"
    exit 1
fi
. "$CONFIG"
if [ -z "$AGD_PASSWORD" ]; then
    echo "Automation password is empty"
    exit 1
fi

release_gate() {
    am start-foreground-service -a com.coolak.samsungbootgate.RELEASE -n "$GATE_SERVICE"
}

block_gate() {
    am start-foreground-service -a com.coolak.samsungbootgate.BLOCK -n "$GATE_SERVICE"
}

fail_closed() {
    echo "$1"
    settings put secure always_on_vpn_lockdown 1
    block_gate
    svc wifi disable
    svc data disable
    exit 1
}

if ! block_gate; then
    fail_closed "Gate block command failed"
fi
settings put secure always_on_vpn_lockdown 1
am broadcast -a start -n "$ADGUARD_COMPONENT" --es password "$AGD_PASSWORD" --ez quiet true >/dev/null
am start -n com.adguard.android/.ui.activity.SplashActivity >/dev/null 2>&1
: >"$UI_XML"

READY=0
I=0
while [ "$I" -lt 90 ]; do
    if uiautomator dump "$UI_XML" >/dev/null 2>&1; then
        if grep -F 'Main protection switch on' "$UI_XML" >/dev/null 2>&1; then
            READY=1
            break
        fi
        if grep -F 'Protection is enabled' "$UI_XML" >/dev/null 2>&1; then
            READY=1
            break
        fi
    fi
    I=$((I + 1))
    sleep 1
done

if [ "$READY" != "1" ]; then
    fail_closed "AdGuard did not confirm a running state"
fi

echo "AdGuard confirmed running; enabling radios and releasing gate"
svc wifi enable
svc data enable
if ! settings put secure always_on_vpn_lockdown 0; then
    fail_closed "Cannot release lockdown"
fi
if ! release_gate; then
    fail_closed "Gate release command failed"
fi

I=0
while [ "$I" -lt 10 ]; do
    if curl -fsS -o /dev/null --connect-timeout 3 --max-time 5 https://connectivitycheck.gstatic.com/generate_204; then
        echo "Internet verification passed after AdGuard"
        exit 0
    fi
    I=$((I + 1))
    sleep 1
done

fail_closed "Internet verification failed; blocking again"
