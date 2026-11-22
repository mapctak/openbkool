package com.example.openbkool

import android.content.ComponentName
import android.content.Context
import android.content.ServiceConnection
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import com.dsi.ant.AntService
import com.dsi.ant.channel.AntChannel
import com.dsi.ant.channel.Capabilities
import com.dsi.ant.channel.ChannelNotAvailableException
import com.dsi.ant.channel.ChannelNotAvailableReason
import com.dsi.ant.channel.IAntChannelEventHandler
import com.dsi.ant.channel.PredefinedNetwork
import com.dsi.ant.message.ChannelId
import com.dsi.ant.message.ChannelType
import com.dsi.ant.message.ExtendedAssignment
import com.dsi.ant.message.LibConfig
import com.dsi.ant.message.fromant.MessageFromAntType
import com.dsi.ant.message.ipc.AntMessageParcel
import com.dsi.ant.plugins.antplus.pcc.AntPlusFitnessEquipmentPcc
import com.dsi.ant.plugins.antplus.pcc.MultiDeviceSearch
import com.dsi.ant.plugins.antplus.pcc.defines.DeviceState
import com.dsi.ant.plugins.antplus.pcc.defines.DeviceType
import com.dsi.ant.plugins.antplus.pcc.defines.RequestAccessResult
import com.dsi.ant.plugins.antplus.pccbase.PccReleaseHandle
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.text.SimpleDateFormat
import java.util.Date
import java.util.EnumSet
import java.util.Locale
import java.util.TimeZone
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.RejectedExecutionException

/** Diagnóstico RX y entrenamiento V1; control manual solo tras activación explícita por sesión. */
class AntTrainerSearch(context: Context, private val training: Boolean = false, private val trainingOwner: TrainingService? = null) : EventChannel.StreamHandler {
    private val context = context.applicationContext
    private val main = Handler(Looper.getMainLooper())
    private var sink: EventChannel.EventSink? = null
    @Volatile private var active: Session? = null
    @Volatile private var latest: Map<String, Any?> = mapOf("status" to "not_started", "running" to false)

    @Volatile private var lastFinished: Map<String, Any?>? = null

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        sink = events
        events.success(snapshot())
    }
    override fun onCancel(arguments: Any?) {
        sink = null
        if (!training) stop(reason = "event_stream_closed")
    }
    fun snapshot(): Map<String, Any?> = latest
    internal fun hasActiveSession() = active != null
    internal fun logLifecycle(entry: Map<String, Any?>) {
        val session = active ?: return
        session.submit { session.recordLifecycle(entry) }
    }
    internal fun screenChanged(off: Boolean) {
        val session = active ?: return
        session.submit { session.screenChanged(off) }
    }

    fun start(mode: String, result: MethodChannel.Result, selected: Map<*, *>? = null,
        lifecycle: List<Map<String, Any?>> = emptyList(), screenOff: Boolean = false) {
        if (mode !in (if (training) listOf("training_connected") else listOf("sequential", "fec", "bkool_v1"))) {
            result.error("invalid_mode", "Protocolo no implementado", null); return
        }
        if (active != null) { result.error("ant_busy", "Espera a que finalice la búsqueda anterior", null); return }
        if (mode == "training_connected" && selected == null) {
            result.error("invalid_target", "Selecciona explícitamente un rodillo antes de conectar", null); return
        }
        val target = try {
            if (selected == null) AntTrainerIdentity(30064, 112, 5) else {
                require(selected["protocol"] == "BKOOL_V1_PUBLIC") { "Solo BKOOL_V1_PUBLIC" }
                fun integer(key: String): Int {
                    val value = selected[key]
                    require(value is Int) { "Identificador entero requerido: $key" }
                    return value
                }
                AntTrainerIdentity(integer("deviceNumber"), integer("deviceType"), integer("transmissionType"))
            }
        } catch (error: Exception) { result.error("invalid_target", error.message, null); return }
        val session = Session(mode, target)
        if (!AntRadioCoordinator.acquire(session)) {
            session.worker.shutdown()
            result.error("ant_busy", "Otra operación ANT está usando la radio", null); return
        }
        active = session
        session.submit { session.begin(lifecycle, screenOff) }
        result.success(mapOf("accepted" to true))
    }

    fun stop(result: MethodChannel.Result? = null, reason: String = "stopped", lifecycle: Map<String, Any?>? = null) {
        val session = active
        if (session == null) { result?.success(latest); return }
        session.cancelled = true
        session.invalidateTargets(reason)
        try {
            session.worker.execute {
                lifecycle?.let(session::recordLifecycle)
                session.end(reason, result)
            }
        } catch (_: RejectedExecutionException) { result?.success(latest) }
    }
    fun manualAction(method: String, sessionId: String?, explicit: Boolean, percent: Double?,
        result: MethodChannel.Result, requestedAtUtc: String?, rapidAdjustment: Boolean, uiQueueMs: Long?) {
        val requestedAt = android.os.SystemClock.elapsedRealtime()
        val session = active
        if (!training || session == null) { result.error("not_connected", "No hay entrenamiento activo", null); return }
        if (session.id != sessionId) { result.error("stale_session", "La sesión ha cambiado; vuelve a conectar", null); return }
        if (!session.commandFence.tryEnqueue()) { result.error("command_busy", "Ya hay una orden en curso", null); return }
        val manualChange = method == "setManualSlope"
        if (manualChange) session.waitingManualChanges.incrementAndGet()
        try { session.worker.execute {
            if (manualChange) session.waitingManualChanges.decrementAndGet()
            val cancelled = session.commandFence.dequeue()
            if (cancelled != null) session.rejectPending(method, percent, cancelled, result)
            else session.manualAction(method, explicit, percent, result, requestedAt, requestedAtUtc, rapidAdjustment, uiQueueMs)
        } } catch (_: RejectedExecutionException) {
            session.commandFence.dequeue()
            if (manualChange) session.waitingManualChanges.decrementAndGet()
            result.error("session_closed", "Sesión cerrada", null)
        }
    }
    fun exportJson(sessionId: String?, finalized: Boolean, result: MethodChannel.Result) {
        val report = if (finalized) lastFinished else latest
        if (report == null || report["sessionId"] == null || (sessionId != null && report["sessionId"] != sessionId)) {
            result.error("report_unavailable", "El registro de esa sesión no está disponible", null)
            return
        }
        result.success(report + mapOf("capturedAt" to now()))
    }

    fun exportCsv(sessionId: String?, result: MethodChannel.Result) {
        val report = lastFinished
        if (report == null || (sessionId != null && report["sessionId"] != sessionId)) {
            result.error("report_unavailable", "El CSV final de esa sesión no está disponible", null)
            return
        }
        val name = report["csvFile"] as? String
        if (name == null) { result.error("no_csv", "No hay registro CSV", null); return }
        Thread {
            try {
                val csv = java.io.File(context.filesDir, name).readText()
                main.post { result.success(csv) }
            } catch (error: Exception) { main.post { result.error("csv_error", error.message, null) } }
        }.start()
    }
    fun dispose() { stop(reason = "engine_disposed"); sink = null }

    private inner class Session(val mode: String, val target: AntTrainerIdentity) : ServiceConnection {
        val worker = AntSerialWorker()
        val commandFence = ManualCommandFence()
        private val captureAnchorMs = android.os.SystemClock.elapsedRealtime()
        private val captureAnchorUtcMs = System.currentTimeMillis()
        fun invalidateTargets(reason: String) {
            commandFence.cancel(reason)
            manual.invalidateTargets(reason)
            main.removeCallbacks(trainingTick)
        }
        private val transmissionAudit = AntTransmissionAudit(android.os.SystemClock::elapsedRealtime)
        @Volatile var cancelled = false
        @Volatile private var finished = false
        @Volatile private var generation = 0
        private var stage = "starting"
        private var status = "running"
        private var reportSequence = 0L
        private val startedAt = now()
        private val identificationTiming = AntIdentificationTiming(android.os.SystemClock::elapsedRealtime, target) {
            val type = if (it["milestone"] == "manufacturer_model_wait_long") "identification_wait" else "identification_milestone"
            event(type, "${it["milestone"]}: ${it["elapsedMs"]} ms", details = it)
        }
        val id = java.util.UUID.randomUUID().toString()
        private var stopping = false
        @Volatile private var radioDead = false
        private val stopReplies = mutableListOf<MethodChannel.Result>()
        val waitingManualChanges = java.util.concurrent.atomic.AtomicInteger(0)
        private val virtualElevation = if (training) VirtualElevation() else null
        private val manualEvents = ArrayDeque<Map<String, Any?>>()
        private var droppedManualEvents = 0
        private var stopDrainUntilMs = 0L
        private var finalClose: Runnable? = null
        private val manual: ManualAntControl by lazy { ManualAntControl(target, android.os.SystemClock::elapsedRealtime,
            ::manualLink, { payload, zero ->
                if (!zero && (cancelled || trainingOwner?.failure() != null)) throw ManualCommandCancelledException()
                check(!finished && !radioDead && transmissionAudit.channelUsable &&
                    (if (zero) manualLink().stopReason(target) else manualLink().reason(target)) == null) { "Canal o señal no disponibles" }
                val selectedChannel = checkNotNull(channel) { "Canal cerrado" }
                manual.recordApiEntry()
                selectedChannel.setBroadcastData(payload)
            }, { e ->
                if (e["event"] == "api_returned" && e["periodicRefresh"] != true && e["stopRequest"] != true) {
                    (e["requestedPercent"] as? Double)?.let { virtualElevation?.accepted(it) }
                }
                if (e["event"] == "stop_requested" || e["event"] == "api_error") virtualElevation?.unavailable()
                val entry = e + mapOf("timestamp" to now(), "sessionId" to id)
                if (manualEvents.size >= 2000) { manualEvents.removeFirst(); droppedManualEvents++ }
                manualEvents.addLast(entry)
                record("manual:${entry["event"]}", null, entry)
                schedulePublish()
            },
                manualPriorityWaiting = { waitingManualChanges.get() > 0 }, describeError = ::antErrorDetails) }
        private fun manualLink(): ManualControlLink {
            val t = telemetry?.snapshot(android.os.SystemClock.elapsedRealtime())
            val device = devices.values.firstOrNull { it["deviceNumber"] == target.number && it["deviceType"] == target.type && it["transmissionType"] == target.transmission }
            return ManualControlLink(dedicated,
                identityVerified, device?.get("manufacturerId") as? Int, device?.get("modelNumber") as? Int,
                t?.get("signalAgeMs") as? Long,
                t?.get("speedKmh") != null && t["powerW"] != null && t["cadenceRpm"] != null,
                channelOpen = opened, radioAvailable = !radioDead, sessionActive = !finished,
                activeIdentityMatches = channelIdentitiesMatch(target, configuredChannelId, adapterChannelId, receivedChannelId))
        }
        private val dedicated = mode == "training_connected"
        private var identityVerified = false
        private var configuredChannelId: Map<String, Any?>? = null
        private var adapterChannelId: Map<String, Any?>? = null
        private var receivedChannelId: Map<String, Any?>? = null
        private var identityReadbackError: Map<String, Any?>? = null
        private var lastManualAvailability: String? = null
        private val telemetry = if (training) BkoolTelemetry(android.os.SystemClock.elapsedRealtime(), target) else null
        private var csvFile: String? = null
        private var csv: java.io.BufferedWriter? = null
        private var csvError: String? = null
        private var lastSignal: String? = null
        private var nextSupervisionAt = 0L
        private val trainingTick = Runnable { submit {
            if (finished || cancelled || !opened) return@submit
            trainingOwner?.failure()?.let { stopForServiceFailure(it); return@submit }
            manual.supervise()
            if (handleControlAbort()) return@submit
            val now = android.os.SystemClock.elapsedRealtime()
            val superviseLink = now >= nextSupervisionAt
            if (superviseLink) {
                nextSupervisionAt = now + 1000
                manual.refreshTarget()
            } else {
                manual.flushPending()
            }
            trainingOwner?.failure()?.let { stopForServiceFailure(it); return@submit }
            if (manual.snapshot()["faulted"] == true) { finish("manual_api_error"); return@submit }
            if (superviseLink) {
                val signal = telemetry!!.signal(android.os.SystemClock.elapsedRealtime())
                if (signal != lastSignal) {
                    event("signal", signal)
                    lastSignal = signal
                    record("signal:$signal", null)
                }
                try { csv?.flush() } catch (error: Exception) { csvFailure(error) }
                if (signal == "disconnected") { finish("disconnected"); return@submit }
            }
            publish()
            scheduleTrainingTick()
        } }

        private fun scheduleTrainingTick() {
            main.removeCallbacks(trainingTick)
            if (finished || cancelled || !opened) return
            val supervisionDelay = (nextSupervisionAt - android.os.SystemClock.elapsedRealtime()).coerceAtLeast(0)
            val delay = minOf(supervisionDelay, manual.nextManualDelayMs() ?: supervisionDelay)
            main.postDelayed(trainingTick, delay)
            if (finished || cancelled) main.removeCallbacks(trainingTick)
        }
        // Metric dropout revokes the authorization for this connection. The existing
        // single zero and drain are reused, while RX supervision stays alive.
        private fun handleControlAbort(result: MethodChannel.Result? = null): Boolean {
            val failure = manual.abortReason() ?: return false
            if (failure != "link_lost:telemetry_not_fresh") {
                end(failure, result)
                return true
            }
            val zeroQueued = manual.suspendForMissingTelemetry()
            if (zeroQueued) stopDrainUntilMs = android.os.SystemClock.elapsedRealtime() + ManualAntControl.DRAIN_MS
            event("control_suspended", "Telemetría parcial; control suspendido. Solicitud 0 % a API=$zeroQueued")
            return false
        }
        private fun csvFailure(error: Exception) {
            csvError = error.toString()
            runCatching { csv?.close() }; csv = null
            event("csv_error", "Registro CSV interrumpido: $error")
        }
        private var isScreenOff = false
        private var screenOffFrames = 0L
        fun screenChanged(off: Boolean) {
            if (finished || off == isScreenOff) return
            if (off) screenOffFrames = 0
            isScreenOff = off
            recordLifecycle(mapOf("event" to if (off) "screen_off" else "screen_on",
                "decision" to "continue_training", "antFramesWhileOff" to screenOffFrames,
                "monotonicMs" to android.os.SystemClock.elapsedRealtime()))
        }
        private fun stopForServiceFailure(reason: String, result: MethodChannel.Result? = null) {
            recordLifecycle(mapOf("event" to "training_service_lost", "decision" to "stop", "reason" to reason))
            end(reason, result)
        }
        fun recordLifecycle(entry: Map<String, Any?>) {
            event("android_lifecycle", entry["event"].toString(), details = entry)
            record("android:${entry["event"]}", null, entry)
        }
        private fun record(kind: String, payload: ByteArray?, details: Map<String, Any?>? = null) {
            val t = telemetry?.snapshot(android.os.SystemClock.elapsedRealtime()) ?: return
            try { csv?.write(csvRow(listOf(now(), t["elapsedMs"], kind, "BKOOL_V1_PUBLIC", target.number, target.type, target.transmission,
                payload?.let { hex(it) }, t["speedKmh"], t["powerW"], t["cadenceRpm"], t["distanceM"],
                t["signal"], t["distancePartial"], t["speedAgeMs"], t["powerAgeMs"], details?.let { org.json.JSONObject(it).toString() }, id))) }
            catch (error: Exception) { csvFailure(error) }
        }
        private val devices = linkedMapOf<String, MutableMap<String, Any?>>()
        private val events = ArrayDeque<Map<String, Any?>>()
        private val frames = ArrayDeque<Map<String, Any?>>()
        private val operationEvents = mutableListOf<Map<String, Any?>>()
        private var v1Failure: Map<String, Any?>? = null
        private var adapterCapabilities: List<Map<String, Any?>>? = null
        private var channelCapabilities: Map<String, Any?>? = null
        private val operations = AntOperationTrace({ operation ->
            val entry = operation + mapOf("timestamp" to now(), "stage" to stage)
            operationEvents.add(entry)
            val error = operation["error"] as? Map<*, *>
            event("ant_operation", "${operation["operation"]} [${operation["state"]}] " +
                if (error == null) "${operation["reason"] ?: ""}" else "${error["type"]}: ${error["failureReason"] ?: ""} ${error["message"]}")
        }, ::antErrorDetails)
        private var droppedFrames = 0
        private var droppedEvents = 0
        private val fecQueue = ArrayDeque<Int>()
        private var multi: MultiDeviceSearch? = null
        private var fec: PccReleaseHandle<AntPlusFitnessEquipmentPcc>? = null
        private var channel: AntChannel? = null
        private var previousLibConfig: LibConfig? = null
        private var libConfigChanged = false
        private val channelClosed = CountDownLatch(1)
        private var opened = false
        private var assigned = false
        private var bound = false
        private var phaseDeadline: Runnable? = null
        private var deadlineSerial = 0
        private var resourcesReleased = true
        private var cleanupFailed = false
        private var phaseErrors = false
        private var pendingSnapshot = false
        private val publishLater = Runnable { submit { pendingSnapshot = false; if (!finished) publish() } }

        fun submit(block: () -> Unit) {
            try { worker.execute(block) } catch (_: RejectedExecutionException) { }
        }
        private fun callback(token: Int, block: () -> Unit) = submit {
            if (!finished && !cancelled && generation == token) {
                try { block() }
                catch (_: java.util.concurrent.CancellationException) { if (!cancelled) finish("stopped") }
                catch (error: Exception) { fail("callback", error) }
            }
        }
        fun rejectPending(method: String, percent: Double?, reason: String, result: MethodChannel.Result) {
            event("command_cancelled", "Orden en cola cancelada: $reason", details = mapOf(
                "method" to method, "requestedPercent" to percent, "reason" to reason, "apiCalled" to false))
            publish()
            result.error("command_cancelled", "Orden cancelada por parada: $reason", null)
        }
        fun manualAction(method: String, explicit: Boolean, percent: Double?, result: MethodChannel.Result,
            requestedAt: Long, requestedAtUtc: String?, rapidAdjustment: Boolean, uiQueueMs: Long?) {
            if (finished || stopping || cancelled) {
                result.error("session_stopping", "La sesión está cerrándose", null); return
            }
            trainingOwner?.failure()?.let { stopForServiceFailure(it, result); return }
            when (method) {
                "authorizeControl" -> manual.enable(explicit)
                "setManualSlope" -> {
                    if (percent == null) { result.error("invalid_slope", "Pendiente numérica requerida", null); return }
                    record("slope_selection", null, mapOf("selectedPercent" to percent.takeIf { it.isFinite() },
                        "requestedAtMs" to requestedAt, "requestedAtUtc" to requestedAtUtc))
                    manual.request(percent, requestedAt, requestedAtUtc, rapidAdjustment, uiQueueMs)
                    scheduleTrainingTick()
                }
            }
            trainingOwner?.failure()?.let { stopForServiceFailure(it, result); return }
            if (handleControlAbort(result)) return
            if (manual.snapshot()["faulted"] == true) { end("manual_api_error", result); return }
            publish(); result.success(latest)
        }
        fun begin(lifecycle: List<Map<String, Any?>>, screenOff: Boolean) {
            event("search_start", "Búsqueda $mode. Solo recepción e información; Bkool V2 desactivado.")
            if (training) {
                try {
                    val file = java.io.File.createTempFile("training_", ".csv", context.filesDir)
                    csvFile = file.name; csv = file.bufferedWriter()
                    csv!!.write(csvRow(listOf("timestamp_utc", "elapsed_ms", "event", "protocol", "device_id", "device_type", "transmission_type",
                        "payload_hex", "speed_kmh", "power_w", "cadence_rpm", "distance_m", "signal", "distance_partial", "speed_age_ms", "power_age_ms", "details_json", "session_id")))
                    record("session_started", null, mapOf("recordState" to "partial"))
                } catch (error: Exception) { csvFailure(error); finish("error"); return }
            }
            lifecycle.forEach(::recordLifecycle)
            if (screenOff) screenChanged(true)
            if (cancelled) return // The queued stop records its own reason and closes the session.
            if (training || mode == "bkool_v1") beginV1() else beginFecSearch()
        }
        private fun event(type: String, message: String, error: Exception? = null, details: Map<String, Any?>? = null) {
            if (training && events.size >= 500) { events.removeFirst(); droppedEvents++ }
            events.addLast(mapOf("timestamp" to now(), "event" to type, "stage" to stage,
                "sessionId" to id, "message" to message, "errorType" to error?.javaClass?.simpleName, "details" to details))
            if (training && (error != null || type in setOf("channel_event", "channel_death",
                "service_disconnected", "channel_identity_mismatch", "identification_wait", "command_cancelled"))) {
                record(type, null, mapOf("message" to message, "error" to error?.message) + details.orEmpty())
            }
            schedulePublish()
        }
        private fun fail(where: String, error: Exception) {
            if (training && cancelled) return // The queued stop owns its reason and lifecycle row.
            phaseErrors = true
            if (stage == "bkool_v1") {
                v1Failure = mapOf("operation" to operations.failureFor(error)?.get("operation"),
                    "operationTrace" to operations.failureFor(error), "error" to antErrorDetails(error))
            }
            event("error", "$where / ${operations.failureFor(error)?.get("operation") ?: "sin operación ANT activa"}: ${error.message ?: error}", error)
            advance()
        }
        private fun schedulePublish() {
            if (!pendingSnapshot && !finished) {
                pendingSnapshot = true
                main.postDelayed(publishLater, 200)
            }
        }
        private fun publish() {
            if (active !== this && (!finished || latest["sessionId"] != id)) return
            val manualState = manual.snapshot() + mapOf("pendingCommands" to commandFence.snapshot()["pendingApplicationCommands"])
            if (training) identificationTiming.availability(manualState["eligible"] == true,
                (manualState["blockingReasons"] as? List<*>)?.filterIsInstance<String>() ?: emptyList(), !finished && !stopping)
            val signature = "${manualState["eligible"]}:${manualState["blockingReasons"]}"
            if (training && lastManualAvailability != signature) {
                lastManualAvailability = signature
                event("manual_availability", "Control elegible=${manualState["eligible"]}; bloqueos=${manualState["blockingReasons"]}",
                    details = mapOf("manualControl" to manualState, "selectedDevice" to target.toMap(),
                        "configuredChannelId" to configuredChannelId, "adapterChannelId" to adapterChannelId,
                        "receivedChannelId" to receivedChannelId, "identityReadbackError" to identityReadbackError))
            }
            val report = mapOf(
                "controlDiagnosticsVersion" to 13,
                "recordState" to if (finished) "final" else "partial",
                "backgroundPolicy" to if (training) "foreground_service" else null,
                "trainingServiceActive" to (!finished && trainingOwner?.isOperational() == true),
                "transmissionDiagnostics" to (transmissionAudit.snapshot() + mapOf(
                    "lastManualOrder" to manualState["lastManualApiSuccess"],
                    "lastStopCommand" to manualState["lastStopCommand"],
                    "stopResult" to manualState["stopResult"], "lastApiResult" to (manualState["lastApiError"] ?: manualState["lastApiSuccess"]),
                    "lastControllerResult" to manualState["lastResult"])),
                "commandQueue" to commandFence.snapshot(),
                "radioCaptureCorrelation" to mapOf("clock" to "android_elapsedRealtime_ms",
                    "anchorMonotonicMs" to captureAnchorMs, "anchorUtcEpochMs" to captureAnchorUtcMs,
                    "externalClockAlignment" to "required_not_automatically_verified",
                    "apiToRfDelivery" to "unconfirmed", "txPayloadCorrelation" to "unavailable"),
                "identificationTiming" to if (training) identificationTiming.snapshot() else null,
                "reportSequence" to ++reportSequence,
                "channelIdentity" to mapOf("selected" to target.toMap(), "configured" to configuredChannelId,
                    "adapterReadback" to adapterChannelId, "lastReceived" to receivedChannelId,
                    "allMatch" to channelIdentitiesMatch(target, configuredChannelId, adapterChannelId, receivedChannelId),
                    "readbackError" to identityReadbackError),
                "sessionId" to id, "manualControl" to manualState, "manualControlEvents" to manualEvents.toList(), "droppedManualControlEvents" to droppedManualEvents,
                "antLink" to when {
                    finished || !opened -> "channel_closed"
                    radioDead -> "radio_unavailable"
                    else -> telemetry?.signal(android.os.SystemClock.elapsedRealtime())
                },
                "selectedDevice" to target.toMap(),
                "channelMode" to if (dedicated) "dedicated_bidirectional_manual_opt_in" else "background_receive_only",
                "connectionState" to if (finished) "closed" else if (identityVerified) "identity_verified" else "waiting_for_identity",
                "virtualElevation" to virtualElevation?.snapshot(),
                "telemetry" to telemetry?.snapshot(android.os.SystemClock.elapsedRealtime()),
                "csvFile" to csvFile, "csvError" to csvError,
                "status" to status, "running" to !finished, "stage" to stage,
                "mode" to mode, "startedAt" to startedAt, "updatedAt" to now(),
                "devices" to devices.values.map { HashMap(it) }, "events" to events.toList(),
                "messages" to frames.toList(), "droppedMessages" to droppedFrames,
                "droppedEvents" to droppedEvents, "resourcesReleased" to resourcesReleased,
                "bkoolV2Enabled" to false,
                "operationEvents" to operationEvents.toList(),
                "v1Failure" to v1Failure, "lastOperation" to operations.lastOperation,
                "firstOperationFailure" to operations.firstFailure,
                "adapterCapabilities" to adapterCapabilities, "channelCapabilities" to channelCapabilities,
                "parameters" to mapOf("fecSeconds" to 30, "fecInfoSecondsPerDevice" to 20,
                    "v1Seconds" to if (training) null else 40, "v1Network" to "PUBLIC", "v1Rf" to 40,
                    "v1Period" to 32768, "v1ReceiveOnly" to !dedicated,
                    "v1WildcardId" to !dedicated, "v1ExpectedType" to 112,
                    "v1RadioTimeoutsApplied" to dedicated),
            )
            if (training && finished) lastFinished = report
            latest = report
            main.post {
                if (latest === report) {
                    sink?.success(report)
                    trainingOwner?.publish(report)
                }
            }
        }
        private fun deadline(seconds: Int, action: () -> Unit) {
            phaseDeadline?.let { main.removeCallbacks(it) }
            val token = generation
            val serial = ++deadlineSerial
            val task = Runnable { callback(token) { if (deadlineSerial == serial) action() } }
            phaseDeadline = task
            main.postDelayed(task, seconds * 1000L)
        }
        private fun beginFecSearch() {
            if (cancelled) { finish("stopped"); return }
            generation++; val token = generation
            stage = "fec_search"; resourcesReleased = false
            event("phase_start", "FE-C: descubrimiento oficial Fitness Equipment, 30 s")
            deadline(30) { advance() }
            try {
                multi = MultiDeviceSearch(context, EnumSet.of(DeviceType.FITNESS_EQUIPMENT),
                    object : MultiDeviceSearch.SearchCallbacks {
                        override fun onSearchStarted(rssi: MultiDeviceSearch.RssiSupport) {
                            callback(token) { event("fec_started", "SDK FE-C iniciado; RSSI: $rssi") }
                        }
                        override fun onDeviceFound(found: com.dsi.ant.plugins.antplus.pccbase.MultiDeviceSearch.MultiDeviceSearchResult) {
                            callback(token) {
                                val number = found.antDeviceNumber
                                if (number !in 1..65535 || found.antDeviceType != DeviceType.FITNESS_EQUIPMENT) {
                                    event("invalid_fec_identity", "Resultado FE-C con identidad inválida: $number")
                                    return@callback
                                }
                                val key = "ANT_PLUS_FEC:$number"
                                if (!devices.containsKey(key)) {
                                    devices[key] = linkedMapOf("key" to key, "deviceNumber" to number,
                                        "deviceType" to found.antDeviceType.intValue, "protocol" to "ANT_PLUS_FEC",
                                        "firstSeen" to now(), "lastSeen" to now(),
                                        "displayName" to found.deviceDisplayName,
                                        "transmissionType" to null, "rawMessagesAvailable" to false)
                                    fecQueue.addLast(number)
                                    event("device_found", "FE-C ID=$number tipo=${found.antDeviceType.intValue}")
                                }
                            }
                        }
                        override fun onSearchStopped(reason: RequestAccessResult) {
                            callback(token) {
                                phaseErrors = true
                                event("fec_search_stopped", "SDK detuvo FE-C: $reason")
                                advance()
                            }
                        }
                    })
            } catch (error: Exception) { fail("FE-C search", error) }
            publish()
        }
        private fun beginFecInfo() {
            if (cancelled) { finish("stopped"); return }
            if (fecQueue.isEmpty()) { if (mode == "sequential") beginV1() else finish(if (phaseErrors) "partial" else "completed"); return }
            generation++; val token = generation
            val number = fecQueue.removeFirst()
            stage = "fec_info"; resourcesReleased = false
            event("phase_start", "Información FE-C ID=$number, hasta 20 s de recepción; sin solicitudes de control")
            deadline(8) { advance() }
            val device = devices.getValue("ANT_PLUS_FEC:$number")
            try {
                fec = AntPlusFitnessEquipmentPcc.requestNewOpenAccess(context, number, 0,
                    { pcc, result, _ -> callback(token) {
                        if (result != RequestAccessResult.SUCCESS || pcc == null) {
                            phaseErrors = true; event("fec_access_error", "FE-C ID=$number: $result"); advance()
                        } else {
                            event("fec_listening", "Suscripciones informativas FE-C ID=$number")
                            deadline(20) { advance() }
                            pcc.subscribeManufacturerIdentificationEvent { timestamp, flags, hw, manufacturer, model -> callback(token) {
                                device.putAll(modelIdentification(manufacturer.takeIf { it >= 0 }, model.takeIf { it >= 0 }))
                                device["manufacturerEventTimestamp"] = timestamp
                                device["manufacturerEventFlags"] = flags.map { it.name }
                                device["hardwareRevision"] = hw.takeIf { it >= 0 }; device["informationSource"] = "SDK_MANUFACTURER_EVENT"
                                device["lastSeen"] = now()
                                event("manufacturer", "FE-C ID=$number fabricante=$manufacturer modelo=$model hardware=$hw")
                            } }
                            pcc.subscribeProductInformationEvent { timestamp, flags, sw, supplemental, serial -> callback(token) {
                                device["productEventTimestamp"] = timestamp
                                device["productEventFlags"] = flags.map { it.name }
                                device["mainSoftwareRevision"] = sw; device["supplementalSoftwareRevision"] = supplemental
                                device["serialNumber"] = serial; device["lastSeen"] = now()
                                event("product", "FE-C ID=$number software=$sw serial=$serial")
                            } }
                        }
                    } },
                    { state -> callback(token) {
                        event("fec_state", "FE-C ID=$number: $state")
                        if (state == DeviceState.DEAD) { phaseErrors = true; advance() }
                    } },
                    { _, _, type, state -> callback(token) { device["equipmentType"] = type.name; event("fec_equipment_state", "FE-C ID=$number: $type / $state") } })
            } catch (error: Exception) { fail("FE-C info", error) }
        }
        private fun beginV1() {
            if (cancelled) return
            generation++; stage = "bkool_v1"; resourcesReleased = false
            event("phase_start", "Bkool V1: PUBLIC, RF=40, período=32768, recepción en segundo plano")
            deadline(8) { phaseErrors = true; event("error", "Timeout al enlazar ANT Radio Service"); finish("error") }
            try {
                bound = operations.run("v1.bindService", mapOf("network" to "PUBLIC"), summarize = { it }) {
                    AntService.bindService(context, this)
                }
                if (!bound) throw IllegalStateException("ANT Radio Service no disponible")
            } catch (error: Exception) { fail("V1 bind", error) }
            publish()
        }
        override fun onServiceConnected(name: ComponentName, binder: IBinder) {
            val token = generation
            callback(token) {
                if (stage != "bkool_v1") return@callback
                configureV1(operations.run("v1.createAntService") { AntService(binder) }, token)
            }
        }
        private fun configureV1(ant: AntService, token: Int) {
            try {
                val provider = operations.run("v1.getChannelProvider") { ant.channelProvider }
                if (operations.run("v1.isLegacyInterfaceInUse", summarize = { it }) { provider.isLegacyInterfaceInUse }) {
                    throw IllegalStateException("Interfaz ANT legacy ocupada")
                }
                if (operations.run("v1.getNumChannelsAvailable", summarize = { it }) { provider.numChannelsAvailable } <= 0) {
                    event("v1_waiting", "Esperando canales/radio ANT disponibles")
                    main.postDelayed({ callback(token) { configureV1(ant, token) } }, 500)
                    return
                }
                val caps = Capabilities().apply { supportBackgroundScanning(!dedicated) }
                if (operations.run("v1.hasAdapterProviderSupport", summarize = { it }) { AntService.hasAdapterProviderSupport() }) {
                    val adapterProvider = operations.run("v1.getAdapterProvider") { ant.adapterProvider }
                    adapterCapabilities = operations.run("v1.getAdaptersInfo", summarize = { it }) {
                        adapterProvider.getAdaptersInfo(context).map { adapter -> mapOf(
                            "id" to adapter.adapterId.toString(), "builtIn" to adapter.isBuiltIn,
                            "version" to adapter.versionString, "capabilities" to capabilityDetails(adapter.capabilities),
                        ) }
                    }
                } else {
                    operations.skip("v1.getAdaptersInfo", "Servicio sin proveedor de adaptadores; se comprobarán las capacidades del canal reservado")
                }
                val matching = operations.run("v1.getNumChannelsAvailableWithCapabilities",
                    mapOf("requiredBackgroundScanning" to !dedicated), summarize = { it }) { provider.getNumChannelsAvailable(caps) }
                operations.run("v1.validateMatchingChannels", mapOf("matchingChannels" to matching)) {
                    if (matching <= 0) throw UnsupportedOperationException("No hay canales disponibles para el modo $mode")
                }
                val acquired = operations.run("v1.acquireChannel",
                    mapOf("network" to "PUBLIC", "requiredBackgroundScanning" to !dedicated)) {
                    provider.acquireChannel(context, PredefinedNetwork.PUBLIC, caps)
                }
                channel = acquired
                val actualCaps = operations.run("v1.getCapabilities", summarize = { capabilityDetails(it) }) { acquired.capabilities }
                channelCapabilities = capabilityDetails(actualCaps)
                if (cancelled) return
                operations.run("v1.setChannelEventHandler") { acquired.setChannelEventHandler(object : IAntChannelEventHandler {
                    override fun onChannelDeath() { transmissionAudit.died(); invalidateTargets("channel_death"); radioDead = true; channelClosed.countDown(); callback(token) { event("channel_death", "La radio/canal V1 dejó de estar disponible"); finish("channel_death") } }
                    override fun onReceiveMessage(type: MessageFromAntType, parcel: AntMessageParcel) {
                        val receivedAt = android.os.SystemClock.elapsedRealtime()
                        val id = parcel.messageId; val content = parcel.messageContent.copyOf()
                        if (type == MessageFromAntType.CHANNEL_EVENT && content.size >= 3) {
                            val code = content[2].toInt() and 255
                            transmissionAudit.observe(code) // Preserve even during drain/cleanup, when worker callbacks are ignored.
                            if (code == 1 || code == 7) {
                                radioDead = true
                                invalidateTargets(if (code == 7) "channel_closed" else "search_timeout")
                            }
                            if (code == 7) channelClosed.countDown()
                        }
                        callback(token) { receive(type.name, id, content, receivedAt) }
                    }
                }) }
                val configuration = object : V1BackgroundChannel, V1DedicatedChannel {
                    override fun assignBidirectionalSlave() { acquired.assign(ChannelType.BIDIRECTIONAL_SLAVE); assigned = true }
                    override fun setLowPrioritySearchOnly() { acquired.setSearchTimeout(com.dsi.ant.message.LowPrioritySearchTimeout.TWENTY_FIVE_SECONDS, com.dsi.ant.message.HighPrioritySearchTimeout.DISABLED) }
                    override fun assignReceiveOnlyBackground() {
                        acquired.assign(ChannelType.SLAVE_RECEIVE_ONLY, ExtendedAssignment().apply { enableBackgroundScanning() })
                        assigned = true
                    }
                    override fun setId(number: Int, type: Int, transmission: Int) {
                        acquired.setChannelId(ChannelId(number, type, transmission))
                        configuredChannelId = mapOf("deviceNumber" to number, "deviceType" to type, "transmissionType" to transmission)
                    }
                    override fun setPeriod(period: Int) { acquired.setPeriod(period) }
                    override fun setRfFrequency(rf: Int) { acquired.setRfFrequency(rf) }
                    override fun enableExtendedIdentity() {
                        val previous = operations.run("v1.getLibConfig", summarize = { libConfigDetails(it) }) { acquired.libConfig }
                        previousLibConfig = previous
                        if (!previous.enableChannelIdOutput) {
                            operations.run("v1.setAdapterWideLibConfig", mapOf("enableChannelIdOutput" to true,
                                "preserveRssi" to previous.enableRssiOutput, "preserveRxTimestamp" to previous.enableRxTimestampOutput)) {
                                acquired.setAdapterWideLibConfig(LibConfig(true, previous.enableRssiOutput, previous.enableRxTimestampOutput))
                                libConfigChanged = true
                            }
                        } else { operations.skip("v1.setAdapterWideLibConfig", "Identidad extendida ya habilitada") }
                    }
                    override fun checkBackgroundAvailable() {
                        val state = operations.run("v1.getBackgroundScanState", summarize = {
                            mapOf("configured" to it.isConfigured, "inProgress" to it.isInProgress)
                        }) { acquired.backgroundScanState }
                        operations.run("v1.validateBackgroundAvailable", mapOf("inProgress" to state.isInProgress)) {
                            if (state.isInProgress) throw IllegalStateException("Otro background scan está en marcha en el adaptador")
                        }
                    }
                    override fun open() {
                        if (cancelled) throw java.util.concurrent.CancellationException("Búsqueda cancelada antes de abrir")
                        val openStarted = android.os.SystemClock.elapsedRealtime()
                        acquired.open(); opened = true
                        transmissionAudit.opened()
                        if (training) identificationTiming.channelOpened(android.os.SystemClock.elapsedRealtime() - openStarted)
                    }
                }
                if (dedicated) configureV1Dedicated(configuration, target, actualCaps.rfFrequencyMin, actualCaps.rfFrequencyMax, operations)
                else configureV1Background(configuration, V1ChannelCapabilities(actualCaps.hasBackgroundScanning(), actualCaps.hasExtendedAssign(),
                    actualCaps.rfFrequencyMin, actualCaps.rfFrequencyMax), operations)
                if (dedicated) {
                    try {
                        adapterChannelId = operations.run("connection.requestChannelId", summarize = { it }) {
                            val value = acquired.requestChannelId().channelId
                            mapOf("deviceNumber" to value.deviceNumber, "deviceType" to value.deviceType, "transmissionType" to value.transmissionType)
                        }
                    } catch (error: Exception) {
                        identityReadbackError = antErrorDetails(error)
                        event("channel_identity_readback_error", "No se puede verificar el ID del canal; control bloqueado", error, identityReadbackError)
                        if (error is android.os.RemoteException) { radioDead = true; throw error }
                    }
                }
                event("v1_listening", "Escucha V1 activa; modo=$mode; destino=$target; control manual desactivado hasta habilitación explícita")
                if (training) {
                    phaseDeadline?.let { main.removeCallbacks(it) }; deadlineSerial++
                    scheduleTrainingTick()
                } else deadline(40) { advance() }
                publish()
            } catch (error: ChannelNotAvailableException) {
                if (error.reasonCode == ChannelNotAvailableReason.SERVICE_INITIALIZING && channel == null) {
                    event("v1_initializing", "ANT Radio Service inicializando")
                    main.postDelayed({ callback(token) { configureV1(ant, token) } }, 500)
                } else { fail("V1 configure", error) }
            }
        }
        override fun onServiceDisconnected(name: ComponentName) { radioDead = true; submit { if (!finished) { event("service_disconnected", "ANT Radio Service desconectado"); finish("radio_service_disconnected") } } }
        override fun onBindingDied(name: ComponentName) { onServiceDisconnected(name) }
        override fun onNullBinding(name: ComponentName) { onServiceDisconnected(name) }

        private fun receive(type: String, messageId: Int, content: ByteArray, receivedAt: Long) {
            val decoded = decodeAntFrame(messageId, content)
            if (training && decoded == null && messageId in listOf(0x4e, 0x4f) && content.size >= 9 &&
                (content[1].toInt() and 255) in listOf(0x50, 0x51)) {
                val payload = content.copyOfRange(1, 9)
                val details = mapOf("payloadHex" to hex(payload), "receivedAtMs" to receivedAt,
                    "reason" to "extended_identity_missing_or_invalid")
                event("identification_frame_ignored", "Página de identificación sin identidad ANT verificable", details = details)
                record("identification_frame_ignored", payload, details)
            }
            if (training && decoded != null) {
                receivedChannelId = mapOf("deviceNumber" to decoded.deviceNumber, "deviceType" to decoded.deviceType, "transmissionType" to decoded.transmissionType)
                if (!telemetry!!.accepts(decoded)) {
                    event("channel_identity_mismatch", "Paquete ajeno al rodillo seleccionado; ignorado",
                        details = receivedChannelId.orEmpty() + mapOf("payloadHex" to hex(decoded.payload), "receivedAtMs" to receivedAt))
                    return
                }
            }
            if (training && decoded != null) {
                if (!identityVerified) { identityVerified = true; event("identity_verified", "Identidad extendida recibida coincide con $target") }
                if (isScreenOff && ++screenOffFrames == 1L) recordLifecycle(mapOf(
                    "event" to "ant_received_screen_off", "receivedAtMs" to receivedAt,
                    "page" to (decoded.payload[0].toInt() and 255)))
                identificationTiming.receive(decoded, receivedAt)
                val page = telemetry!!.receive(decoded, receivedAt)
                if (page?.page == 0x10) virtualElevation?.observe(telemetry.distanceMeters, telemetry.distanceIntervalValid)
                observeBkoolPage11(decoded.payload)?.let { manual.observePage11(it, receivedAt) }
                if ((decoded.payload[0].toInt() and 255) !in listOf(0x50, 0x51)) record("page", decoded.payload)
            }
            if (frames.size >= 2000) { frames.removeFirst(); droppedFrames++ }
            frames.addLast(mapOf("timestamp" to now(), "protocol" to "BKOOL_V1_PUBLIC", "messageType" to type,
                "messageId" to messageId, "messageIdHex" to "%02X".format(messageId),
                "messageHex" to hex(byteArrayOf(messageId.toByte()) + content), "contentHex" to hex(content),
                "payloadHex" to decoded?.payload?.let { hex(it) },
                "deviceNumber" to decoded?.deviceNumber,
                "deviceType" to decoded?.deviceType, "transmissionType" to decoded?.transmissionType))
            if (decoded != null) {
                val key = "BKOOL_V1_PUBLIC:${decoded.deviceNumber}:${decoded.deviceType}:${decoded.transmissionType}"
                val device = devices.getOrPut(key) {
                    event("device_found", "ANT público ID=${decoded.deviceNumber} tipo=${decoded.deviceType} transmisión=${decoded.transmissionType}")
                    linkedMapOf("key" to key, "protocol" to "BKOOL_V1_PUBLIC",
                        "deviceNumber" to decoded.deviceNumber, "deviceType" to decoded.deviceType,
                        "transmissionType" to decoded.transmissionType, "firstSeen" to now(),
                        "bkoolV1TypeCandidate" to (decoded.deviceType == 112), "rawMessagesAvailable" to true)
                }
                device["lastSeen"] = now()
                manufacturerPage(decoded.payload)?.let { page ->
                    device.putAll(page)
                    val observation = page + mapOf("receivedAtMs" to receivedAt, "payloadHex" to hex(decoded.payload),
                        "identityVerifiedForControl" to (page["manufacturerId"] == 67 && page["modelNumber"] == 22))
                    event("information_page", "ANT ID=${decoded.deviceNumber} página=${decoded.payload[0].toInt() and 255}: $page",
                        details = observation)
                    record("information_page", decoded.payload, observation)
                }
            }
            if (type == "CHANNEL_EVENT" && content.size >= 3) {
                val code = content[2].toInt() and 255
                event("channel_event", "Evento ANT recibido: 0x%02X".format(code))
                if (code == 1 || code == 7) {
                    radioDead = true
                    phaseErrors = true
                    if (training) finish(if (code == 7) "channel_closed" else "radio_search_timeout") else advance()
                    return
                }
            }
            schedulePublish()
        }

        private fun cleanup(): Boolean {
            generation++; deadlineSerial++
            phaseDeadline?.let { main.removeCallbacks(it) }; phaseDeadline = null
            val m = multi; multi = null
            val p = fec; fec = null
            val c = channel; channel = null
            val actions = mutableListOf<() -> Unit>()
            if (m != null) actions.add { operations.run("cleanup.closeMultiDeviceSearch") { m.close() } }
            if (p != null) actions.add { operations.run("cleanup.closeFecAccess") { p.close() } }
            if (c != null) {
                if (libConfigChanged) actions.add {
                    val current = operations.run("cleanup.getLibConfig", summarize = { libConfigDetails(it) }) { c.libConfig }
                    operations.run("cleanup.restoreLibConfig", mapOf("enableChannelIdOutput" to previousLibConfig!!.enableChannelIdOutput)) {
                        c.setAdapterWideLibConfig(LibConfig(previousLibConfig!!.enableChannelIdOutput,
                            current.enableRssiOutput, current.enableRxTimestampOutput))
                    }
                }
                if (opened) actions.add {
                    if (channelClosed.count != 0L) operations.run("cleanup.closeChannel") {
                        transmissionAudit.closeRequested()
                        c.close()
                        transmissionAudit.closeApiReturned()
                    }
                    operations.run("cleanup.awaitChannelClosed", mapOf("timeoutSeconds" to 3)) {
                        if (!channelClosed.await(3, TimeUnit.SECONDS) || transmissionAudit.snapshot()["channelClosedEventAtMs"] == null)
                            throw IllegalStateException("No se confirmó CHANNEL_CLOSED en 3 s (muerte del canal no equivale al evento)")
                    }
                }
                if (assigned) actions.add { if (!opened || transmissionAudit.snapshot()["channelClosedEventAtMs"] != null) operations.run("cleanup.unassignChannel") { c.unassign() } }
                actions.add { operations.run("cleanup.releaseChannel") { c.release() } }
            }
            if (bound) actions.add { operations.run("cleanup.unbindService") { context.unbindService(this) } }
            val errors = releaseAntResources(actions)
            opened = false; assigned = false; bound = false; libConfigChanged = false
            if (errors.isNotEmpty()) cleanupFailed = true
            resourcesReleased = !cleanupFailed
            errors.forEach { event("cleanup_error", it.message ?: it.toString(), it) }
            if (m != null || p != null || c != null) event("phase_closed", "Recursos de $stage: liberados=$resourcesReleased")
            return resourcesReleased
        }
        private fun advance() {
            if (training) { finish(if (phaseErrors) "error" else "completed"); return }
            val from = stage
            if (!cleanup()) { finish("cleanup_failed"); return }
            if (cancelled) { finish("stopped"); return }
            when (from) {
                "fec_search", "fec_info" -> beginFecInfo()
                else -> finish(if (phaseErrors) "partial" else "completed")
            }
        }
        fun end(reason: String, result: MethodChannel.Result? = null) {
            if (finished) { result?.success(latest); return }
            result?.let { stopReplies.add(it) }
            finish(reason)
        }
        fun finish(reason: String) {
            if (finished || stopping) return
            stopping = true; cancelled = true
            invalidateTargets(reason)
            val zeroQueued = manual.stop(reason, allowZero = !radioDead && opened && reason != "disconnected")
            event("safe_stop", "Parada $reason; solicitud 0 % a API=$zeroQueued. Aplicación y resistencia segura SIN confirmar.")
            if (zeroQueued) stopDrainUntilMs = android.os.SystemClock.elapsedRealtime() + ManualAntControl.DRAIN_MS
            val drain = stopDrainUntilMs - android.os.SystemClock.elapsedRealtime()
            if (drain > 0) {
                status = "stopping_zero_unconfirmed"; publish()
                val task = Runnable { submit { closeAfterStop(reason) } }
                finalClose = task
                main.postDelayed(task, drain)
            } else closeAfterStop(reason)
        }
        private fun closeAfterStop(reason: String) {
            if (finished) return
            finalClose?.let { main.removeCallbacks(it) }; finalClose = null
            val clean = cleanup()
            identificationTiming.finish()
            manual.completeStop(clean)
            status = if (!clean) "cleanup_failed" else reason
            if (training) {
                if (trainingOwner != null) recordLifecycle(mapOf("event" to "service_stopping",
                    "reason" to reason, "screenOff" to isScreenOff, "antFramesWhileOff" to screenOffFrames))
                record("finished:$reason", null, mapOf("recordState" to "final", "status" to status,
                    "stopReason" to reason, "resourcesReleased" to clean, "stopResult" to manual.snapshot()["stopResult"]))
                try { csv?.close() } catch (error: Exception) { csvFailure(error) }
                csv = null
            }
            stage = "finished"; finished = true
            main.removeCallbacks(publishLater)
            event("search_finished", "Finalizado: $status; recursos liberados=$resourcesReleased")
            publish()
            if (resourcesReleased) AntRadioCoordinator.release(this)
            active = null
            main.post { trainingOwner?.finished() }
            stopReplies.forEach { it.success(snapshot()) }; stopReplies.clear()
            worker.shutdown()
        }
    }
    private fun capabilityDetails(c: Capabilities): Map<String, Any?> = mapOf(
        "backgroundScanning" to c.hasBackgroundScanning(), "extendedAssign" to c.hasExtendedAssign(),
        "rfMin" to c.rfFrequencyMin, "rfMax" to c.rfFrequencyMax,
        "rssi" to c.hasRssi(), "rxTimestamp" to c.hasRxMessageTimestamp(),
        "searchPriority" to c.hasSearchPriority(), "description" to c.toString(),
    )
    private fun libConfigDetails(c: LibConfig): Map<String, Any?> = mapOf(
        "channelId" to c.enableChannelIdOutput, "rssi" to c.enableRssiOutput,
        "rxTimestamp" to c.enableRxTimestampOutput, "flags" to (c.flagsByte.toInt() and 255),
    )
    private fun now(): String = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US).apply {
        timeZone = TimeZone.getTimeZone("UTC")
    }.format(Date())
}
