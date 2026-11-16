package com.photobooth.kiosk

import android.app.admin.DevicePolicyManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

class KioskBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED) return
        val preferences = context.getSharedPreferences("photobooth_kiosk", Context.MODE_PRIVATE)
        if (preferences.getBoolean("kiosk_disabled", false)) return

        val policy = context.getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
        if (!policy.isDeviceOwnerApp(context.packageName)) {
            Log.w("PhotoboothKiosk", "Boot relaunch requires device-owner provisioning.")
            return
        }

        val launch = Intent(context, MainActivity::class.java).apply {
            action = Intent.ACTION_MAIN
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        }
        context.startActivity(launch)
    }
}
