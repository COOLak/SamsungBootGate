package com.coolak.samsungbootgate;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.net.VpnService;
import android.os.ParcelFileDescriptor;
import android.util.Log;

import java.io.BufferedReader;
import java.io.FileReader;
import java.io.IOException;

public final class GateVpnService extends VpnService {
    public static final String ACTION_BLOCK = "com.coolak.samsungbootgate.BLOCK";
    public static final String ACTION_RELEASE = "com.coolak.samsungbootgate.RELEASE";
    private static final String CHANNEL = "gate";
    private static final String PREFS = "boot_state";
    private static final String KEY_RELEASED_BOOT = "released_boot";
    private static final int NOTIFICATION_ID = 1;
    private ParcelFileDescriptor tunnel;

    public static void requestBlock(Context context) {
        start(context, ACTION_BLOCK);
    }

    public static void requestRelease(Context context) {
        start(context, ACTION_RELEASE);
    }

    private static void start(Context context, String action) {
        Intent intent = new Intent(context, GateVpnService.class).setAction(action);
        context.startForegroundService(intent);
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        startForeground(NOTIFICATION_ID, buildNotification());
        String action = intent == null ? null : intent.getAction();
        String bootId = currentBootId();
        if (bootId.isEmpty()) {
            blockCurrentBoot();
        } else if (ACTION_RELEASE.equals(action)) {
            releaseCurrentBoot(bootId);
        } else if (ACTION_BLOCK.equals(action)) {
            blockCurrentBoot();
        } else if (bootId.equals(releasedBootId())) {
            releaseTunnel();
        } else {
            blockCurrentBoot();
        }
        return START_STICKY;
    }

    private void blockCurrentBoot() {
        if (tunnel != null) {
            return;
        }
        try {
            tunnel = new Builder()
                .setSession("Samsung Boot Gate")
                .setBlocking(true)
                .addAddress("10.66.0.2", 32)
                .addRoute("0.0.0.0", 0)
                .addAddress("fd66::2", 128)
                .addRoute("::", 0)
                .establish();
            if (tunnel == null) {
                throw new IOException("VpnService.Builder.establish returned null");
            }
            Log.i("SamsungBootGate", "BLOCKED boot=" + currentBootId());
        } catch (Throwable error) {
            Log.e("SamsungBootGate", "Failed to establish blocking VPN", error);
            stopSelf();
        }
    }

    private void releaseCurrentBoot(String bootId) {
        boolean stored = devicePreferences().edit().putString(KEY_RELEASED_BOOT, bootId).commit();
        if (!stored) {
            Log.e("SamsungBootGate", "Cannot persist released boot; staying blocked");
            blockCurrentBoot();
            return;
        }
        releaseTunnel();
    }

    private void releaseTunnel() {
        closeTunnel();
        stopForeground(true);
        stopSelf();
        Log.i("SamsungBootGate", "RELEASED boot=" + currentBootId());
    }

    private void closeTunnel() {
        if (tunnel != null) {
            try {
                tunnel.close();
            } catch (IOException error) {
                Log.w("SamsungBootGate", "Failed to close tunnel", error);
            }
            tunnel = null;
        }
    }

    private String currentBootId() {
        try (BufferedReader reader = new BufferedReader(new FileReader("/proc/sys/kernel/random/boot_id"))) {
            String line = reader.readLine();
            return line == null ? "" : line.trim();
        } catch (Throwable error) {
            Log.e("SamsungBootGate", "Cannot read boot ID", error);
            return "";
        }
    }

    private String releasedBootId() {
        return devicePreferences().getString(KEY_RELEASED_BOOT, "");
    }

    private SharedPreferences devicePreferences() {
        Context storage = createDeviceProtectedStorageContext();
        return storage.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
    }

    private Notification buildNotification() {
        NotificationManager manager = getSystemService(NotificationManager.class);
        manager.createNotificationChannel(
            new NotificationChannel(CHANNEL, "Samsung Boot Gate", NotificationManager.IMPORTANCE_LOW)
        );
        return new Notification.Builder(this, CHANNEL)
            .setContentTitle("Samsung Boot Gate")
            .setContentText("Blocking network until KernelSU and AdGuard are ready")
            .setSmallIcon(android.R.drawable.ic_lock_lock)
            .setOngoing(true)
            .build();
    }

    @Override
    public void onRevoke() {
        closeTunnel();
        stopSelf();
    }

    @Override
    public void onDestroy() {
        closeTunnel();
        super.onDestroy();
    }
}
