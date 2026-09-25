package com.ryanheise.audioservice;

import android.content.Context;
import android.content.Intent;
import android.os.Bundle;

public class MediaButtonReceiver extends androidx.media.session.MediaButtonReceiver {
    public static final String ACTION_NOTIFICATION_DELETE = "com.ryanheise.audioservice.intent.action.ACTION_NOTIFICATION_DELETE";
    public static final String ACTION_CUSTOM_ACTION = "com.ryanheise.audioservice.intent.action.ACTION_CUSTOM_ACTION";

    @Override
    public void onReceive(Context context, Intent intent) {
        if (intent != null && AudioService.instance != null) {
            if (ACTION_NOTIFICATION_DELETE.equals(intent.getAction())) {
                AudioService.instance.handleDeleteNotification();
                return;
            }
            if (ACTION_CUSTOM_ACTION.equals(intent.getAction())) {
                String actionName = intent.getStringExtra("action_name");
                Bundle extras = intent.getBundleExtra("action_extras");
                AudioService.instance.handleCustomAction(actionName, extras);
                return;
            }
        }
        super.onReceive(context, intent);
    }
}
