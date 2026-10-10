from pathlib import Path
import re

manifest = Path("android/app/src/main/AndroidManifest.xml")
manifest_text = manifest.read_text(encoding="utf-8")

# Android 8+ requires explicit opt-in for installing packages from this app.
if "android.permission.REQUEST_INSTALL_PACKAGES" not in manifest_text:
    marker = "<application"
    if marker not in manifest_text:
        raise SystemExit("Could not find <application> in AndroidManifest.xml")
    manifest_text = manifest_text.replace(
        marker,
        '    <uses-permission android:name="android.permission.REQUEST_INSTALL_PACKAGES" />\n    ' + marker,
        1,
    )

# The package installer broadcasts the OS confirmation action to this receiver.
# Register it independently of the FCM notification channel's configured name.
receiver = '<receiver android:name=".MainActivity$InstallStatusReceiver" android:exported="false" />'
if "MainActivity$InstallStatusReceiver" not in manifest_text:
    if "</application>" not in manifest_text:
        raise SystemExit("Could not find </application> in AndroidManifest.xml")
    manifest_text = manifest_text.replace("</application>", "        " + receiver + "\n    </application>", 1)
manifest.write_text(manifest_text, encoding="utf-8")

main_candidates = [
    Path("android/app/src/main/kotlin/com/allways/delivery/MainActivity.kt"),
    Path("android/app/src/main/kotlin/com/allways/carrier/MainActivity.kt"),
]
main = next((p for p in main_candidates if p.exists()), None)
if main is None:
    raise SystemExit("Could not find the generated ALLways MainActivity.kt")

kotlin = main.read_text(encoding="utf-8")
package_match = re.search(r"^package\s+([\w.]+)\s*$", kotlin, re.MULTILINE)
if not package_match:
    raise SystemExit("Could not identify the Kotlin package declaration")
package_name = package_match.group(1)
if package_name.endswith(".delivery"):
    updater_channel = "com.allways.delivery/apk_installer"
    install_action = "com.allways.delivery.PACKAGE_INSTALL_STATUS"
elif package_name.endswith(".carrier"):
    updater_channel = "com.allways.carrier/apk_installer"
    install_action = "com.allways.carrier.PACKAGE_INSTALL_STATUS"
else:
    raise SystemExit("Unsupported ALLways updater package: " + package_name)

required_imports = [
    "import android.app.PendingIntent",
    "import android.content.BroadcastReceiver",
    "import android.content.Intent",
    "import android.content.pm.PackageInstaller",
    "import android.net.Uri",
    "import android.os.Build",
    "import android.provider.Settings",
    "import java.io.File",
    "import java.io.FileInputStream",
]
missing_imports = [item for item in required_imports if item not in kotlin]
if missing_imports:
    kotlin = kotlin.replace(
        package_match.group(0),
        package_match.group(0) + "\n" + "\n".join(missing_imports),
        1,
    )

class_marker = "class MainActivity : FlutterActivity() {"
if class_marker not in kotlin:
    raise SystemExit("Could not find MainActivity class declaration")
if "private val updaterChannel" not in kotlin:
    kotlin = kotlin.replace(
        class_marker,
        class_marker
        + '\n    private val updaterChannel = "' + updater_channel + '"'
        + '\n    private val installAction = "' + install_action + '"',
        1,
    )

handler = """
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, updaterChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "installApk" -> installApk(call.argument<String>("path"), result)
                    "openInstallSettings" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:$packageName")))
                        } else {
                            startActivity(Intent(Settings.ACTION_SECURITY_SETTINGS))
                        }
                        result.success("opened")
                    }
                    else -> result.notImplemented()
                }
            }
"""
configure_marker = "super.configureFlutterEngine(flutterEngine)"
if "MethodChannel(flutterEngine.dartExecutor.binaryMessenger, updaterChannel)" not in kotlin:
    if configure_marker not in kotlin:
        raise SystemExit("Could not find configureFlutterEngine insertion point")
    kotlin = kotlin.replace(configure_marker, configure_marker + handler, 1)

install_method = """
    private fun installApk(path: String?, result: MethodChannel.Result) {
        if (path.isNullOrBlank()) {
            result.error("NO_APK", "APK path is missing", null)
            return
        }
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && !packageManager.canRequestPackageInstalls()) {
                startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:$packageName")))
                result.success("permission_required")
                return
            }
            val apk = File(path)
            if (!apk.exists() || apk.length() <= 0L) {
                result.error("NO_APK", "Downloaded APK is missing", null)
                return
            }
            val params = PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL)
            params.setAppPackageName(packageName)
            val sessionId = packageManager.packageInstaller.createSession(params)
            val session = packageManager.packageInstaller.openSession(sessionId)
            try {
                session.openWrite("package", 0, apk.length()).use { output ->
                    FileInputStream(apk).use { input -> input.copyTo(output, 1024 * 1024) }
                    session.fsync(output)
                }
                val callbackIntent = Intent(this, InstallStatusReceiver::class.java).apply {
                    action = installAction
                    putExtra("sessionId", sessionId)
                }
                val flags = PendingIntent.FLAG_UPDATE_CURRENT or
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) PendingIntent.FLAG_MUTABLE else 0
                val callback = PendingIntent.getBroadcast(this, sessionId, callbackIntent, flags)
                session.commit(callback.intentSender)
                result.success("started")
            } finally {
                session.close()
            }
        } catch (error: Exception) {
            result.error("INSTALL_FAILED", error.message ?: "Package installation failed", null)
        }
    }
"""
if "private fun installApk(" not in kotlin:
    final_brace = kotlin.rfind("}")
    if final_brace < 0:
        raise SystemExit("Could not find closing brace for MainActivity")
    kotlin = kotlin[:final_brace] + install_method + "\n" + kotlin[final_brace:]

receiver_class = """
    class InstallStatusReceiver : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            if (intent.getIntExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE) ==
                PackageInstaller.STATUS_PENDING_USER_ACTION) {
                val confirmation = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    intent.getParcelableExtra(Intent.EXTRA_INTENT, Intent::class.java)
                } else {
                    @Suppress("DEPRECATION")
                    intent.getParcelableExtra(Intent.EXTRA_INTENT)
                }
                confirmation?.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                if (confirmation != null) context.startActivity(confirmation)
            }
        }
    }
"""
if "class InstallStatusReceiver" not in kotlin:
    final_brace = kotlin.rfind("}")
    if final_brace < 0:
        raise SystemExit("Could not find closing brace for MainActivity")
    kotlin = kotlin[:final_brace] + receiver_class + "\n" + kotlin[final_brace:]

main.write_text(kotlin, encoding="utf-8")
print("Configured native ALLways APK updater in " + str(main))
