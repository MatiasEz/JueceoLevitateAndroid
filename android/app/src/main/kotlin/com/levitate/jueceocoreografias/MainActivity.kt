package com.levitate.jueceocoreografias

import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ActivityInfo
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val updateChannel = "com.levitate.jueceocoreografias/updater"

    override fun onCreate(savedInstanceState: Bundle?) {
        requestedOrientation = if (resources.configuration.smallestScreenWidthDp >= 600) {
            ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE
        } else {
            ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
        }

        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, updateChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getVersionCode" -> result.success(currentVersionCode())
                    "canInstallPackages" -> result.success(canInstallPackages())
                    "openInstallSettings" -> {
                        openInstallSettings()
                        result.success(null)
                    }
                    "installApk" -> {
                        val path = call.argument<String>("path")
                        if (path.isNullOrBlank()) {
                            result.error("MISSING_APK_PATH", "Falta la ruta del APK.", null)
                            return@setMethodCallHandler
                        }
                        installApk(File(path), result)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun currentVersionCode(): Long {
        val packageInfo = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            packageManager.getPackageInfo(
                packageName,
                PackageManager.PackageInfoFlags.of(0)
            )
        } else {
            @Suppress("DEPRECATION")
            packageManager.getPackageInfo(packageName, 0)
        }

        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            packageInfo.longVersionCode
        } else {
            @Suppress("DEPRECATION")
            packageInfo.versionCode.toLong()
        }
    }

    private fun canInstallPackages(): Boolean {
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.O ||
            packageManager.canRequestPackageInstalls()
    }

    private fun openInstallSettings() {
        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Intent(
                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                Uri.parse("package:$packageName")
            )
        } else {
            Intent(Settings.ACTION_SECURITY_SETTINGS)
        }
        startActivity(intent)
    }

    private fun installApk(apkFile: File, result: MethodChannel.Result) {
        if (!apkFile.exists()) {
            result.error("APK_NOT_FOUND", "No se encontro el APK descargado.", null)
            return
        }
        if (!canInstallPackages()) {
            result.error(
                "INSTALL_PERMISSION_REQUIRED",
                "Falta habilitar la instalacion desde esta app.",
                null
            )
            return
        }

        val uri = FileProvider.getUriForFile(
            this,
            "$packageName.fileprovider",
            apkFile
        )
        val intent = Intent(Intent.ACTION_INSTALL_PACKAGE).apply {
            data = uri
            flags = Intent.FLAG_GRANT_READ_URI_PERMISSION
            putExtra(Intent.EXTRA_RETURN_RESULT, true)
        }
        startActivity(intent)
        result.success(null)
    }
}
