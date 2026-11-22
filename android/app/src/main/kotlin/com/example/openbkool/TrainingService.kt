package com.example.openbkool

import android.Manifest
import android.app.ActivityManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.drawable.Icon
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.os.SystemClock
import io.flutter.plugin.common.MethodChannel

/** Process-local owner. Android must never recreate a stopped workout from an Intent. */
class TrainingService : Service() {
    private var wakeLock: PowerManager.WakeLock? = null
    private var stopAction: PendingIntent? = null
    private var stopToken: String? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == STOP) {
            val token = intent.getStringExtra(TOKEN)
            if (token != null && token == stopToken) {
                val decision = recordLifecycle("notification_stop", backgroundAccess(this), "notification_stop")
                if (pending?.token == token) {
                    cancelPending("notification_stop")
                    releaseForeground()
                } else {
                    controller(applicationContext).stop(reason = "notification_stop", lifecycle = decision)
                }
            } else if (foreground !== this && pending == null) {
                stopSelf(startId)
            }
            return START_NOT_STICKY
        }
        val request = pending
        if (request == null || request.token != intent?.getStringExtra(TOKEN)) {
            if (pending == null && foreground !== this) stopSelf(startId)
            return START_NOT_STICKY
        }
        stopToken = request.token
        serviceStarted = true
        recordLifecycle("service_started")
        try {
            val access = backgroundAccess(this)
            check(access.blockReason == null) { access.blockReason.orEmpty() }
            startForeground(NOTIFICATION_ID, notification(request.token))
            recordLifecycle("promotion_requested", access)
            verifyPromotion(request, SystemClock.elapsedRealtime() + 2000L)
        } catch (error: RuntimeException) {
            failPromotion(request, error.message ?: error.javaClass.simpleName)
        }
        return START_NOT_STICKY
    }

    private fun verifyPromotion(request: StartRequest, deadline: Long) {
        if (stopToken != request.token) return
        if (pending !== request) {
            releaseForeground()
            return
        }
        try {
            val access = backgroundAccess(this)
            check(access.blockReason == null) { access.blockReason.orEmpty() }
            if (!isForegroundService(this) || !access.notificationPosted) {
                if (SystemClock.elapsedRealtime() >= deadline) {
                    failPromotion(request, "Android no confirmó el servicio y su notificación")
                } else {
                    main.postDelayed({ verifyPromotion(request, deadline) }, 100L)
                }
                return
            }
            servicePromoted = true
            recordLifecycle("service_promoted", access)
            wakeLock = getSystemService(PowerManager::class.java)
                .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "OpenBkool:Training")
                .apply { acquire() }
            foreground = this
            clearPending()
            recordLifecycle("background_authorized", access)
            val ant = controller(applicationContext)
            ant.start(request.mode, request.result, request.device)
            if (!ant.hasActiveSession()) releaseForeground()
        } catch (error: RuntimeException) {
            failPromotion(request, error.message ?: error.javaClass.simpleName)
        }
    }

    private fun failPromotion(request: StartRequest, detail: String) {
        clearPending()
        recordLifecycle("promotion_failed", backgroundAccess(this), detail)
        releaseForeground()
        request.result.error("training_service_failed", detail, backgroundSnapshot)
    }

    private fun notification(token: String): Notification {
        val open = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val stop = PendingIntent.getService(this, 0, Intent(this, TrainingService::class.java).setAction(STOP)
            .putExtra(TOKEN, token), PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_CANCEL_CURRENT)
        stopAction = stop
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, CHANNEL)
            else @Suppress("DEPRECATION") Notification.Builder(this)
        if (Build.VERSION.SDK_INT >= 31) builder.setForegroundServiceBehavior(Notification.FOREGROUND_SERVICE_IMMEDIATE)
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
        serviceStarted = false
        servicePromoted = false
        recordLifecycle("service_released")
        releaseResources()
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    override fun onDestroy() {
        if (foreground === this) {
            val beforeDeath = recordLifecycle("service_destroyed", backgroundAccess(this), "training_service_destroyed")
            foreground = null
            serviceStarted = false
            servicePromoted = false
            recordLifecycle("background_revoked")
            controller(applicationContext).stop(reason = "training_service_destroyed", lifecycle = beforeDeath)
        } else if (stopToken != null && pending?.token == stopToken) {
            cancelPending("training_service_destroyed")
            serviceStarted = false
            servicePromoted = false
            recordLifecycle("service_destroyed")
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
        private var serviceStarted = false
        private var servicePromoted = false
        private var access: TrainingBackgroundAccess? = null
        private var lifecycleEvents = emptyList<Map<String, Any?>>()
        @Volatile private var backgroundSnapshot = emptyMap<String, Any?>()

        private fun recordLifecycle(event: String, checkedAccess: TrainingBackgroundAccess? = access,
            decision: String? = null): Map<String, Any?> {
            access = checkedAccess
            val authorized = checkedAccess?.allowsContinuation(serviceStarted, servicePromoted, foreground != null) == true
            val state = mapOf(
                "serviceStarted" to serviceStarted,
                "servicePromoted" to servicePromoted,
                "backgroundAuthorized" to authorized,
                "appInBackground" to !visible,
                "backgroundBlockReason" to (checkedAccess?.blockReason ?: if (authorized) null else "service_inactive"),
                "backgroundPermissions" to checkedAccess?.toMap(),
            )
            val entry = state + mapOf("event" to event, "decision" to decision,
                "timestampUtc" to java.text.SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", java.util.Locale.US).apply {
                    timeZone = java.util.TimeZone.getTimeZone("UTC")
                }.format(java.util.Date()), "monotonicMs" to SystemClock.elapsedRealtime())
            android.util.Log.i("OpenBkoolTraining", entry.toString())
            lifecycleEvents = lifecycleEvents.takeLast(63) + entry
            backgroundSnapshot = state + mapOf("backgroundLifecycle" to lifecycleEvents)
            return entry
        }

        fun recordLegacyPause() {
            session?.recordLifecycle(recordLifecycle("legacy_flutter_pause_ignored"))
        }
        private var foreground: TrainingService? = null
        private var session: AntTrainerSearch? = null
        private var visible = false
        private val main = Handler(Looper.getMainLooper())

        fun controller(context: Context): AntTrainerSearch = session ?: AntTrainerSearch(
            context.applicationContext, training = true,
            backgroundStatus = { backgroundSnapshot },
            onFinished = {
                foreground?.releaseForeground()
                session?.emitSnapshot()
            },
        ).also { session = it }

        fun setVisible(context: Context, visibleNow: Boolean) {
            visible = visibleNow
            val checkedAccess = backgroundAccess(context)
            val hasWorkout = pending != null || session?.hasActiveSession() == true
            if (foreground != null && servicePromoted) servicePromoted = isForegroundService(context)
            val mustStop = !visible && hasWorkout &&
                !checkedAccess.allowsContinuation(serviceStarted, servicePromoted, foreground != null)
            val decision = recordLifecycle(
                if (visible) "activity_started" else "activity_stopped",
                checkedAccess,
                if (mustStop) "app_background" else if (!visible && hasWorkout) "continue_training" else null,
            )
            if (mustStop) {
                cancelPending("app_background")
                session?.stop(reason = "app_background", lifecycle = decision)
            } else if (hasWorkout) {
                session?.recordLifecycle(decision)
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
            recordLifecycle("service_start_cancelled", decision = reason)
            request.result.error("training_start_cancelled", reason, backgroundSnapshot)
        }

        fun start(context: Context, mode: String, device: Map<String, Any?>?, result: MethodChannel.Result) {
            val ant = controller(context)
            if (!visible || pending != null || serviceStarted || foreground != null || ant.hasActiveSession()) {
                result.error("training_unavailable", "Abre la app y espera el cierre de la sesión anterior", null)
                return
            }
            val manager = context.getSystemService(NotificationManager::class.java)
            if (Build.VERSION.SDK_INT >= 26) {
                manager.createNotificationChannel(NotificationChannel(CHANNEL, "Entrenamientos ANT", NotificationManager.IMPORTANCE_LOW))
            }
            lifecycleEvents = emptyList()
            val checkedAccess = backgroundAccess(context)
            recordLifecycle("training_start_requested", checkedAccess)
            if (checkedAccess.blockReason != null) {
                recordLifecycle("foreground_only", checkedAccess, checkedAccess.blockReason)
                ant.start(mode, result, device)
                return
            }
            val request = StartRequest(java.util.UUID.randomUUID().toString(), mode, device, result)
            pending = request
            recordLifecycle("service_start_requested")
            val intent = Intent(context, TrainingService::class.java).putExtra(TOKEN, request.token)
            try {
                val component = if (Build.VERSION.SDK_INT >= 26) context.startForegroundService(intent)
                    else context.startService(intent)
                checkNotNull(component) { "Android no inició el servicio de entrenamiento" }
                timeout = Runnable { cancelPending("training_service_timeout") }.also { main.postDelayed(it, 5000) }
            } catch (error: RuntimeException) {
                clearPending()
                recordLifecycle("service_start_failed", decision = error.javaClass.simpleName)
                result.error("training_service_failed", error.message, backgroundSnapshot)
            }
        }
        @Suppress("DEPRECATION") // On Android 8+ this API returns only the calling app's services.
        private fun isForegroundService(context: Context): Boolean {
            val component = ComponentName(context, TrainingService::class.java)
            return context.getSystemService(ActivityManager::class.java)
                .getRunningServices(Int.MAX_VALUE)
                .any { it.service == component && it.foreground }
        }

        private fun backgroundAccess(context: Context): TrainingBackgroundAccess {
            val manager = context.getSystemService(NotificationManager::class.java)
            val channel = if (Build.VERSION.SDK_INT >= 26) manager.getNotificationChannel(CHANNEL) else null
            val granted = { permission: String ->
                context.checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED
            }
            return TrainingBackgroundAccess(
                sdk = Build.VERSION.SDK_INT,
                notificationPermission = Build.VERSION.SDK_INT < 33 || granted(Manifest.permission.POST_NOTIFICATIONS),
                notificationsEnabled = manager.areNotificationsEnabled(),
                channelEnabled = Build.VERSION.SDK_INT < 26 || channel?.importance?.let { it > NotificationManager.IMPORTANCE_NONE } == true,
                bluetoothConnect = Build.VERSION.SDK_INT >= 31 && granted(Manifest.permission.BLUETOOTH_CONNECT),
                bluetoothScan = Build.VERSION.SDK_INT >= 31 && granted(Manifest.permission.BLUETOOTH_SCAN),
                notificationPosted = manager.activeNotifications.any { it.id == NOTIFICATION_ID },
            )
        }
    }
}
