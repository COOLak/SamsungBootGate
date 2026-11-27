#!/system/bin/sh

PACKAGE=com.coolak.samsungbootgate
SERVICE="$PACKAGE/.GateVpnService"
ORIGINAL_PACKAGE=$(settings get secure always_on_vpn_package)
ORIGINAL_LOCKDOWN=$(settings get secure always_on_vpn_lockdown)

restore() {
    echo "Restoring Always-on VPN settings"
    settings put secure always_on_vpn_package "$ORIGINAL_PACKAGE"
    settings put secure always_on_vpn_lockdown "$ORIGINAL_LOCKDOWN"
    am start-foreground-service -a com.coolak.samsungbootgate.RELEASE -n "$SERVICE" >/dev/null 2>&1
}
trap restore EXIT

settings put secure always_on_vpn_package "$PACKAGE"
settings put secure always_on_vpn_lockdown 1
am start-foreground-service -a com.coolak.samsungbootgate.BLOCK -n "$SERVICE" >/dev/null
sleep 3
echo "Blocked state: package=$(settings get secure always_on_vpn_package) lockdown=$(settings get secure always_on_vpn_lockdown)"
if curl -fsS -o /dev/null --connect-timeout 2 --max-time 3 https://connectivitycheck.gstatic.com/generate_204; then
    echo "ERROR: network escaped the blocking gate"
else
    echo "OK: network is blocked"
fi

am start-foreground-service -a com.coolak.samsungbootgate.RELEASE -n "$SERVICE" >/dev/null
sleep 3
echo "Released state: package=$(settings get secure always_on_vpn_package) lockdown=$(settings get secure always_on_vpn_lockdown)"
if curl -fsS -o /dev/null --connect-timeout 3 --max-time 5 https://connectivitycheck.gstatic.com/generate_204; then
    echo "OK: network works after release"
else
    echo "ERROR: network remains blocked after release"
fi
sleep 5
echo "Settled state: package=$(settings get secure always_on_vpn_package) lockdown=$(settings get secure always_on_vpn_lockdown)"
if curl -fsS -o /dev/null --connect-timeout 3 --max-time 5 https://connectivitycheck.gstatic.com/generate_204; then
    echo "OK: network remains released"
else
    echo "ERROR: gate re-blocked the network"
fi
