package com.smartring.smart_ring

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    companion object {
        private const val BLE_CHANNEL = "com.smartring.smart_ring/ble_foreground_service"
        private const val UPDATER_CHANNEL = "com.smartring.smart_ring/app_updater"
        private const val REQ_POST_NOTIFICATIONS = 1001
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            BLE_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "startService" -> {
                    requestNotificationPermissionIfNeeded()
                    val title = call.argument<String>("title") ?: "Spike · Ring Connected"
                    val text = call.argument<String>("text")
                        ?: "Streaming heart rate & stress telemetry"
                    val intent = Intent(this, BleForegroundService::class.java).apply {
                        action = BleForegroundService.ACTION_START
                        putExtra(BleForegroundService.EXTRA_TITLE, title)
                        putExtra(BleForegroundService.EXTRA_TEXT, text)
                    }
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        startForegroundService(intent)
                    } else {
                        startService(intent)
                    }
                    result.success(null)
                }

                "updateNotification" -> {
                    if (BleForegroundService.isRunning) {
                        val title = call.argument<String>("title") ?: "Spike · Ring Connected"
                        val text = call.argument<String>("text")
                            ?: "Streaming heart rate & stress telemetry"
                        val intent = Intent(this, BleForegroundService::class.java).apply {
                            action = BleForegroundService.ACTION_UPDATE
                            putExtra(BleForegroundService.EXTRA_TITLE, title)
                            putExtra(BleForegroundService.EXTRA_TEXT, text)
                        }
                        startService(intent)
                    }
                    result.success(null)
                }

                "stopService" -> {
                    val intent = Intent(this, BleForegroundService::class.java).apply {
                        action = BleForegroundService.ACTION_STOP
                    }
                    if (BleForegroundService.isRunning) {
                        startService(intent)
                    } else {
                        stopService(Intent(this, BleForegroundService::class.java))
                    }
                    result.success(null)
                }

                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            UPDATER_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getAppVersion" -> {
                    try {
                        val packageInfo = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                            packageManager.getPackageInfo(
                                packageName,
                                PackageManager.PackageInfoFlags.of(0),
                            )
                        } else {
                            @Suppress("DEPRECATION")
                            packageManager.getPackageInfo(packageName, 0)
                        }
                        val versionCode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                            packageInfo.longVersionCode
                        } else {
                            @Suppress("DEPRECATION")
                            packageInfo.versionCode.toLong()
                        }
                        result.success(
                            mapOf(
                                "versionName" to (packageInfo.versionName ?: "1.0.0"),
                                "versionCode" to versionCode,
                            ),
                        )
                    } catch (e: Exception) {
                        result.error("VERSION_ERROR", e.message, null)
                    }
                }

                "getUpdateCacheDir" -> {
                    try {
                        val dir = File(cacheDir, "updates")
                        if (!dir.exists()) {
                            dir.mkdirs()
                        }
                        result.success(dir.absolutePath)
                    } catch (e: Exception) {
                        result.error("CACHE_DIR_ERROR", e.message, null)
                    }
                }

                "canRequestPackageInstalls" -> {
                    val canInstall = Build.VERSION.SDK_INT < Build.VERSION_CODES.O ||
                        packageManager.canRequestPackageInstalls()
                    result.success(canInstall)
                }

                "openInstallPermissionSettings" -> {
                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            val intent = Intent(
                                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                Uri.parse("package:$packageName"),
                            ).apply {
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            startActivity(intent)
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SETTINGS_ERROR", e.message, null)
                    }
                }

                "installApk" -> {
                    val apkPath = call.argument<String>("path")
                    if (apkPath.isNullOrBlank()) {
                        result.error("INVALID_ARG", "Missing APK path", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val apkFile = File(apkPath)
                        if (!apkFile.exists() || apkFile.length() == 0L) {
                            result.error("FILE_NOT_FOUND", "APK file not found at $apkPath", null)
                            return@setMethodCallHandler
                        }
                        val uri = FileProvider.getUriForFile(
                            this,
                            "$packageName.fileprovider",
                            apkFile,
                        )
                        val intent = Intent(Intent.ACTION_VIEW).apply {
                            setDataAndType(uri, "application/vnd.android.package-archive")
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("INSTALL_ERROR", e.message, null)
                    }
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun requestNotificationPermissionIfNeeded() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
                PackageManager.PERMISSION_GRANTED
            ) {
                requestPermissions(
                    arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                    REQ_POST_NOTIFICATIONS,
                )
            }
        }
    }
}
