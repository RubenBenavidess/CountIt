package ec.countit.app

import android.content.ActivityNotFoundException
import android.content.Intent
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
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
    }
}
