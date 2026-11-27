package com.wassally.app

import android.content.Intent
import android.net.Uri
import android.os.Build
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
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.wassally.app/device_settings",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "notificationSettings" -> {
                    try {
                        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
                                putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                            }
                        } else {
                            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName"))
                        }
                        startActivity(intent)
                        result.success(true)
                    } catch (error: Exception) {
                        result.error("SETTINGS_UNAVAILABLE", "Cannot open notification settings", null)
                    }
                }
                "batterySettings" -> {
                    try {
                        // App details is safe on Play and lets the user choose Battery >
                        // Unrestricted manually. No REQUEST_IGNORE_BATTERY_OPTIMIZATIONS permission.
                        val intent = Intent(
                            Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                            Uri.parse("package:$packageName"),
                        )
                        startActivity(intent)
                        result.success(true)
                    } catch (error: Exception) {
                        result.error("SETTINGS_UNAVAILABLE", "Cannot open battery settings", null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}
