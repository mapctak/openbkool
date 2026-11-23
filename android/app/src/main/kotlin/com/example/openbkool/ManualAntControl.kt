package com.example.openbkool

import java.util.concurrent.atomic.AtomicReference

internal object ManualControlPolicy {
    const val FULL_MIN_PERCENT = -5.0
    const val FULL_MAX_PERCENT = 15.0
    const val STEP_PERCENT = 0.5
    const val REFRESH_MS = 5000L
    const val MIN_COMMAND_MS = 1000L
    const val ADJUSTMENT_QUIET_MS = 180L
}

/** Full original UI range; binary compatibility is not physical validation. */
internal fun encodePro1Slope(percent: Double): ByteArray {
    require(percent.isFinite() && percent >= ManualControlPolicy.FULL_MIN_PERCENT &&
        percent <= ManualControlPolicy.FULL_MAX_PERCENT && percent * 2 == (percent * 2).toInt().toDouble())
    val grade = ((percent.toFloat() + 200.0f) * 100.0f).toInt()
    return byteArrayOf(0x33, -1, -1, -1, -1, grade.toByte(), (grade shr 8).toByte(), -1)
}

internal data class ManualControlLink(val dedicated: Boolean, val identityVerified: Boolean,
    val manufacturer: Int?, val model: Int?, val signalAgeMs: Long?, val telemetryFresh: Boolean,
    val channelOpen: Boolean = true, val radioAvailable: Boolean = true, val sessionActive: Boolean = true,
    val activeIdentityMatches: Boolean = true) {
    fun blockingReasons(target: AntTrainerIdentity): List<String> = buildList {
        if (target != AntTrainerIdentity(30064,112,5)) add("wrong_target")
        if (!dedicated) add("dedicated_channel_required")
        if (!channelOpen) add("channel_not_open")
        if (!radioAvailable) add("radio_unavailable")
        if (!sessionActive) add("session_closed")
        if (dedicated && !activeIdentityMatches) add("active_channel_identity_not_verified")
        if (!identityVerified) add("identity_not_verified")
        if (manufacturer != 67 || model != 22) add("manufacturer_model_not_verified")
        if (signalAgeMs == null || signalAgeMs < 0 || signalAgeMs >= 3000) add("signal_not_fresh")
        if (!telemetryFresh) add("telemetry_not_fresh")
    }
    fun reason(target: AntTrainerIdentity): String? = blockingReasons(target).firstOrNull()
    /** Only for a stop-zero, never for normal requests or activation. */
    fun stopReason(target: AntTrainerIdentity): String? = blockingReasons(target)
        .firstOrNull { it != "signal_not_fresh" && it != "telemetry_not_fresh" }
    fun toMap(): Map<String, Any?> = mapOf("dedicated" to dedicated, "identityVerified" to identityVerified,
        "manufacturerId" to manufacturer, "modelNumber" to model, "signalAgeMs" to signalAgeMs,
        "telemetryFresh" to telemetryFresh, "channelOpen" to channelOpen,
        "radioAvailable" to radioAvailable, "sessionActive" to sessionActive, "activeIdentityMatches" to activeIdentityMatches)

}

/** Cancellation before ANT IPC entry is not a radio error and must not suppress stop-zero. */
internal class ManualCommandCancelledException : IllegalStateException("Command cancelled before ANT API entry")

/** Serial-worker state machine; injected transport is fake in every automated test. */
internal class ManualAntControl(
    private val target: AntTrainerIdentity,
    private val clock: () -> Long,
    private val link: () -> ManualControlLink,
    private val transport: (ByteArray, Boolean) -> Unit,
    private val emit: (Map<String, Any?>) -> Unit,
    private val manualPriorityWaiting: () -> Boolean = { false },
    private val describeError: (Exception) -> Map<String, Any?> = { mapOf("type" to it.javaClass.name, "message" to it.message) },
) {
    companion object { const val DRAIN_MS = 1500L }
    private data class StopIntent(val reason: String, val requestedAtMs: Long)
    private val stopIntent = AtomicReference<StopIntent?>(null)
    private data class Desired(val percent: Double, val bytes: ByteArray, val id: Int,
        val requestedAt: Long, val requestedAtUtc: String?, val admittedAt: Long,
        val quietUntil: Long, val uiQueueMs: Long?)
    private var pendingDesired: Desired? = null
    private var lastAcceptedAt: Long? = null
    private var refreshGoal: Double? = null
    private var targetRevision = 0L
    private var commandSequence = 0L
    private var apiEnteredAtMs: Long? = null
    /** Safe from UI/SDK threads. Never waits for the serial worker or ANT IPC. */
    fun invalidateTargets(reason: String) { stopIntent.compareAndSet(null, StopIntent(reason, clock())) }
    val targetsInvalidated: Boolean get() = stopIntent.get() != null
    /** Called on the serial worker immediately before the actual SDK call, never on TX. */
    fun recordApiEntry() {
        apiEnteredAtMs = clock()
        lastAttemptAt = apiEnteredAtMs
    }
    private fun emitApiEntry(fields: Map<String, Any?>) {
        val entered = apiEnteredAtMs ?: return
        event("ant_api_entered", fields + mapOf("apiEnteredAtMs" to entered,
            "requestToApiEntryMs" to (fields["requestedAtMs"] as? Long)?.let { entered - it },
            "controllerToApiEntryMs" to (fields["admittedAtMs"] as? Long)?.let { entered - it }), result = false)
    }
    private var controlState = "inactive"
    private var stopReason: String? = null
    private var closeComplete = false
    private var closeFailed = false
    private var enabled = false
    private var everEnabled = false
    private var stopped = false
    private var faulted = false
    private var terminalAbort: String? = null
    private var lastSubmitted: Double? = null
    private var lastRequested: Double? = null
    private var lastApiSuccess: Map<String, Any?>? = null
    private var pendingObservation: Map<String, Any?>? = null
    private var lastCompatiblePage11: Map<String, Any?>? = null
    private var lastManualApiSuccess: Map<String, Any?>? = null
    private var lastStopCommand: Map<String, Any?>? = null
    private var lastApiError: Map<String, Any?>? = null
    private var lastAttemptAt: Long? = null
    private var sequence = 0
    private var attempts = 0
    private var stopResult: String? = null
    private var lastResult: Map<String, Any?>? = null
    private var lastManualRejection: Map<String, Any?>? = null
    private fun event(kind: String, fields: Map<String, Any?> = emptyMap(), result: Boolean = true): Map<String, Any?> {
        val e = mapOf("sequence" to ++sequence, "event" to kind, "monotonicMs" to clock(), "target" to target.toMap(),
            "physicalApplication" to "unconfirmed") + fields +
            (if (kind == "rejected") mapOf("requestedPercent" to lastRequested) else emptyMap())
        if (kind == "rejected") lastManualRejection = e
        if (result) lastResult = e
        emit(e); return e
    }
    /** Observe from the serial worker; transitions are logged, never transmit. */
    fun supervise() {
        val failure = abortReason()
        if (failure != null || stopped || faulted || targetsInvalidated) cancelPending(failure ?: "control_closed")
        val next = when {
            stopped && stopReason == "telemetry_not_fresh" && !closeComplete && !faulted -> "suspended"
            (stopped || stopIntent.get() != null) && !closeComplete -> "stopping"
            faulted || closeFailed || (stopped && lastManualApiSuccess != null && stopResult != null && stopResult != "zero_api_returned_unconfirmed") || (stopped && (stopReason?.startsWith("link_lost") == true || stopReason == "disconnected")) -> "error"
            stopped -> "stopped"
            enabled && failure != null -> "error"
            enabled -> "active"
            link().reason(target) == null -> "available"
            else -> "inactive"
        }
        if (next != controlState) {
            val previous = controlState
            controlState = next
            event("control_state", mapOf("from" to previous, "to" to next,
                "reason" to (if (closeFailed) "cleanup_failed" else stopReason ?: failure ?:
                    if (faulted) "api_fault_requires_reconnect" else link().reason(target) ?: "link_valid")), result = false)
        }
    }
    // A drained broadcast has no payload-level confirmation. Reuse only if no
    // slope entered ANT and the controller has never faulted.
    fun canRetainChannel() = stopped && !faulted && lastManualApiSuccess == null && terminalAbort == null

    fun completeStop(clean: Boolean) {
        closeComplete = true; closeFailed = !clean
        supervise()
    }
    fun enable(): Map<String, Any?> {
        val reason = when {
            stopped || faulted || targetsInvalidated -> "session_requires_reconnect"
            enabled -> "already_enabled"
            else -> link().reason(target)
        }
        if (reason != null) return event("activation_rejected", mapOf("reason" to reason))
        enabled = true
        everEnabled = true
        supervise()
        return event("enabled", mapOf("noCommandSent" to true,
            "minPercent" to ManualControlPolicy.FULL_MIN_PERCENT, "maxPercent" to ManualControlPolicy.FULL_MAX_PERCENT))
    }
    fun abortReason(): String? {
        if (!enabled) return null
        if (terminalAbort == null) terminalAbort = link().reason(target)?.let { "link_lost:$it" }
        return terminalAbort
    }
    fun suspendForMissingTelemetry(): Boolean {
        check(abortReason() == "link_lost:telemetry_not_fresh")
        return stop("telemetry_not_fresh", allowZero = link().stopReason(target) == null)
    }

    fun request(percent: Double, requestedAt: Long = clock(), requestedAtUtc: String? = null,
        rapidAdjustment: Boolean = false, uiQueueMs: Long? = null): Map<String, Any?> {
        attempts++
        val value = percent.takeIf { it.isFinite() }
        lastRequested = value
        val admittedAt = clock()
        val requestFields = mapOf("requestId" to attempts, "requestedPercent" to value,
            "requestedAtMs" to requestedAt, "requestedAtUtc" to requestedAtUtc,
            "uiQueueMs" to uiQueueMs, "admittedAtMs" to admittedAt,
            "nativeAdmissionMs" to admittedAt - requestedAt, "rapidAdjustment" to rapidAdjustment)
        event("request", requestFields + mapOf("attempt" to attempts))
        val bytes = try { encodePro1Slope(percent) } catch (_: IllegalArgumentException) {
            return event("rejected", requestFields + mapOf("reason" to "invalid_slope", "apiCalled" to false))
        }
        val reason = when {
            stopped || faulted || stopIntent.get() != null -> "session_requires_reconnect"
            !enabled -> "activation_required"
            else -> abortReason()
        }
        if (reason != null) return event("rejected", requestFields + mapOf("reason" to reason, "apiCalled" to false))
        if (percent != 0.0 && pendingDesired?.percent == 0.0) {
            return event("rejected", requestFields + mapOf("reason" to "flat_pending", "apiCalled" to false))
        }
        lastManualRejection = null
        // Returning to the accepted goal cancels a different deferred change too.
        if (lastSubmitted == percent && percent != 0.0) {
            cancelPending("latest_matches_accepted")
            return event("duplicate_skipped", mapOf("requestedPercent" to percent))
        }
        val previous = pendingDesired
        if (previous != null) cancelPending(if (percent == 0.0) "superseded_by_flat" else "superseded_by_manual")
        val transportDueAt = lastAttemptAt?.plus(ManualControlPolicy.MIN_COMMAND_MS) ?: 0
        // An idle step is immediate. Only work that would already have to wait
        // gets a short quiet window, where another step can replace it.
        val consolidate = rapidAdjustment && percent != 0.0 &&
            (previous != null || transportDueAt > admittedAt)
        val quietUntil = requestedAt + if (consolidate) ManualControlPolicy.ADJUSTMENT_QUIET_MS else 0L
        pendingDesired = Desired(percent, bytes, attempts, requestedAt, requestedAtUtc, admittedAt, quietUntil, uiQueueMs)
        val delay = nextManualDelayMs() ?: 0L
        if (delay > 0) return event("manual_pending", requestFields + mapOf("dueAtMs" to clock() + delay,
            "reason" to if (quietUntil >= clock() + delay) "adjustment_quiet_window" else "transport_interval", "replacesRequestId" to previous?.id, "apiCalled" to false))
        return flushPending() ?: if (pendingDesired != null && !targetsInvalidated)
            event("manual_pending", requestFields + mapOf("reason" to "newer_input_waiting", "apiCalled" to false))
            else event("command_cancelled", mapOf("apiCalled" to false, "reason" to "control_closed"))
    }
    private fun cancelPending(reason: String) {
        val pending = pendingDesired ?: return
        pendingDesired = null
        event("manual_pending_cancelled", mapOf("requestId" to pending.id, "requestedPercent" to pending.percent,
            "reason" to reason, "apiCalled" to false), result = false)
    }
    /** Only this slot is deferred; it never captures an old target in a timer. */
    fun nextManualDelayMs(): Long? {
        if (pendingDesired == null || !enabled || stopped || faulted || targetsInvalidated || abortReason() != null) return null
        return (manualDueAt(pendingDesired!!) - clock()).coerceAtLeast(0)
    }
    private fun manualDueAt(desired: Desired): Long = maxOf(desired.quietUntil,
        lastAttemptAt?.plus(ManualControlPolicy.MIN_COMMAND_MS) ?: 0L)

    fun flushPending(): Map<String, Any?>? {
        if (pendingDesired == null) return null
        if (!enabled || stopped || faulted || targetsInvalidated || abortReason() != null) {
            cancelPending(abortReason() ?: "control_closed"); return null
        }
        if (nextManualDelayMs() != 0L || manualPriorityWaiting()) return null
        val desired = pendingDesired!!
        pendingDesired = null
        return send(desired.percent, desired.bytes, false, desired = desired)
    }
    /** Manual work always wins; missed refreshes never form a catch-up queue. */
    fun refreshTarget(): Map<String, Any?>? {
        if (pendingDesired != null) return flushPending()
        if (!enabled || stopped || faulted || targetsInvalidated || abortReason() != null || manualPriorityWaiting()) return null
        val current = refreshGoal ?: return null
        val previous = lastAcceptedAt ?: return null
        if (clock() - previous < ManualControlPolicy.REFRESH_MS) return null
        event("periodic_refresh", mapOf("requestedPercent" to current, "intervalMs" to ManualControlPolicy.REFRESH_MS), result = false)
        return send(current, encodePro1Slope(current), false, periodic = true)
    }
    private fun send(percent: Double, bytes: ByteArray, stopping: Boolean, periodic: Boolean = false, desired: Desired? = null): Map<String, Any?> {
        if (!stopping && stopIntent.get() != null) return event("command_cancelled", mapOf("apiCalled" to false, "reason" to "targets_invalidated"))
        if (periodic && manualPriorityWaiting()) return event("refresh_yielded", mapOf("apiCalled" to false), result = false)
        val previousAttempt = lastAttemptAt
        lastAttemptAt = clock()
        val revision = if (stopping || periodic) targetRevision else targetRevision + 1
        val fields = mapOf("commandId" to ++commandSequence, "targetRevision" to revision,
            "requestedPercent" to percent, "payloadHex" to hex(bytes), "stopRequest" to stopping,
            "api" to "AntChannel.setBroadcastData", "apiReturned" to false, "periodicRefresh" to periodic,
            "requestId" to desired?.id, "requestedAtMs" to desired?.requestedAt,
            "requestedAtUtc" to desired?.requestedAtUtc, "admittedAtMs" to desired?.admittedAt,
            "uiQueueMs" to desired?.uiQueueMs)
        apiEnteredAtMs = null
        event("api_attempt", fields)
        return try {
            if (!stopping && stopIntent.get() != null) throw ManualCommandCancelledException()
            if (!stopping && manualPriorityWaiting()) {
                lastAttemptAt = previousAttempt
                if (!periodic) pendingDesired = desired
                return event(if (periodic) "refresh_yielded" else "manual_dispatch_yielded", fields + mapOf("apiCalled" to false), result = false)
            }
            transport(bytes.copyOf(), stopping)
            val returnedAt = clock()
            emitApiEntry(fields)
            lastSubmitted = percent
            if (!stopping) {
                refreshGoal = percent
                targetRevision = revision
                lastAcceptedAt = returnedAt
            }
            val accepted = event("api_returned", fields + mapOf(
                "apiReturned" to true, "apiReturnedAtMs" to returnedAt, "apiEnteredAtMs" to apiEnteredAtMs,
                "requestToApiEntryMs" to desired?.let { request -> apiEnteredAtMs?.minus(request.requestedAt) },
                "controllerToApiEntryMs" to desired?.let { apiEnteredAtMs?.minus(it.admittedAt) },
                "apiDurationMs" to apiEnteredAtMs?.let { returnedAt - it },
                "apiResult" to "void_return_no_delivery_confirmation",
            ))
            lastApiSuccess = accepted
            if (stopping) {
                lastStopCommand = accepted
            } else if (!periodic) {
                lastManualApiSuccess = accepted
                pendingObservation = accepted
                lastCompatiblePage11 = null
            }
            accepted
        } catch (_: ManualCommandCancelledException) {
            lastAttemptAt = previousAttempt
            event("command_cancelled", fields + mapOf("apiCalled" to false, "reason" to "targets_invalidated"))
        } catch (error: Exception) {
            val failedAt = clock()
            emitApiEntry(fields)
            faulted = true; enabled = false; refreshGoal = null
            cancelPending("api_error")
            supervise()
            val details = try { describeError(error) } catch (_: Exception) { mapOf("type" to error.javaClass.name, "message" to error.message) }
            event("api_error", fields + mapOf("apiEnteredAtMs" to apiEnteredAtMs, "apiErrorAtMs" to failedAt, "error" to details)).also { lastApiError = it; if (stopping) lastStopCommand = it }
        }
    }

    fun observePage11(observation: Map<String, Any?>, receivedAtMs: Long) {
        val command = pendingObservation ?: return
        val returnedAt = command["apiReturnedAtMs"] as Long
        val percent = command["requestedPercent"] as Double
        val payload = encodePro1Slope(percent)
        val expected = (payload[5].toInt() and 255) or ((payload[6].toInt() and 255) shl 8)
        if (receivedAtMs <= returnedAt || observation["rawWordAtBytes4And5"] != expected) return
        pendingObservation = null
        lastCompatiblePage11 = event("page11_numeric_match", observation + mapOf(
            "commandId" to command["commandId"], "requestId" to command["requestId"],
            "requestedPercent" to percent, "receivedAtMs" to receivedAtMs,
            "apiReturnToObservationMs" to receivedAtMs - returnedAt,
            "requestedAtUtc" to command["requestedAtUtc"], "uiQueueMs" to command["uiQueueMs"],
            "requestToObservationMs" to (command["requestedAtMs"] as? Long)?.let { receivedAtMs - it },
        ), result = false)
    }

    /** Exactly one zero attempt, only after activation and with a still usable link.
     * Force this one duplicate zero for stop; a previous void return proves no delivery.
     * Returns whether radio drain time is needed before closing. Never retries. */
    fun stop(reason: String, allowZero: Boolean): Boolean {
        if (stopped) return false
        invalidateTargets(reason)
        refreshGoal = null
        pendingObservation = null
        cancelPending(reason)
        stopped = true; enabled = false; stopReason = reason
        supervise()
        event("stop_requested", mapOf("reason" to reason, "zeroIsNotSafeResistance" to true,
            "stopRequestedAtMs" to stopIntent.get()?.requestedAtMs, "stopProcessedAtMs" to clock(), "targetsInvalidated" to true))
        val skip = when {
            !everEnabled -> "never_enabled"
            faulted -> "api_fault_no_retry"
            lastManualApiSuccess == null -> "no_manual_command_sent"
            !allowZero -> "link_or_channel_unavailable"
            else -> link().stopReason(target)
        }
        if (skip != null) {
            stopResult = "zero_not_requested:$skip"
            event("stop_zero_skipped", mapOf("reason" to skip)); return false
        }
        val result = send(0.0, encodePro1Slope(0.0), true)
        stopResult = if (result["event"] == "api_returned") "zero_api_returned_unconfirmed" else "zero_api_error"
        return result["event"] == "api_returned"
    }
    fun snapshot(): Map<String, Any?> {
        supervise()
        val current = link()
        val now = clock()
        val reasons = buildList {
            if (faulted) add("api_fault_requires_reconnect")
            if (stopped) add(if (stopReason == "telemetry_not_fresh") "control_suspended" else "session_stopped")
            if (!stopped && stopIntent.get() != null) add("stop_requested")
            terminalAbort?.let(::add)
            addAll(current.blockingReasons(target))
        }
        return mapOf("state" to controlState, "stopReason" to stopReason, "closeComplete" to closeComplete,
            "enabled" to enabled, "everEnabled" to everEnabled,
            "stopped" to stopped, "faulted" to faulted, "eligible" to reasons.isEmpty(),
            "unavailableReason" to reasons.firstOrNull(), "blockingReasons" to reasons,
            "link" to current.toMap(),
            "periodicRefreshEnabled" to (enabled && !faulted && terminalAbort == null && !targetsInvalidated),
            "refreshTargetPercent" to if (enabled && !faulted && stopIntent.get() == null) refreshGoal else null,
            "targetRevision" to targetRevision, "targetsInvalidated" to (stopIntent.get() != null),
            "stopRequestedAtMs" to stopIntent.get()?.requestedAtMs, "stopIntentReason" to stopIntent.get()?.reason,
            "lastRequestedPercent" to lastRequested,
            "lastManualApiSuccess" to lastManualApiSuccess, "lastCompatiblePage11" to lastCompatiblePage11, "lastStopCommand" to lastStopCommand,
            "pendingManualChange" to pendingDesired?.takeIf { enabled && !faulted && !targetsInvalidated && terminalAbort == null }?.let {
                mapOf("percent" to it.percent, "requestId" to it.id, "requestedAtMs" to it.requestedAt,
                    "dueAtMs" to manualDueAt(it),
                    "reason" to if (it.quietUntil == manualDueAt(it) && it.quietUntil > now) "adjustment_quiet_window" else "transport_interval") },
            "lastApiSuccess" to lastApiSuccess, "lastApiError" to lastApiError, "lastSubmittedPercent" to lastSubmitted,
            "attempts" to attempts, "pendingCommands" to 0, "stopResult" to stopResult,
            "lastManualRejection" to lastManualRejection,
            "lastResult" to lastResult, "physicalApplication" to "unconfirmed", "resistanceAfterClose" to "unknown")
    }
}
