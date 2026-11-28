package com.coolak.samsungbootgate;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.provider.Settings;
import android.util.Log;

public final class BootReceiver extends BroadcastReceiver {
    @Override
    public void onReceive(Context context, Intent intent) {
        boolean packageStored = Settings.Secure.putString(
            context.getContentResolver(),
            "always_on_vpn_package",
            "com.coolak.samsungbootgate"
        );
        boolean lockdownStored = Settings.Secure.putInt(
            context.getContentResolver(),
            "always_on_vpn_lockdown",
            1
        );
        if (!packageStored || !lockdownStored) {
            Log.e("SamsungBootGate", "Cannot rearm Always-on boot gate");
            return;
        }
        Log.i("SamsungBootGate", "Always-on boot gate rearmed");
        if (Intent.ACTION_LOCKED_BOOT_COMPLETED.equals(intent.getAction())) {
            try {
                GateVpnService.requestBlock(context);
                Log.i("SamsungBootGate", "Direct-boot blocking tunnel requested");
            } catch (Throwable error) {
                Log.e("SamsungBootGate", "Cannot start direct-boot blocking tunnel", error);
            }
        }
    }
}
