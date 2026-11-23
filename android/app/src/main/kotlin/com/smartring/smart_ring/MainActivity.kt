package com.smartring.smart_ring

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "com.smartring.smart_ring/ble_foreground_service"
        private const val REQ_POST_NOTIFICATIONS = 1001
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL,
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
