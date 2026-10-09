from pathlib import Path

manifest = Path("android/app/src/main/AndroidManifest.xml")
text = manifest.read_text()
if "android.permission.REQUEST_INSTALL_PACKAGES" not in text:
    text = text.replace(
        '<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>',
        '<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>\n            <uses-permission android:name="android.permission.REQUEST_INSTALL_PACKAGES"/>'
    )
if 'MainActivity$InstallStatusReceiver' not in text:
    text = text.replace(
        '<meta-data android:name="com.google.firebase.messaging.default_notification_channel_id" android:value="allways_urgent_v2"/>',
        '<receiver android:name=".MainActivity$InstallStatusReceiver" android:exported="false"/>\n              <meta-data android:name="com.google.firebase.messaging.default_notification_channel_id" android:value="allways_urgent_v2"/>'
    )
manifest.write_text(text)

main = Path("android/app/src/main/kotlin/com/allways/carrier/MainActivity.kt")
main.write_text(r'''package com.allways.carrier

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import androidx.core.app.NotificationCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream

class MainActivity : FlutterActivity() {
    private val channelId = "allways_urgent_v2"
    private val updaterChannel = "com.allways.carrier/apk_installer"
    private val installAction = "com.allways.carrier.PACKAGE_INSTALL_STATUS"

    override fun onCreate(savedInstanceState: Bundle?) { super.onCreate(savedInstanceState); createChannel() }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "allways_notifications").setMethodCallHandler { call, result ->
            if (call.method == "showNotification") {
                showNotification(call.argument<String>("title") ?: "ALLways", call.argument<String>("body") ?: "")
                result.success(null)
            } else result.notImplemented()
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, updaterChannel).setMethodCallHandler { call, result ->
            when (call.method) {
                "installApk" -> installApk(call.argument<String>("path"), result)
                "openInstallSettings" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:$packageName")))
                    else startActivity(Intent(Settings.ACTION_SECURITY_SETTINGS))
                    result.success("opened")
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            getSystemService(NotificationManager::class.java).createNotificationChannel(
                NotificationChannel(channelId, "ALLways Urgent Alerts", NotificationManager.IMPORTANCE_HIGH).apply {
                    enableVibration(true)
                    vibrationPattern = longArrayOf(0, 450, 180, 450, 180, 700)
                }
            )
        }
    }

    private fun showNotification(title: String, body: String) {
        createChannel()
        val launch = packageManager.getLaunchIntentForPackage(packageName)?.apply { flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP }
        val pending = launch?.let {
            PendingIntent.getActivity(this, (System.currentTimeMillis() and 0x7fffffff).toInt(), it,
                PendingIntent.FLAG_UPDATE_CURRENT or if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0)
        }
        val n = NotificationCompat.Builder(this, channelId)
            .setSmallIcon(android.R.drawable.ic_dialog_alert)
            .setContentTitle(title).setContentText(body)
            .setPriority(NotificationCompat.PRIORITY_MAX).setAutoCancel(true).setContentIntent(pending).build()
        (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).notify((System.currentTimeMillis() and 0x7fffffff).toInt(), n)
    }

    private fun installApk(path: String?, result: MethodChannel.Result) {
        if (path.isNullOrBlank()) { result.error("NO_APK", "APK path is missing", null); return }
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && !packageManager.canRequestPackageInstalls()) {
                startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:$packageName")))
                result.success("permission_required"); return
            }
            val apk = File(path)
            if (!apk.exists() || apk.length() <= 0L) { result.error("NO_APK", "Downloaded APK is missing", null); return }
            val params = PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL)
            params.setAppPackageName(packageName)
            val id = packageManager.packageInstaller.createSession(params)
            val session = packageManager.packageInstaller.openSession(id)
            try {
                session.openWrite("package", 0, apk.length()).use { out ->
                    FileInputStream(apk).use { input -> input.copyTo(out, 1024 * 1024) }
                    session.fsync(out)
                }
                val intent = Intent(this, InstallStatusReceiver::class.java).apply { action = installAction; putExtra("sessionId", id) }
                val flags = PendingIntent.FLAG_UPDATE_CURRENT or if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) PendingIntent.FLAG_MUTABLE else 0
                session.commit(PendingIntent.getBroadcast(this, id, intent, flags).intentSender)
                result.success("started")
            } finally { session.close() }
        } catch (e: Exception) { result.error("INSTALL_FAILED", e.message ?: "Package installation failed", null) }
    }

    class InstallStatusReceiver : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            if (intent.getIntExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE) == PackageInstaller.STATUS_PENDING_USER_ACTION) {
                val confirm = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU)
                    intent.getParcelableExtra(Intent.EXTRA_INTENT, Intent::class.java)
                else { @Suppress("DEPRECATION") intent.getParcelableExtra(Intent.EXTRA_INTENT) }
                confirm?.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                if (confirm != null) context.startActivity(confirm)
            }
        }
    }
}
''')
