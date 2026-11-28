#!/system/bin/sh

LOG=/data/local/tmp/adguard-postroot-gate.log
UI_XML=/data/local/tmp/adguard-postroot-ui.xml
MODDIR=${MODDIR:-/data/adb/modules/adguard_postroot_gate}
CONFIG="$MODDIR/automation.conf"
GATE_PACKAGE=com.coolak.samsungbootgate
GATE_SERVICE="$GATE_PACKAGE/.GateVpnService"
ADGUARD_PACKAGE=com.adguard.android
ADGUARD_COMPONENT="$ADGUARD_PACKAGE/.receiver.AutomationReceiver"
ADGUARD_BOOT_COMPONENT="$ADGUARD_PACKAGE/.receiver.BootUpReceiver"
ADGUARD_PREFS=/data/user/0/com.adguard.android/shared_prefs/base.xml

exec >"$LOG" 2>&1
echo "controller start $(date) uptime=$(cut -d' ' -f1 /proc/uptime) boot=$(cat /proc/sys/kernel/random/boot_id)"

release_gate() {
    am start-foreground-service -a com.coolak.samsungbootgate.RELEASE -n "$GATE_SERVICE"
}

block_gate() {
    am start-foreground-service -a com.coolak.samsungbootgate.BLOCK -n "$GATE_SERVICE"
}

stop_adguard() {
    am broadcast -a stop -n "$ADGUARD_COMPONENT" --es password "$AGD_PASSWORD" --ez quiet true >/dev/null 2>&1
}

fail_closed() {
    echo "$1"
    settings put secure always_on_vpn_package "$GATE_PACKAGE"
    settings put secure always_on_vpn_lockdown 1
    block_gate
    exit 1
}

routing_is_automatic_proxy() {
    grep -F 'name="routing_mode" value="3"' "$ADGUARD_PREFS" >/dev/null 2>&1
}

protection_is_enabled() {
    grep -F 'name="last_time_protection_enabled" value="true"' "$ADGUARD_PREFS" >/dev/null 2>&1
}

protection_is_disabled() {
    grep -F 'name="last_time_protection_enabled" value="false"' "$ADGUARD_PREFS" >/dev/null 2>&1
}

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

if ! pm disable "$ADGUARD_BOOT_COMPONENT" >/dev/null 2>&1; then
    fail_closed "Cannot disable AdGuard boot receiver"
fi
if ! settings put secure always_on_vpn_package "$GATE_PACKAGE"; then
    fail_closed "Cannot pin the Always-on gate package"
fi
if ! settings put secure always_on_vpn_lockdown 1; then
    fail_closed "Cannot enable Always-on lockdown"
fi
if ! block_gate; then
    fail_closed "Gate block command failed"
fi

GATE_READY=0
I=0
while [ "$I" -lt 30 ]; do
    if ip addr 2>/dev/null | grep -F '10.66.0.2' >/dev/null 2>&1 && ip addr 2>/dev/null | grep -F 'fd66::2' >/dev/null 2>&1; then
        GATE_READY=1
        break
    fi
    I=$((I + 1))
    sleep 1
done
if [ "$GATE_READY" != "1" ]; then
    fail_closed "Blocking tunnel did not appear before AdGuard startup"
fi
echo "Blocking tunnel confirmed before AdGuard startup"

if ! routing_is_automatic_proxy; then
    stop_adguard
    fail_closed "AdGuard is not configured for Automatic proxy; refusing to start it"
fi

# Any protection that preceded KernelSU is stopped. The only start below is
# issued by this root controller after the gate and routing mode are verified.
if protection_is_enabled; then
    stop_adguard
fi
STOPPED=0
I=0
while [ "$I" -lt 30 ]; do
    if protection_is_disabled; then
        STOPPED=1
        break
    fi
    I=$((I + 1))
    sleep 1
done
if [ "$STOPPED" != "1" ]; then
    fail_closed "AdGuard did not stop before the root-controlled start"
fi

am broadcast -a start -n "$ADGUARD_COMPONENT" --es password "$AGD_PASSWORD" --ez quiet true >/dev/null

READY=0
I=0
while [ "$I" -lt 180 ]; do
    if ! routing_is_automatic_proxy; then
        stop_adguard
        fail_closed "AdGuard changed routing mode during startup"
    fi
    if protection_is_enabled; then
        READY=1
        break
    fi
    I=$((I + 1))
    sleep 1
done

if [ "$READY" != "1" ]; then
    stop_adguard
    fail_closed "AdGuard did not persist Protection Enabled"
fi
if ! routing_is_automatic_proxy; then
    stop_adguard
    fail_closed "AdGuard protection is not using Automatic proxy"
fi

# Protection is enabled now. Let only AdGuard reach upstream while every
# other package stays behind the blocking tunnel until both NAT families live.
if ! am start-foreground-service -a com.coolak.samsungbootgate.ALLOW_ADGUARD -n "$GATE_SERVICE"; then
    fail_closed "Cannot enable AdGuard-only upstream"
fi
echo "Protection Enabled; upstream allowed only to AdGuard until NAT is ready"

RULES_READY=0
I=0
while [ "$I" -lt 180 ]; do
    if iptables -S ADGUARD_OUTPUT 2>/dev/null | grep -F 'tcp' | grep -F -- '-j REDIRECT' >/dev/null 2>&1 && ip6tables -S ADGUARD_OUTPUT 2>/dev/null | grep -F 'tcp' | grep -F -- '-j REDIRECT' >/dev/null 2>&1; then
        RULES_READY=1
        break
    fi
    I=$((I + 1))
    sleep 1
done
if [ "$RULES_READY" != "1" ]; then
    stop_adguard
    fail_closed "Automatic proxy NAT rules are not active"
fi

echo "Protection Enabled with Automatic proxy and live NAT rules; allowing startup to settle"
sleep 8
if ! routing_is_automatic_proxy || ! protection_is_enabled; then
    stop_adguard
    fail_closed "AdGuard changed state before network release"
fi
if ! iptables -S ADGUARD_OUTPUT 2>/dev/null | grep -F 'tcp' | grep -F -- '-j REDIRECT' >/dev/null 2>&1 || ! ip6tables -S ADGUARD_OUTPUT 2>/dev/null | grep -F 'tcp' | grep -F -- '-j REDIRECT' >/dev/null 2>&1; then
    stop_adguard
    fail_closed "Automatic proxy NAT rules disappeared before network release"
fi
if ! release_gate; then
    fail_closed "Gate release command failed"
fi

am start --activity-clear-task --activity-new-task -n com.adguard.android/.ui.activity.SplashActivity >/dev/null 2>&1
sleep 2
input tap 108 2125
echo "Network gate released after Protection Enabled and Automatic proxy verification"
exit 0
