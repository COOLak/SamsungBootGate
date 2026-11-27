package com.coolak.samsungbootgate;

import android.app.Activity;
import android.content.Intent;
import android.net.VpnService;
import android.os.Bundle;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.TextView;

public final class MainActivity extends Activity {
    private static final int VPN_CONSENT = 1001;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        int padding = (int) (24 * getResources().getDisplayMetrics().density);
        LinearLayout layout = new LinearLayout(this);
        layout.setOrientation(LinearLayout.VERTICAL);
        layout.setPadding(padding, padding, padding, padding);

        TextView text = new TextView(this);
        text.setText(
            "Samsung Boot Gate\n\n" +
            "Blocks IPv4 and IPv6 until the post-root AdGuard controller releases this boot. " +
            "Enable Always-on VPN and Block connections without VPN in Android settings."
        );
        text.setTextSize(18);
        layout.addView(text);

        Button arm = new Button(this);
        arm.setText("Prepare and start gate");
        arm.setOnClickListener(view -> prepareAndStart());
        layout.addView(arm);

        Button settings = new Button(this);
        settings.setText("Open Android VPN settings");
        settings.setOnClickListener(view -> startActivity(new Intent("android.settings.VPN_SETTINGS")));
        layout.addView(settings);

        Button release = new Button(this);
        release.setText("Release this boot (test)");
        release.setOnClickListener(view -> GateVpnService.requestRelease(this));
        layout.addView(release);

        setContentView(layout);
    }

    private void prepareAndStart() {
        Intent consent = VpnService.prepare(this);
        if (consent != null) {
            startActivityForResult(consent, VPN_CONSENT);
        } else {
            GateVpnService.requestBlock(this);
        }
    }

    @Override
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if (requestCode == VPN_CONSENT && resultCode == RESULT_OK) {
            GateVpnService.requestBlock(this);
        }
    }
}
