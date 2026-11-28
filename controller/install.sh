#!/bin/bash
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
ZIP="$HERE/AdGuardPostRootGate.zip"
CONFIG="$HERE/adguard-postroot-gate.conf"
BUILD="$HERE/build/adguard_postroot_gate"

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

rm -rf "$BUILD"
mkdir -p "$BUILD"
cp -R "$HERE/adguard-postroot-gate/." "$BUILD/"
cp "$CONFIG" "$BUILD/automation.conf"
chmod 600 "$BUILD/automation.conf"
(
    cd "$BUILD"
    zip -q -r "$ZIP" .
)
adb push "$ZIP" /data/local/tmp/AdGuardPostRootGate.zip >/dev/null
adb shell "su -c 'set -e; rm -rf /data/adb/modules_update/adguard_postroot_gate /data/adb/modules/adguard_postroot_gate; mkdir -p /data/adb/modules/adguard_postroot_gate; /data/adb/ksu/bin/busybox unzip -o /data/local/tmp/AdGuardPostRootGate.zip -d /data/adb/modules/adguard_postroot_gate; chmod 600 /data/adb/modules/adguard_postroot_gate/automation.conf; if command -v restorecon >/dev/null 2>&1; then restorecon -R /data/adb/modules/adguard_postroot_gate; fi; rm -f /data/local/tmp/AdGuardPostRootGate.zip'"
MODULES=$(adb shell "su -c '/data/adb/ksud module list'")
case "$MODULES" in
    *'"id": "adguard_postroot_gate"'*)
        echo "AdGuard post-root controller installed; it runs after the next KernelSU late-load."
        ;;
    *)
        echo "Controller is missing from the KernelSU module list" >&2
        exit 1
        ;;
esac
