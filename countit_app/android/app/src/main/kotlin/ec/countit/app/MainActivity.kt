package ec.countit.app

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        /** Default channel of every push (COU-106); FCM uses it through the manifest meta-data. */
        const val NOTIFICATION_CHANNEL_ID = "countit_default"
        private const val NOTIFICATION_PERMISSION_REQUEST = 4031
        private const val PREFS = "countit_notifications"
        private const val ASKED = "permission_asked"
    }

    /** Pending «request» call of the notifications channel (one at a time). */
    private var permissionResult: MethodChannel.Result? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createNotificationChannel()
    }

    /** «Count It!» channel, high importance (heads-up), created once; idempotent. */
    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            NOTIFICATION_CHANNEL_ID,
            getString(R.string.notification_channel_name),
            NotificationManager.IMPORTANCE_HIGH,
        ).apply { description = getString(R.string.notification_channel_description) }
        getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }

    /**
     * granted | denied | notDetermined. Before Android 13 there is no runtime
     * permission: only the user's switch in the system settings counts.
     */
    private fun notificationStatus(): String {
        val enabled = Build.VERSION.SDK_INT < Build.VERSION_CODES.N ||
            getSystemService(NotificationManager::class.java).areNotificationsEnabled()
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return if (enabled) "granted" else "denied"
        if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) {
            return if (enabled) "granted" else "denied"
        }
        val asked = getSharedPreferences(PREFS, MODE_PRIVATE).getBoolean(ASKED, false)
        // Refused once, the system still shows the dialog (rationale); refused
        // twice it does not anymore: only Settings can change it.
        return if (!asked || shouldShowRequestPermissionRationale(Manifest.permission.POST_NOTIFICATIONS)) {
            "notDetermined"
        } else {
            "denied"
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != NOTIFICATION_PERMISSION_REQUEST) return
        permissionResult?.success(notificationStatus())
        permissionResult = null
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        // Sensitive screens (passwords, balances) block screenshots, screen
        // recording and the recent-apps thumbnail (COU-115).
        MethodChannel(messenger, "ec.countit.app/secure_screen").setMethodCallHandler { call, result ->
            when (call.method) {
                "enable" -> {
                    window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    result.success(null)
                }
                "disable" -> {
                    window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        // «Abrir app de correo» after registering (COU-110): the inbox of the
        // default e-mail app, never a compose screen.
        MethodChannel(messenger, "ec.countit.app/mail").setMethodCallHandler { call, result ->
            if (call.method != "openInbox") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val intent = Intent(Intent.ACTION_MAIN)
                .addCategory(Intent.CATEGORY_APP_EMAIL)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            try {
                startActivity(intent)
                result.success(true)
            } catch (e: ActivityNotFoundException) {
                result.success(false)
            }
        }

        // Notifications permission (COU-175): asked at a meaningful moment
        // from Dart, never at start-up.
        MethodChannel(messenger, "ec.countit.app/notifications").setMethodCallHandler { call, result ->
            when (call.method) {
                "status" -> result.success(notificationStatus())
                "request" -> {
                    val status = notificationStatus()
                    if (status != "notDetermined" || Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
                        result.success(status)
                    } else if (permissionResult != null) {
                        result.error("busy", "A request is already showing", null)
                    } else {
                        getSharedPreferences(PREFS, MODE_PRIVATE).edit().putBoolean(ASKED, true).apply()
                        permissionResult = result
                        requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), NOTIFICATION_PERMISSION_REQUEST)
                    }
                }
                "openSettings" -> {
                    val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                            .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                    } else {
                        Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                            .setData(android.net.Uri.fromParts("package", packageName, null))
                    }
                    try {
                        startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                        result.success(true)
                    } catch (e: ActivityNotFoundException) {
                        result.success(false)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}
