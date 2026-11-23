package com.smartring.smart_ring

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder

/**
 * Foreground service keeping the Colmi R02 BLE connection and real-time heart
 * rate notifications alive while the app is backgrounded on Android.
 */
class BleForegroundService : Service() {

    companion object {
        const val CHANNEL_ID = "spike_ble_monitor"
        const val CHANNEL_NAME = "Smart Ring Connection"
        const val NOTIFICATION_ID = 4201

        const val ACTION_START = "com.smartring.smart_ring.action.START_BLE_SERVICE"
        const val ACTION_UPDATE = "com.smartring.smart_ring.action.UPDATE_BLE_SERVICE"
        const val ACTION_STOP = "com.smartring.smart_ring.action.STOP_BLE_SERVICE"

        const val EXTRA_TITLE = "title"
        const val EXTRA_TEXT = "text"

        @Volatile
        var isRunning: Boolean = false
            private set
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                isRunning = false
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                    stopForeground(STOP_FOREGROUND_REMOVE)
                } else {
                    @Suppress("DEPRECATION")
                    stopForeground(true)
                }
                stopSelf()
                return START_NOT_STICKY
            }

            ACTION_UPDATE -> {
                if (isRunning) {
                    val title = intent.getStringExtra(EXTRA_TITLE) ?: "Spike · Ring Connected"
                    val text = intent.getStringExtra(EXTRA_TEXT)
                        ?: "Streaming heart rate & stress telemetry"
                    val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                    manager.notify(NOTIFICATION_ID, buildNotification(title, text))
                }
                return START_STICKY
            }

            else -> {
                val title = intent?.getStringExtra(EXTRA_TITLE) ?: "Spike · Ring Connected"
                val text = intent?.getStringExtra(EXTRA_TEXT)
                    ?: "Streaming heart rate & stress telemetry"
                val notification = buildNotification(title, text)
                isRunning = true
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    startForeground(
                        NOTIFICATION_ID,
                        notification,
                        ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE,
                    )
                } else {
                    startForeground(NOTIFICATION_ID, notification)
                }
                return START_STICKY
            }
        }
    }

    override fun onDestroy() {
        isRunning = false
        super.onDestroy()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                CHANNEL_NAME,
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "Keeps the Colmi R02 smart ring connected in the background"
                setShowBadge(false)
            }
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(title: String, text: String): Notification {
        val launchIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pendingFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
        val pendingIntent = PendingIntent.getActivity(this, 0, launchIntent, pendingFlags)

        val smallIcon = if (applicationInfo.icon != 0) {
            applicationInfo.icon
        } else {
            android.R.drawable.stat_sys_data_bluetooth
        }

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }

        return builder
            .setContentTitle(title)
            .setContentText(text)
            .setSmallIcon(smallIcon)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .build()
    }
}
