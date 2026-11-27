#!/system/bin/sh

LOG=/data/local/tmp/adguard-postroot-gate.log
EVENTS=/data/local/tmp/adguard-postroot-events.log
CONFIG=/data/adb/adguard-postroot-gate.conf
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

: >"$EVENTS"
logcat -v time >"$EVENTS" 2>&1 &
LOGGER=$!
cleanup() {
    kill "$LOGGER" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

release_gate() {
    am start-foreground-service -a com.coolak.samsungbootgate.RELEASE -n "$GATE_SERVICE"
}

block_gate() {
    am start-foreground-service -a com.coolak.samsungbootgate.BLOCK -n "$GATE_SERVICE"
}

block_gate
am broadcast -a start -n "$ADGUARD_COMPONENT" --es password "$AGD_PASSWORD" --ez quiet true >/dev/null

READY=0
I=0
while [ "$I" -lt 90 ]; do
    if grep -F 'new: [state=Running' "$EVENTS" >/dev/null 2>&1; then
        READY=1
        break
    fi
    if grep -F 'new: [state=Stopped' "$EVENTS" >/dev/null 2>&1; then
        echo "AdGuard reported a stopped state"
        exit 1
    fi
    I=$((I + 1))
    sleep 1
done

if [ "$READY" != "1" ]; then
    echo "AdGuard did not confirm a running state"
    exit 1
fi

echo "AdGuard confirmed running; releasing gate"
if ! release_gate; then
    echo "Gate release command failed"
    exit 1
fi

sleep 2
if curl -fsS -o /dev/null --max-time 8 https://connectivitycheck.gstatic.com/generate_204; then
    echo "Internet verification passed after AdGuard"
    exit 0
fi

echo "Internet verification failed; blocking again"
block_gate
exit 1
