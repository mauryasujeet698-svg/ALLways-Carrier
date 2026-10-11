#!/usr/bin/env python3
"""Install ALLways' native APK installer and local-notification bridge after flutter create."""
from __future__ import annotations
import argparse
import re
from pathlib import Path

def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--package", required=True)
    parser.add_argument("--channel", required=True)
    parser.add_argument("--label", required=True)
    args = parser.parse_args()

    source_root = Path("android/app/src/main/kotlin")
    candidates = list(source_root.rglob("MainActivity.kt")) if source_root.exists() else []
    kotlin_package = args.package
    if candidates:
        existing = candidates[0].read_text(encoding="utf-8")
        match = re.search(r"(?m)^\s*package\s+([A-Za-z0-9_.]+)\s*$", existing)
        if match:
            kotlin_package = match.group(1)
        main_file = candidates[0]
    else:
        main_file = source_root / Path(*args.package.split(".")) / "MainActivity.kt"
        main_file.parent.mkdir(parents=True, exist_ok=True)

    action = args.package + ".PACKAGE_INSTALL_STATUS"
    kotlin = r'''package __PACKAGE__

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.app.NotificationCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream

class MainActivity : FlutterActivity() {
    companion object {
        const val INSTALL_ACTION = "__ACTION__"
        const val UPDATE_CHANNEL_ID = "allways_updates"
    }

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        createUpdateChannel()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "__CHANNEL__")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "installApk" -> installApk(call.argument<String>("path"), result)
                    "openInstallSettings" -> openInstallSettings(result)
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "allways_notifications")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "showNotification" -> {
                        showLocalNotification(
                            call.argument<String>("title") ?: "ALLways",
                            call.argument<String>("body") ?: "You have a new ALLways update."
                        )
                        result.success("shown")
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun openInstallSettings(result: MethodChannel.Result) {
        try {
            val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:$packageName"))
            } else {
                Intent(Settings.ACTION_SECURITY_SETTINGS)
            }
            startActivity(intent)
            result.success("opened")
        } catch (e: Exception) {
            result.error("INSTALL_SETTINGS_FAILED", e.message ?: "Could not open installation settings", null)
        }
    }

    private fun installApk(path: String?, result: MethodChannel.Result) {
        if (path.isNullOrBlank()) {
            result.error("NO_APK", "APK path is missing", null)
            return
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && !packageManager.canRequestPackageInstalls()) {
            result.success("permission_required")
            return
        }
        val apk = File(path)
        if (!apk.exists() || !apk.isFile || !apk.canRead() || apk.length() <= 0L) {
            result.error("NO_APK", "Downloaded APK is missing or unreadable", null)
            return
        }

        var session: PackageInstaller.Session? = null
        try {
            val params = PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL)
            params.setAppPackageName(packageName)
            params.setSize(apk.length())
            val installer = packageManager.packageInstaller
            val sessionId = installer.createSession(params)
            session = installer.openSession(sessionId)
            session.openWrite("package", 0, apk.length()).use { output ->
                FileInputStream(apk).use { input -> input.copyTo(output, 1024 * 1024) }
                session.fsync(output)
            }
            val callback = Intent(this, InstallStatusReceiver::class.java)
                .setAction(INSTALL_ACTION)
                .putExtra("sessionId", sessionId)
            val flags = PendingIntent.FLAG_UPDATE_CURRENT or
                (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) PendingIntent.FLAG_MUTABLE else 0)
            val pending = PendingIntent.getBroadcast(this, sessionId, callback, flags)
            session.commit(pending.intentSender)
            result.success("started")
        } catch (e: Exception) {
            try { session?.abandon() } catch (_: Exception) {}
            result.error("INSTALL_FAILED", e.message ?: "Package installation failed", null)
        } finally {
            try { session?.close() } catch (_: Exception) {}
        }
    }

    private fun createUpdateChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(
                NotificationChannel(UPDATE_CHANNEL_ID, "ALLways Updates", NotificationManager.IMPORTANCE_HIGH).apply {
                    description = "ALLways delivery, ride and app-update notifications"
                    enableVibration(true)
                }
            )
        }
    }

    private fun showLocalNotification(title: String, body: String) {
        createUpdateChannel()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            return
        }
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)?.apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pending = launchIntent?.let {
            PendingIntent.getActivity(
                this, (System.currentTimeMillis() and 0x7fffffff).toInt(), it,
                PendingIntent.FLAG_UPDATE_CURRENT or
                    (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0)
            )
        }
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, UPDATE_CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        builder.setSmallIcon(if (applicationInfo.icon != 0) applicationInfo.icon else android.R.drawable.ic_dialog_info)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(Notification.BigTextStyle().bigText(body))
            .setAutoCancel(true)
        if (pending != null) builder.setContentIntent(pending)
        (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
            .notify((System.currentTimeMillis() and 0x7fffffff).toInt(), builder.build())
    }

    class InstallStatusReceiver : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            if (intent.action != INSTALL_ACTION) return
            val status = intent.getIntExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE)
            if (status == PackageInstaller.STATUS_PENDING_USER_ACTION) {
                val confirmIntent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    intent.getParcelableExtra(Intent.EXTRA_INTENT, Intent::class.java)
                } else {
                    @Suppress("DEPRECATION")
                    intent.getParcelableExtra(Intent.EXTRA_INTENT) as? Intent
                }
                confirmIntent?.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                if (confirmIntent != null) context.startActivity(confirmIntent)
            } else if (status != PackageInstaller.STATUS_SUCCESS) {
                val message = intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE) ?: "Please retry the update."
                val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    manager.createNotificationChannel(
                        NotificationChannel(UPDATE_CHANNEL_ID, "ALLways Updates", NotificationManager.IMPORTANCE_HIGH)
                    )
                }
                val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    Notification.Builder(context, UPDATE_CHANNEL_ID)
                } else {
                    @Suppress("DEPRECATION")
                    Notification.Builder(context)
                }
                builder.setSmallIcon(if (context.applicationInfo.icon != 0) context.applicationInfo.icon else android.R.drawable.ic_dialog_info)
                    .setContentTitle("ALLways update could not be installed")
                    .setContentText(message)
                    .setAutoCancel(true)
                manager.notify(20261011, builder.build())
            }
        }
    }
}
'''
    kotlin = kotlin.replace("__PACKAGE__", kotlin_package).replace("__ACTION__", action).replace("__CHANNEL__", args.channel)
    main_file.write_text(kotlin, encoding="utf-8")

    manifest = Path("android/app/src/main/AndroidManifest.xml")
    if not manifest.exists():
        raise SystemExit("Flutter Android manifest was not generated")
    text = manifest.read_text(encoding="utf-8")
    for permission in ("android.permission.REQUEST_INSTALL_PACKAGES", "android.permission.POST_NOTIFICATIONS"):
        if permission not in text:
            match = re.search(r"<manifest\b[^>]*>", text)
            if not match:
                raise SystemExit("Could not find the opening manifest element")
            text = text[:match.end()] + f'\n    <uses-permission android:name="{permission}" />' + text[match.end():]
    receiver_name = ".MainActivity$InstallStatusReceiver"
    if receiver_name not in text:
        receiver = f'''
        <receiver android:name="{receiver_name}" android:exported="false">
            <intent-filter>
                <action android:name="{action}" />
            </intent-filter>
        </receiver>
'''
        text = text.replace("</application>", receiver + "    </application>")
    manifest.write_text(text, encoding="utf-8")
    print(f"Configured native update installer for {args.label} ({args.package})")

if __name__ == "__main__":
    main()
