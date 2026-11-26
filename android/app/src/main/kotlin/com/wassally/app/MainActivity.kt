package com.wassally.app

import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.wassally.app/referral_device",
        ).setMethodCallHandler { call, result ->
            if (call.method == "androidScopedId") {
                // Android 8+: scoped to signing key, Android user and device.
                // Do not persist or log this raw value on device or Firebase.
                val id = Settings.Secure.getString(contentResolver, Settings.Secure.ANDROID_ID)
                if (id != null && Regex("^[a-fA-F0-9]{16}$").matches(id)) {
                    result.success(id.lowercase())
                } else {
                    result.error("DEVICE_UNAVAILABLE", "Cannot verify device eligibility", null)
                }
            } else {
                result.notImplemented()
            }
        }
    }
}
