#!/system/bin/sh

LOG=/data/local/tmp/adguard-postroot-gate.log
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
    uiautomator dump /data/local/tmp/adguard-postroot-ui.xml >/dev/null 2>&1
    grep -F 'text="Protection is enabled" resource-id="com.adguard.android:id/protection_status"' /data/local/tmp/adguard-postroot-ui.xml >/dev/null 2>&1
}

ipv4_proxy_rules_active() {
    iptables -t nat -S ADGUARD_OUTPUT 2>/dev/null | grep -F 'tcp' | grep -F -- '-j REDIRECT' >/dev/null 2>&1
}

ipv6_proxy_rules_active() {
    if ip6tables -t mangle -S ADGUARD_OUTPUT 2>/dev/null | grep -F 'tcp' | grep -F 'MARK --set-xmark 0x1b' >/dev/null 2>&1 && ip6tables -S ADGUARD_INPUT 2>/dev/null | grep -F -- '--mark 0x1b' | grep -F 'tcp' | grep -F 'ACCEPT' >/dev/null 2>&1; then
        return 0
    fi
    ip6tables -t nat -S ADGUARD_OUTPUT 2>/dev/null | grep -F 'tcp' | grep -F -- '-j REDIRECT' >/dev/null 2>&1
}

proxy_is_live() {
    routing_is_automatic_proxy && ipv4_proxy_rules_active && ipv6_proxy_rules_active && protection_is_enabled
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
while [ "$I" -lt 15 ]; do
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

# Launch the original UI only from the root controller. This raises startup
# priority on a memory-constrained fresh boot without changing routing mode.
am start -n com.adguard.android/.ui.activity.SplashActivity >/dev/null 2>&1
sleep 5

READY=0
STABLE=0
I=0
while [ "$I" -lt 65 ]; do
    if ! routing_is_automatic_proxy; then
        stop_adguard
        fail_closed "AdGuard changed routing mode during startup"
    fi
    if proxy_is_live; then
        STABLE=$((STABLE + 1))
    else
        STABLE=0
    fi
    if [ "$STABLE" -ge 5 ]; then
        READY=1
        break
    fi
    if [ $((I % 10)) -eq 0 ]; then
        uiautomator dump /data/local/tmp/adguard-postroot-ui.xml >/dev/null 2>&1
        if grep -F 'Main protection switch off' /data/local/tmp/adguard-postroot-ui.xml >/dev/null 2>&1; then
            echo "Starting protection through the original AdGuard UI as root: attempt $((I / 10 + 1))"
            input tap 540 1180
        else
            echo "Original AdGuard is starting or enabled; waiting for five stable live checks"
        fi
    fi
    I=$((I + 1))
    sleep 1
done

if [ "$READY" != "1" ]; then
    echo "Final proxy diagnostics before fail-closed"
    iptables -t nat -S ADGUARD_OUTPUT 2>&1 | grep -E 'REDIRECT|MARK|No chain'
    ip6tables -t mangle -S ADGUARD_OUTPUT 2>&1 | grep -E 'REDIRECT|MARK|No chain'
    ip6tables -S ADGUARD_INPUT 2>&1 | grep -E 'ACCEPT|No chain'
    stop_adguard
    fail_closed "AdGuard did not sustain live Automatic proxy rules within 65s"
fi

echo "Original Protection is enabled and proxy rules stayed live for five checks"
if ! release_gate; then
    fail_closed "Gate release command failed"
fi

sleep 3
if ! proxy_is_live; then
    stop_adguard
    fail_closed "AdGuard proxy disappeared after network release"
fi
echo "Network gate released after live Automatic proxy verification"
exit 0
