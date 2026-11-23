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
    private class ReuseRequest(val checkOnly: Boolean) {
        @Volatile var cancelled = false
    }

    private var reuseRequest: ReuseRequest? = null
    private var notifiedState: Pair<String, Boolean>? = null
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
            val connectionOnly = intent.getBooleanExtra("connectionOnly", false)
            if (requestedToken != null) stopTraining(null, "user_finish", "notification",
                connectionOnly, requestedToken, disconnect = intent.getBooleanExtra("disconnect", false))
            if (token == null && pending == null) stopSelf(startId)
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
            val notice = notification(requestedToken, request?.checkOnly == true, false)
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
        startOnController(controller, request.device, request.result, request.checkOnly, prerequisites)
        if (!controller.hasActiveSession()) stopSelf()
    }

    private fun startOnController(controller: AntTrainerSearch, device: Map<String, Any?>?,
        result: MethodChannel.Result, checkOnly: Boolean, prerequisites: TrainingPermissions) {
        controller.start(if (checkOnly) "training_connection_check" else "training_connected", result, device, listOf(
            lifecycle("service_started") + mapOf("monotonicMs" to startedAtMs),
            lifecycle("foreground_promoted") + mapOf("promotionRequestedAtMs" to promotionRequestedAtMs),
            lifecycle("notification_active") + prerequisites.toMap(),
            lifecycle(if (activityResumed) "activity_resumed" else "activity_stopped") +
                mapOf("decision" to "continue_connection"),
        ), screenOff = !getSystemService(PowerManager::class.java).isInteractive)
    }

    private fun reuse(device: Map<String, Any?>?, result: MethodChannel.Result, checkOnly: Boolean) {
        val controller = ant
        if (controller == null || !ready) {
            result.error("ant_busy", "La conexión ANT se está iniciando", null)
            return
        }
        failure()?.let {
            controller.stop(reason = it)
            result.error("training_service_failed", "Servicio ANT no disponible", null)
            return
        }
        if (reuseRequest != null) {
            result.error("ant_busy", "La conexión ANT se está iniciando", null)
            return
        }
        val request = ReuseRequest(checkOnly)
        reuseRequest = request
        val reply = object : MethodChannel.Result {
            private fun deliver(send: () -> Unit) {
                main.post {
                    if (reuseRequest === request) reuseRequest = null
                    send()
                }
            }
            override fun success(value: Any?) = deliver { result.success(value) }
            override fun error(code: String, message: String?, details: Any?) = deliver { result.error(code, message, details) }
            override fun notImplemented() = deliver { result.notImplemented() }
        }
        controller.reuse(device, checkOnly, reply, { request.cancelled }) { released ->
            when {
                request.cancelled -> reply.error("training_start_cancelled", "Entrenamiento sin iniciar", null)
                !released -> reply.error("cleanup_failed", "No se pudo liberar el canal ANT", null)
                failure() != null -> reply.error("training_service_destroyed", "Servicio ANT finalizado", null)
                else -> startOnController(controller, device, reply, checkOnly, permissionStatus(this))
            }
            if (!controller.hasActiveSession()) finished()
        }
    }

    internal fun idleExpired(now: Long, readySince: Long?) =
        TrainingServicePolicy.idleExpired(now, readySince, backgroundSinceMs)

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

    internal fun archiveWorkout(report: Map<String, Any?>) {
        val id = report["sessionId"] as? String ?: return
        synchronized(workoutReports) {
            workoutReports[id] = report
            if (workoutReports.size > 4) workoutReports.remove(workoutReports.keys.first())
        }
    }

    internal fun workoutReport(id: String?) = synchronized(workoutReports) {
        if (id == null) workoutReports.values.lastOrNull() else workoutReports[id]
    }

    internal fun publish(report: Map<String, Any?>) {
        if (current !== this && current != null) return
        lastReport = report
        eventSink?.success(report)
        val state = report["antConnectionState"]
        val id = report["connectionActionId"] as? String ?: return
        if (!ready || state == "disconnected" || !isOperational()) return
        val connectionOnly = report["connectionOnly"] == true
        val connected = state == "read_only"
        val signature = id to connected
        if (notifiedState != signature) {
            notifiedState = signature
            stopAction?.cancel()
            try {
                val notice = notification(id, connectionOnly, connected)
                if (Build.VERSION.SDK_INT >= 29) {
                    startForeground(NOTIFICATION_ID, notice, ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE)
                } else {
                    startForeground(NOTIFICATION_ID, notice)
                }
            } catch (_: RuntimeException) {
                supervisionFailure = "training_notification_lost"
                ant?.stop(reason = "training_notification_lost")
            }
        }
    }

    internal fun finished() {
        if (ant?.hasActiveSession() == true) return
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

    private fun stopTraining(result: MethodChannel.Result?, reason: String, source: String,
        connectionOnly: Boolean, expectedId: String? = null, disconnect: Boolean = false) {
        if (expectedId == null && reuseRequest?.checkOnly == connectionOnly) reuseRequest?.cancelled = true
        val controller = ant
        if (controller != null) {
            controller.stopConnectionOrWorkout(result, reason,
                lifecycle("stop_requested") + mapOf("source" to source, "reason" to reason),
                connectionOnly, expectedId, disconnect)
        } else {
            if ((expectedId == null || expectedId == token) && pending?.checkOnly == connectionOnly) {
                cancelStart("training_start_cancelled")
                stopSelf()
            }
            result?.success(lastReport)
        }
    }

    private fun notification(token: String, checkOnly: Boolean, connected: Boolean): Notification {
        val open = PendingIntent.getActivity(this, 0,
            Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val stop = PendingIntent.getService(this, 0, serviceIntent(this, STOP, token)
            .putExtra("connectionOnly", checkOnly).putExtra("disconnect", connected),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_CANCEL_CURRENT)
        stopAction = stop
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, CHANNEL)
            else @Suppress("DEPRECATION") Notification.Builder(this)
        if (Build.VERSION.SDK_INT >= 31) builder.setForegroundServiceBehavior(Notification.FOREGROUND_SERVICE_IMMEDIATE)
        return builder.setSmallIcon(android.R.drawable.ic_media_play)
            .setContentTitle(when {
                connected -> "OpenBkool — Rodillo conectado"
                checkOnly -> "OpenBkool — Comprobando conexión"
                else -> "OpenBkool — Entrenamiento libre"
            })
            .setContentText(if (checkOnly) "Conexión ANT" else "Sesión ANT")
            .setContentIntent(open)
            .setOngoing(true)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setUsesChronometer(false)
            .setDeleteIntent(stop)
            .addAction(Notification.Action.Builder(Icon.createWithResource(this, android.R.drawable.ic_media_pause), if (connected) "DESCONECTAR" else if (checkOnly) "CANCELAR" else "DETENER", stop).build())
            .build()
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        // Removing the task closes an idle connection. An active workout retains
        // its foreground notification and can still be stopped there.
        ant?.stopConnectionOrWorkout(null, "task_removed", lifecycle("task_removed"),
            connectionOnly = true, expectedId = null, disconnect = true)
        super.onTaskRemoved(rootIntent)
    }

    override fun onDestroy() {
        ready = false
        reuseRequest?.cancelled = true
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
        if (current === this) {
            if (lastReport["trainingServiceActive"] == true) {
                publish(lastReport + mapOf("trainingServiceActive" to false,
                    "antConnectionState" to "error", "connectionState" to "closed"))
            }
            current = null
        }
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

        private data class StartRequest(val token: String, val device: Map<String, Any?>?, val result: MethodChannel.Result, val checkOnly: Boolean)
        private var pending: StartRequest? = null
        private val startTimeout = Runnable { cancelStart("training_service_timeout") }
        private var current: TrainingService? = null
        private val workoutReports = linkedMapOf<String, Map<String, Any?>>()
        private var lastController: AntTrainerSearch? = null
        private var activityResumed = false
        @Volatile private var backgroundSinceMs: Long? = SystemClock.elapsedRealtime()
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
            backgroundSinceMs = if (resumed) null else SystemClock.elapsedRealtime()
            current?.ant?.logLifecycle(lifecycle(if (resumed) "activity_resumed" else "activity_stopped") +
                mapOf("decision" to "continue_training"))
        }

        internal fun stop(result: MethodChannel.Result, reason: String, connectionOnly: Boolean,
            expectedId: String?, disconnect: Boolean) {
            val service = current
            if (service != null) service.stopTraining(result, reason, "activity", connectionOnly, expectedId, disconnect)
            else {
                if (expectedId == null && pending?.checkOnly == connectionOnly) cancelStart("training_start_cancelled")
                result.success(lastReport)
            }
        }

        internal fun start(context: Context, device: Map<String, Any?>?, result: MethodChannel.Result, checkOnly: Boolean) {
            current?.let { it.reuse(device, result, checkOnly); return }
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
            val request = StartRequest(java.util.UUID.randomUUID().toString(), device, result, checkOnly)
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
