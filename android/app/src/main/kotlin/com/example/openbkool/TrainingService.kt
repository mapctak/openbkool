package com.example.openbkool

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.drawable.Icon
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import io.flutter.plugin.common.MethodChannel

/** Process-local owner. Android must never recreate a stopped workout from an Intent. */
class TrainingService : Service() {
    private var wakeLock: PowerManager.WakeLock? = null
    private var stopAction: PendingIntent? = null
    private var stopToken: String? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == STOP) {
            if (intent.getStringExtra(TOKEN) == stopToken && stopToken != null) {
                controller(applicationContext).stop(reason = "notification_stop")
            } else if (foreground !== this) {
                stopSelf(startId)
            }
            return START_NOT_STICKY
        }
        val request = pending
        if (request == null || request.token != intent?.getStringExtra(TOKEN)) {
            // A canceled launch can still be delivered. Do not stop a newer launch.
            if (pending == null && foreground !== this) stopSelf(startId)
            return START_NOT_STICKY
        }
        clearPending()
        try {
            startForeground(NOTIFICATION_ID, notification(request.token))
            wakeLock = getSystemService(PowerManager::class.java)
                .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "OpenBkool:Training")
                .apply { acquire() }
            foreground = this
            stopToken = request.token
            controller(applicationContext).start(request.mode, request.result, request.device)
            if (!controller(applicationContext).hasActiveSession()) releaseForeground()
        } catch (error: RuntimeException) {
            releaseForeground()
            request.result.error("training_service_failed", error.message, null)
        }
        return START_NOT_STICKY
    }

    private fun notification(token: String): Notification {
        val open = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val stop = PendingIntent.getService(this, 0, Intent(this, TrainingService::class.java).setAction(STOP)
            .putExtra(TOKEN, token), PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_CANCEL_CURRENT)
        stopAction = stop
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, CHANNEL)
            else @Suppress("DEPRECATION") Notification.Builder(this)
        return builder.setSmallIcon(android.R.drawable.ic_media_play)
            .setContentTitle("Entrenamiento OpenBkool")
            .setContentText("Sesión ANT activa")
            .setContentIntent(open)
            .setOngoing(true)
            .setDeleteIntent(stop)
            .addAction(Notification.Action.Builder(Icon.createWithResource(this, android.R.drawable.ic_media_pause), "DETENER", stop).build())
            .build()
    }

    private fun releaseResources() {
        wakeLock?.let { if (it.isHeld) it.release() }
        wakeLock = null
        stopAction?.cancel()
        stopAction = null
        stopToken = null
    }

    private fun releaseForeground() {
        if (foreground === this) foreground = null
        releaseResources()
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    override fun onDestroy() {
        if (foreground === this) {
            foreground = null
            controller(applicationContext).stop(reason = "training_service_destroyed")
        }
        releaseResources()
        super.onDestroy()
    }

    companion object {
        private const val CHANNEL = "openbkool_training"
        private const val NOTIFICATION_ID = 4819
        private const val STOP = "com.example.openbkool.STOP_TRAINING"
        private const val TOKEN = "training_token"

        private data class StartRequest(val token: String, val mode: String,
            val device: Map<String, Any?>?, val result: MethodChannel.Result)
        private var pending: StartRequest? = null
        private var timeout: Runnable? = null
        val backgroundAuthorized: Boolean get() = foreground != null
        private var foreground: TrainingService? = null
        private var session: AntTrainerSearch? = null
        private var visible = false
        private val main = Handler(Looper.getMainLooper())

        fun controller(context: Context): AntTrainerSearch = session ?: AntTrainerSearch(
            context.applicationContext, training = true,
            backgroundStatus = {
                mapOf("backgroundAuthorized" to (foreground != null),
                    "appInBackground" to !visible)
            },
            onFinished = {
                foreground?.releaseForeground()
                session?.emitSnapshot()
            },
        ).also { session = it }

        fun setVisible(visibleNow: Boolean) {
            visible = visibleNow
            if (!visible && foreground == null) {
                cancelPending("app_background")
                session?.stop(reason = "app_background")
            }
            session?.emitSnapshot()
        }

        private fun clearPending() {
            pending = null
            timeout?.let(main::removeCallbacks)
            timeout = null
        }

        fun cancelPending(reason: String) {
            val request = pending ?: return
            clearPending()
            request.result.error("training_start_cancelled", reason, null)
        }

        fun start(context: Context, mode: String, device: Map<String, Any?>?, result: MethodChannel.Result) {
            val ant = controller(context)
            if (!visible || pending != null || foreground != null || ant.hasActiveSession()) {
                result.error("training_unavailable", "Abre la app y espera el cierre de la sesión anterior", null)
                return
            }
            val manager = context.getSystemService(NotificationManager::class.java)
            if (Build.VERSION.SDK_INT >= 26) {
                manager.createNotificationChannel(NotificationChannel(CHANNEL, "Entrenamientos ANT", NotificationManager.IMPORTANCE_LOW))
            }
            val channelEnabled = Build.VERSION.SDK_INT < 26 ||
                manager.getNotificationChannel(CHANNEL)?.importance != NotificationManager.IMPORTANCE_NONE
            val canShowStop = manager.areNotificationsEnabled() && channelEnabled &&
                (Build.VERSION.SDK_INT < 33 || context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED)
            val connectedDevicePermission = Build.VERSION.SDK_INT < 31 ||
                context.checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) == PackageManager.PERMISSION_GRANTED ||
                context.checkSelfPermission(Manifest.permission.BLUETOOTH_SCAN) == PackageManager.PERMISSION_GRANTED
            if (!canShowStop || !connectedDevicePermission) {
                // Foreground-only fallback when Android hides the stop action.
                ant.start(mode, result, device)
                return
            }
            val request = StartRequest(java.util.UUID.randomUUID().toString(), mode, device, result)
            pending = request
            val intent = Intent(context, TrainingService::class.java).putExtra(TOKEN, request.token)
            try {
                if (Build.VERSION.SDK_INT >= 26) context.startForegroundService(intent)
                else context.startService(intent)
                timeout = Runnable { cancelPending("training_service_timeout") }.also { main.postDelayed(it, 5000) }
            } catch (error: RuntimeException) {
                clearPending()
                result.error("training_service_failed", error.message, null)
            }
        }
    }
}
