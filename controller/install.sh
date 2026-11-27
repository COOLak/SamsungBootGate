#!/bin/bash
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
ZIP="$HERE/AdGuardPostRootGate.zip"
CONFIG="$HERE/adguard-postroot-gate.conf"

if [ ! -r "$CONFIG" ]; then
    echo "Missing $CONFIG" >&2
    exit 1
fi

ROOT_ID=$(adb shell su -c id 2>/dev/null | tr -d '\r')
case "$ROOT_ID" in
    *"uid=0"*) ;;
    *)
        echo "KernelSU root is not available through su" >&2
        exit 1
        ;;
esac

for PACKAGE in com.coolak.samsungbootgate com.adguard.android; do
    PACKAGE_PATH=$(adb shell pm path "$PACKAGE" 2>/dev/null | tr -d '\r')
    case "$PACKAGE_PATH" in
        package:*) ;;
        *)
            echo "Required package is not installed: $PACKAGE" >&2
            exit 1
            ;;
    esac
done

(
    cd "$HERE/adguard-postroot-gate"
    zip -q -r "$ZIP" .
)
adb push "$ZIP" /data/local/tmp/AdGuardPostRootGate.zip >/dev/null
adb push "$CONFIG" /data/local/tmp/adguard-postroot-gate.conf >/dev/null
adb shell su -c 'set -e; /data/adb/ksu/bin/ksud module install /data/local/tmp/AdGuardPostRootGate.zip; cp /data/local/tmp/adguard-postroot-gate.conf /data/adb/adguard-postroot-gate.conf; chmod 600 /data/adb/adguard-postroot-gate.conf; rm -f /data/local/tmp/AdGuardPostRootGate.zip /data/local/tmp/adguard-postroot-gate.conf'
adb shell su -c 'test -r /data/adb/modules/adguard_postroot_gate/service.sh && test -r /data/adb/adguard-postroot-gate.conf'
echo "AdGuard post-root controller installed; it runs after the next KernelSU late-load."
