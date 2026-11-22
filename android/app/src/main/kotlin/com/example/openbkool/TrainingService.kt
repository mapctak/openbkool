package com.example.openbkool

import android.Manifest
import android.app.ActivityManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.graphics.drawable.Icon
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.os.SystemClock
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class TrainingService : Service() {
    private var token: String? = null
    private var ant: AntTrainerSearch? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private var stopAction: PendingIntent? = null
    private var receiverRegistered = false
    @Volatile private var ready = false
    @Volatile private var supervisionFailure: String? = null
    private var startedAtMs = 0L
    private var promotionRequestedAtMs = 0L
    private val verify = Runnable { verifyPromotion() }
    private var verifyUntil = 0L
    private val screenReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            ant?.screenChanged(intent.action == Intent.ACTION_SCREEN_OFF)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val requestedToken = intent?.data?.lastPathSegment
        if (intent?.action == STOP) {
            if (TrainingServicePolicy.acceptsStop(token, requestedToken)) stopTraining(null, "user_finish", "notification")
            else if (token == null && pending == null) stopSelf(startId)
            return START_NOT_STICKY
        }

        if (token != null) return START_NOT_STICKY
        val request = pending
        // A delayed start can arrive after cancellation. Fulfill Android's foreground
        // launch contract without creating an ANT controller for that intent.
        if (intent?.action != START || requestedToken == null) {
            stopSelf(startId)
            return START_NOT_STICKY
        }
        token = requestedToken
        startedAtMs = SystemClock.elapsedRealtime()
        current = this
        try {
            val notice = notification(requestedToken)
            if (Build.VERSION.SDK_INT >= 29) {
                startForeground(NOTIFICATION_ID, notice, ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE)
            } else {
                startForeground(NOTIFICATION_ID, notice)
            }
            promotionRequestedAtMs = SystemClock.elapsedRealtime()
            if (request == null || request.token != requestedToken) {
                stopSelf(startId)
            } else {
                android.util.Log.i(TAG, "service_started token=${request.token}")
                verifyUntil = SystemClock.elapsedRealtime() + 2500
                verifyPromotion()
            }
        } catch (error: RuntimeException) {
            failStart(request?.takeIf { it.token == requestedToken }, error.message ?: error.javaClass.simpleName)
        }
        return START_NOT_STICKY
    }

    private fun verifyPromotion() {
        val request = pending
        if (request == null || request.token != token) { stopSelf(); return }
        try {
            val prerequisites = permissionStatus(this)
            val blocker = TrainingServicePolicy.permissionBlock(prerequisites)
            if (blocker != null) { failStart(request, blocker); return }
            val foreground = isPromoted()
            val posted = notificationActive()
            when (TrainingServicePolicy.promotion(foreground, posted, SystemClock.elapsedRealtime() >= verifyUntil)) {
                Promotion.WAIT -> main.postDelayed(verify, 100)
                Promotion.FAILED -> failStart(request, "Android no confirmó el servicio y la notificación")
                Promotion.READY -> openTraining(request, prerequisites)
            }
        } catch (error: RuntimeException) {
            failStart(request, error.message ?: error.javaClass.simpleName)
        }
    }

    private fun openTraining(request: StartRequest, prerequisites: TrainingPermissions) {
        val power = getSystemService(PowerManager::class.java)
        wakeLock = power.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "$TAG:ANT").apply { acquire() }
        val filter = IntentFilter().apply { addAction(Intent.ACTION_SCREEN_OFF); addAction(Intent.ACTION_SCREEN_ON) }
        if (Build.VERSION.SDK_INT >= 33) registerReceiver(screenReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        else @Suppress("DEPRECATION") registerReceiver(screenReceiver, filter)
        receiverRegistered = true
        ready = true
        val controller = AntTrainerSearch(applicationContext, training = true, trainingOwner = this)
        ant = controller
        clearPending()
        controller.start("training_connected", request.result, request.device, listOf(
            lifecycle("service_started") + mapOf("monotonicMs" to startedAtMs),
            lifecycle("foreground_promoted") + mapOf("promotionRequestedAtMs" to promotionRequestedAtMs),
            lifecycle("notification_active") + prerequisites.toMap(),
            lifecycle(if (activityResumed) "activity_resumed" else "activity_stopped") +
                mapOf("decision" to "continue_training"),
        ), screenOff = !power.isInteractive)
        if (controller.hasActiveSession()) lastController = null
        else stopSelf()
    }

    internal fun isOperational() = ready && supervisionFailure == null

    internal fun failure(): String? {
        if (!ready) return "training_service_destroyed"
        supervisionFailure?.let { return it }
        val failure = try {
            when {
                TrainingServicePolicy.permissionBlock(permissionStatus(this)) != null -> "training_permission_lost"
                wakeLock?.isHeld != true -> "training_wakelock_lost"
                !isPromoted() -> "training_foreground_lost"
                !notificationActive() -> "training_notification_lost"
                else -> null
            }
        } catch (_: RuntimeException) {
            "training_service_unavailable"
        }
        if (failure != null) supervisionFailure = failure
        return failure
    }

    @Suppress("DEPRECATION") // Android 8+ returns the calling application's services.
    private fun isPromoted(): Boolean =
        getSystemService(ActivityManager::class.java).getRunningServices(Int.MAX_VALUE)
            .any { it.service == ComponentName(this, TrainingService::class.java) && it.foreground }

    private fun notificationActive(): Boolean =
        getSystemService(NotificationManager::class.java).activeNotifications.any {
            it.id == NOTIFICATION_ID && (it.notification.flags and Notification.FLAG_FOREGROUND_SERVICE) != 0
        }

    internal fun publish(report: Map<String, Any?>) {
        lastReport = report
        eventSink?.success(report)
    }

    internal fun finished() {
        releaseWakeLock()
        stopSelf()
    }

    private fun failStart(request: StartRequest?, detail: String) {
        if (request != null && pending === request) {
            clearPending()
            request.result.error("training_service_failed", detail, null)
        }
        android.util.Log.w(TAG, "service_start_failed: $detail")
        stopSelf()
    }

    private fun stopTraining(result: MethodChannel.Result?, reason: String, source: String) {
        val controller = ant
        if (controller != null) {
            controller.stop(result, reason, lifecycle("stop_requested") + mapOf("source" to source, "reason" to reason))
        } else {
            cancelStart("training_start_cancelled")
            result?.success(lastReport)
            stopSelf()
        }
    }

    private fun notification(token: String): Notification {
        val open = PendingIntent.getActivity(this, 0,
            Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val stop = PendingIntent.getService(this, 0, serviceIntent(this, STOP, token), PendingIntent.FLAG_IMMUTABLE)
        stopAction = stop
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, CHANNEL)
            else @Suppress("DEPRECATION") Notification.Builder(this)
        if (Build.VERSION.SDK_INT >= 31) builder.setForegroundServiceBehavior(Notification.FOREGROUND_SERVICE_IMMEDIATE)
        return builder.setSmallIcon(android.R.drawable.ic_media_play)
            .setContentTitle("OpenBkool — Entrenamiento libre activo")
            .setContentText("Sesión ANT · DETENER para finalizar")
            .setContentIntent(open)
            .setOngoing(true)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setUsesChronometer(true)
            .setDeleteIntent(stop)
            .addAction(Notification.Action.Builder(Icon.createWithResource(this, android.R.drawable.ic_media_pause), "DETENER", stop).build())
            .build()
    }

    override fun onDestroy() {
        ready = false
        main.removeCallbacks(verify)
        if (pending?.token == token) cancelStart("training_service_destroyed")
        val controller = ant
        if (controller?.hasActiveSession() == true) {
            controller.stop(reason = "training_service_destroyed", lifecycle = lifecycle("service_destroyed"))
        }
        if (receiverRegistered) unregisterReceiver(screenReceiver)
        stopAction?.cancel()
        if (controller?.hasActiveSession() != true) releaseWakeLock()
        stopForeground(STOP_FOREGROUND_REMOVE)
        if (current === this) current = null
        if (controller != null && (controller.hasActiveSession() || controller.snapshot()["sessionId"] != null)) {
            lastController = controller
        }
        android.util.Log.i(TAG, "service_stopped")
        super.onDestroy()
    }

    private fun releaseWakeLock() {
        wakeLock?.let { if (it.isHeld) it.release() }
        wakeLock = null
    }

    companion object {
        private const val TAG = "OpenBkoolTraining"
        private const val CHANNEL = "openbkool_training"
        private const val NOTIFICATION_ID = 4819
        private const val START = "com.example.openbkool.START_TRAINING"
        private const val STOP = "com.example.openbkool.STOP_TRAINING"
        private val main = Handler(Looper.getMainLooper())

        private data class StartRequest(val token: String, val device: Map<String, Any?>?, val result: MethodChannel.Result)
        private var pending: StartRequest? = null
        private val startTimeout = Runnable { cancelStart("training_service_timeout") }
        private var current: TrainingService? = null
        private var lastController: AntTrainerSearch? = null
        private var activityResumed = false
        private var eventSink: EventChannel.EventSink? = null
        private var lastReport: Map<String, Any?> = mapOf("status" to "not_started", "running" to false)

        internal fun snapshot() = lastReport
        internal fun controller() = current?.ant ?: lastController

        internal fun streamHandler() = object : EventChannel.StreamHandler {
            private var attached: EventChannel.EventSink? = null
            override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                attached = events
                eventSink = events
                events.success(lastReport)
            }
            override fun onCancel(arguments: Any?) {
                if (eventSink === attached) eventSink = null
                attached = null
            }
        }

        internal fun activityChanged(resumed: Boolean) {
            if (activityResumed == resumed) return
            activityResumed = resumed
            current?.ant?.logLifecycle(lifecycle(if (resumed) "activity_resumed" else "activity_stopped") +
                mapOf("decision" to "continue_training"))
        }

        internal fun stop(result: MethodChannel.Result, reason: String) {
            val service = current
            if (service != null) service.stopTraining(result, reason, "activity")
            else {
                cancelStart("training_start_cancelled")
                result.success(lastReport)
            }
        }

        internal fun start(context: Context, device: Map<String, Any?>?, result: MethodChannel.Result) {
            if (!TrainingServicePolicy.canStart(pending != null, current != null, lastController?.hasActiveSession() == true)) {
                result.error("ant_busy", "Ya hay un entrenamiento en curso o cerrándose", null)
                return
            }
            val manager = context.getSystemService(NotificationManager::class.java)
            if (Build.VERSION.SDK_INT >= 26) {
                manager.createNotificationChannel(NotificationChannel(CHANNEL, "Entrenamiento libre", NotificationManager.IMPORTANCE_LOW))
            }
            val blocker = TrainingServicePolicy.permissionBlock(permissionStatus(context))
            if (blocker != null) {
                result.error("training_service_blocked", blocker, null)
                return
            }
            val request = StartRequest(java.util.UUID.randomUUID().toString(), device, result)
            pending = request
            try {
                val intent = serviceIntent(context, START, request.token)
                val component = if (Build.VERSION.SDK_INT >= 26) context.startForegroundService(intent)
                    else context.startService(intent)
                checkNotNull(component) { "Android no inició el servicio" }
                main.postDelayed(startTimeout, 5000)
            } catch (error: RuntimeException) {
                clearPending()
                result.error("training_service_failed", error.message, null)
            }
        }

        private fun serviceIntent(context: Context, action: String, token: String) =
            Intent(context, TrainingService::class.java).setAction(action)
                .setData(android.net.Uri.parse("openbkool://training/$token"))

        private fun lifecycle(event: String) = mapOf("event" to event, "monotonicMs" to SystemClock.elapsedRealtime())

        private fun clearPending() {
            pending = null
            main.removeCallbacks(startTimeout)
        }

        private fun cancelStart(reason: String) {
            val request = pending ?: return
            clearPending()
            request.result.error(reason, "Entrenamiento sin iniciar", null)
        }

        internal fun permissionStatus(context: Context): TrainingPermissions {
            val manager = context.getSystemService(NotificationManager::class.java)
            fun granted(permission: String) = context.checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED
            return TrainingPermissions(
                Build.VERSION.SDK_INT,
                granted(Manifest.permission.POST_NOTIFICATIONS),
                granted(Manifest.permission.BLUETOOTH_CONNECT) || granted(Manifest.permission.BLUETOOTH_SCAN),
                manager.areNotificationsEnabled() && (Build.VERSION.SDK_INT < 26 ||
                    manager.getNotificationChannel(CHANNEL)?.importance != NotificationManager.IMPORTANCE_NONE),
            )
        }
    }
}
