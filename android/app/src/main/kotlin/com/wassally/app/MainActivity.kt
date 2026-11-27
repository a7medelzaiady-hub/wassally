package com.wassally.app

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var reusedEngine = false

    /**
     * #326: على الموبايلات قليلة الرامات أندرويد بيقفل الـActivity في الخلفية والتطبيق
     * لسه شغال. افتراضيًا Flutter كان بيقفل المحرك معاها، فالرجوع للتطبيق كان بيعيد
     * main() من الأول (شاشة بيضا + تهيئة Firebase + الرجوع للرئيسية).
     * هنا المحرك بيتحفظ طول ما العملية عايشة، فالـActivity الجديدة بترجع لنفس الشاشة فورًا.
     * أول تشغيل بيعمل محرك جديد مش شغال، فـFlutter بيبدأه بنفسه بمسار الرابط (لو فيه).
     */
    override fun provideFlutterEngine(context: Context): FlutterEngine {
        FlutterEngineCache.getInstance().get(ENGINE_ID)?.let {
            reusedEngine = true
            return it
        }
        val engine = FlutterEngine(context.applicationContext)
        FlutterEngineCache.getInstance().put(ENGINE_ID, engine)
        return engine
    }

    // المحرك يعيش بعد قفل الـActivity (لحد ما أندرويد يقفل العملية كلها).
    override fun shouldDestroyEngineWithHost(): Boolean = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // المحرك كان شغال فـFlutter مش هيقرا رابط الفتح الجديد لوحده: نبعته زي onNewIntent.
        // (savedInstanceState != null يعني استرجاع نفس الشاشة، مش فتح رابط جديد.)
        if (reusedEngine && savedInstanceState == null) {
            routeFromIntent(intent)?.let { flutterEngine?.navigationChannel?.pushRouteInformation(it) }
        }
    }

    private fun routeFromIntent(intent: Intent?): String? {
        if (intent?.action != Intent.ACTION_VIEW) return null
        val data = intent.data ?: return null
        val path = data.path?.takeIf { it.isNotEmpty() } ?: return null
        return if (data.query.isNullOrEmpty()) path else "$path?${data.query}"
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        // الـActivity دي اتقفلت: ما نسيبش القنوات ماسكة فيها (الجديدة بتسجّلها تاني).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, REFERRAL_CHANNEL)
            .setMethodCallHandler(null)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SETTINGS_CHANNEL)
            .setMethodCallHandler(null)
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            REFERRAL_CHANNEL,
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
            SETTINGS_CHANNEL,
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

    companion object {
        private const val ENGINE_ID = "wasally_main"
        private const val REFERRAL_CHANNEL = "com.wassally.app/referral_device"
        private const val SETTINGS_CHANNEL = "com.wassally.app/device_settings"
    }
}
