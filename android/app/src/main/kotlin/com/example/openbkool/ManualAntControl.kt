package com.example.openbkool

import java.util.concurrent.atomic.AtomicReference

/** Operational policy is deliberately separate from offline protocol candidates.
 * Raising either bound requires reviewed physical transmission and stop evidence. */
internal object ManualControlPolicy {
    const val CONTINUOUS_PHYSICAL_ENABLED = false
    const val MANUAL_SESSION_PHYSICAL_ENABLED = true
    const val FULL_MIN_PERCENT = -5.0
    const val FULL_MAX_PERCENT = 15.0
    const val REFRESH_MS = 5000L
    const val MIN_COMMAND_MS = 1000L
    const val REFRESH_TRIAL_PHYSICAL_ENABLED = true
    const val LOW_LOAD_PHYSICAL_ENABLED = true
    const val MAX_PERCENT = 1.0
    const val STEP_PERCENT = 0.5
    const val MAX_DURATION_MS = 30000L
}

internal enum class ManualControlMode(val wireName: String, val maxDurationMs: Long?) {
    TRIAL("trial_30s", ManualControlPolicy.MAX_DURATION_MS),
    ISOLATED_TWO("isolated_two_percent", ManualControlPolicy.MAX_DURATION_MS),
    ISOLATED_THREE("isolated_three_percent", ManualControlPolicy.MAX_DURATION_MS),
    REFRESH_TRIAL("refresh_trial_30s", ManualControlPolicy.MAX_DURATION_MS),
    LOW_LOAD("manual_low_load", null),
    MANUAL_SESSION("manual_session", null),
    CONTINUOUS("continuous_experimental", null);
    val refreshes: Boolean get() = this == MANUAL_SESSION || this == REFRESH_TRIAL || this == LOW_LOAD
    val isolatedTarget: Double? get() = when(this) { ISOLATED_TWO -> 2.0; ISOLATED_THREE -> 3.0; else -> null }
    companion object { fun parse(value: String?) = entries.firstOrNull { it.wireName == value } }
}

/** Per-session authorization, not a claim that every value was physically measured. */
internal enum class ManualRangeProfile(val wireName: String, val min: Double, val max: Double) {
    LOW("low", 0.0, 0.5), REPORTED("reported", 0.0, 3.0), ORIGINAL("original", -5.0, 15.0);
    fun accepts(percent: Double) = percent.isFinite() && percent in min..max && percent * 2 == (percent * 2).toInt().toDouble()
    fun toMap(): Map<String, Any?> = mapOf("id" to wireName, "minPercent" to min, "maxPercent" to max,
        "stepPercent" to 0.5, "experimental" to true, "allValuesPhysicallyValidated" to false)
    companion object { fun parse(value: String?) = entries.firstOrNull { it.wireName == value } }
}

/** Only the three values supported by the first physical experiment. No Float truncation. */
internal fun encodeManualSlope(percent: Double): ByteArray {
    require(percent.isFinite() && percent >= 0 && percent <= ManualControlPolicy.MAX_PERCENT &&
        percent / ManualControlPolicy.STEP_PERCENT == (percent / ManualControlPolicy.STEP_PERCENT).toInt().toDouble()) { "Solo 0 %, 0,5 % o 1 %" }
    return encodeSlopeCandidate(percent)
}

/** Full original UI range; binary compatibility is not physical validation. */
internal fun encodePro1Slope(percent: Double): ByteArray {
    require(percent.isFinite() && percent >= ManualControlPolicy.FULL_MIN_PERCENT &&
        percent <= ManualControlPolicy.FULL_MAX_PERCENT && percent * 2 == (percent * 2).toInt().toDouble())
    val grade = ((percent.toFloat() + 200.0f) * 100.0f).toInt()
    return byteArrayOf(0x33, -1, -1, -1, -1, grade.toByte(), (grade shr 8).toByte(), -1)
}

/** Offline candidates 0..4 only. Representability does not authorize physical use. */
internal fun encodeSlopeCandidate(percent: Double): ByteArray {
    require(percent.isFinite() && percent >= 0 && percent <= 4 && percent * 2 == (percent * 2).toInt().toDouble())
    return encodePro1Slope(percent)
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
    private val continuousAllowed: Boolean = ManualControlPolicy.CONTINUOUS_PHYSICAL_ENABLED,
    private val manualSessionAllowed: Boolean = ManualControlPolicy.MANUAL_SESSION_PHYSICAL_ENABLED,
    private val manualPriorityWaiting: () -> Boolean = { false },
    private val describeError: (Exception) -> Map<String, Any?> = { mapOf("type" to it.javaClass.name, "message" to it.message) },
) {
    companion object { const val MAX_TEST_MS = ManualControlPolicy.MAX_DURATION_MS; const val DRAIN_MS = 1500L }
    private data class StopIntent(val reason: String, val requestedAtMs: Long)
    private val stopIntent = AtomicReference<StopIntent?>(null)
    private data class Desired(val percent: Double, val bytes: ByteArray, val id: Int, val requestedAt: Long, val requestedAtUtc: String?)
    private var pendingDesired: Desired? = null
    private var acceptedDesired: Desired? = null
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
            "requestToApiEntryMs" to (fields["requestedAtMs"] as? Long)?.let { entered - it }), result = false)
    }
    private var controlState = "inactive"
    private var stopReason: String? = null
    private var closeComplete = false
    private var closeFailed = false
    private var enabled = false
    private var everEnabled = false
    private var stopped = false
    private var faulted = false
    private var deadline: Long? = null
    private var activatedAt: Long? = null
    private var endedAt: Long? = null
    private var mode = ManualControlMode.TRIAL
    private var authorizedRange: ManualRangeProfile? = null
    private var twoPercentAttempted = false
    private var threePercentAttempted = false
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
            faulted || closeFailed || (stopped && everEnabled && stopResult != null && stopResult != "zero_api_returned_unconfirmed") || (stopped && (stopReason?.startsWith("link_lost") == true || stopReason == "disconnected")) -> "error"
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
    fun completeStop(clean: Boolean) {
        closeComplete = true; closeFailed = !clean
        supervise()
    }
    fun enable(explicit: Boolean, requestedMode: String? = ManualControlMode.TRIAL.wireName, experimentalConfirmed: Boolean = false, rangeProfile: String? = null): Map<String, Any?> {
        val selectedRange = ManualRangeProfile.parse(rangeProfile)
        val selectedMode = ManualControlMode.parse(requestedMode)
        val reason = when {
            !explicit -> "explicit_activation_required"
            selectedMode == null -> "invalid_control_mode"
            selectedMode == ManualControlMode.ISOLATED_TWO && !experimentalConfirmed -> "isolated_two_confirmation_required"
            selectedMode == ManualControlMode.ISOLATED_THREE && !experimentalConfirmed -> "isolated_three_confirmation_required"
            selectedMode == ManualControlMode.REFRESH_TRIAL && !experimentalConfirmed -> "refresh_trial_confirmation_required"
            selectedMode == ManualControlMode.REFRESH_TRIAL && !ManualControlPolicy.REFRESH_TRIAL_PHYSICAL_ENABLED -> "refresh_trial_disabled"
            selectedMode == ManualControlMode.LOW_LOAD && !experimentalConfirmed -> "low_load_risk_consent_required"
            selectedMode == ManualControlMode.LOW_LOAD && !ManualControlPolicy.LOW_LOAD_PHYSICAL_ENABLED -> "low_load_disabled"
            selectedMode == ManualControlMode.MANUAL_SESSION && !manualSessionAllowed -> "manual_session_stop_and_radio_buffer_validation_required"
            selectedMode == ManualControlMode.MANUAL_SESSION && !experimentalConfirmed -> "manual_range_risk_consent_required"
            selectedMode == ManualControlMode.MANUAL_SESSION && selectedRange == null -> "manual_range_profile_required"
            selectedMode == ManualControlMode.CONTINUOUS && !continuousAllowed -> "continuous_physical_validation_required"
            stopped || faulted || stopIntent.get() != null -> "session_requires_reconnect"
            enabled -> "already_enabled"
            else -> link().reason(target)
        }
        if (reason != null) return event("activation_rejected", mapOf("reason" to reason))
        mode = selectedMode!!
        authorizedRange = if (mode == ManualControlMode.MANUAL_SESSION) selectedRange else null
        enabled = true; everEnabled = true; activatedAt = clock()
        deadline = mode.maxDurationMs?.let { activatedAt!! + it }
        supervise()
        return event("enabled", mapOf("mode" to mode.wireName, "maxDurationMs" to mode.maxDurationMs, "noCommandSent" to true,
            "experimentalConfirmed" to experimentalConfirmed, "authorizedRange" to authorizedRange?.toMap()))
    }
    fun abortReason(): String? {
        if (!enabled) return null
        if (terminalAbort == null) terminalAbort =
            if (deadline?.let { clock() >= it } == true) "test_timeout" else link().reason(target)?.let { "link_lost:$it" }
        return terminalAbort
    }
    fun suspendForMissingTelemetry(): Boolean {
        check(abortReason() == "link_lost:telemetry_not_fresh")
        return stop("telemetry_not_fresh", allowZero = link().stopReason(target) == null)
    }

    fun request(percent: Double, requestedAt: Long = clock(), requestedAtUtc: String? = null): Map<String, Any?> {
        attempts++
        val value = percent.takeIf { it.isFinite() }
        lastRequested = value
        val requestFields = mapOf("requestId" to attempts, "requestedPercent" to value,
            "requestedAtMs" to requestedAt, "requestedAtUtc" to requestedAtUtc)
        event("request", requestFields + mapOf("attempt" to attempts))
        if (mode == ManualControlMode.MANUAL_SESSION && authorizedRange?.accepts(percent) != true)
            return event("rejected", mapOf("reason" to "slope_outside_authorized_profile", "authorizedRange" to authorizedRange?.toMap(), "apiCalled" to false))
        if ((mode == ManualControlMode.REFRESH_TRIAL || mode == ManualControlMode.LOW_LOAD) && percent != 0.0 && percent != 0.5)
            return event("rejected", mapOf("reason" to if (mode == ManualControlMode.LOW_LOAD) "low_load_only_zero_or_half" else "refresh_trial_only_zero_or_half", "apiCalled" to false))
        if (mode != ManualControlMode.MANUAL_SESSION && percent in listOf(2.0,3.0,4.0) && percent != mode.isolatedTarget) return event("rejected", mapOf(
            "reason" to "experimental_level_not_authorized", "requestedPercent" to percent,
            "attempt" to attempts, "apiCalled" to false))
        val bytes = try { when { mode == ManualControlMode.MANUAL_SESSION -> encodePro1Slope(percent); percent == mode.isolatedTarget -> encodeSlopeCandidate(percent); else -> encodeManualSlope(percent) } } catch (_: IllegalArgumentException) {
            return event("rejected", mapOf("reason" to "invalid_slope", "attempt" to attempts))
        }
        val reason = when {
            stopped || faulted || stopIntent.get() != null -> "session_requires_reconnect"
            !enabled -> "explicit_activation_required"
            else -> abortReason()
        }
        if (reason != null) return event("rejected", mapOf("reason" to reason, "attempt" to attempts))
        if (mode == ManualControlMode.ISOLATED_TWO && percent == 2.0 && twoPercentAttempted) return event("rejected", mapOf("reason" to "isolated_two_already_attempted", "apiCalled" to false))
        if (mode == ManualControlMode.ISOLATED_THREE && percent == 3.0 && threePercentAttempted) return event("rejected", mapOf("reason" to "isolated_three_already_attempted", "apiCalled" to false))
        lastManualRejection = null
        // Returning to the accepted goal cancels a different deferred change too.
        if (lastSubmitted == percent) {
            cancelPending("latest_matches_accepted")
            return event("duplicate_skipped", mapOf("requestedPercent" to percent))
        }
        val previous = pendingDesired
        pendingDesired = Desired(percent, bytes, attempts, requestedAt, requestedAtUtc)
        val delay = nextManualDelayMs() ?: 0L
        if (delay > 0) return event("manual_pending", requestFields + mapOf("dueAtMs" to clock() + delay,
            "reason" to "transport_interval", "replacesRequestId" to previous?.id, "apiCalled" to false))
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
        return lastAttemptAt?.let { (it + ManualControlPolicy.MIN_COMMAND_MS - clock()).coerceAtLeast(0) } ?: 0L
    }
    fun flushPending(): Map<String, Any?>? {
        if (pendingDesired == null) return null
        if (!enabled || stopped || faulted || targetsInvalidated || abortReason() != null) {
            cancelPending(abortReason() ?: "control_closed"); return null
        }
        if (nextManualDelayMs() != 0L || manualPriorityWaiting()) return null
        val desired = pendingDesired!!
        // Profile and connection are rechecked immediately before deferred emission.
        if (mode == ManualControlMode.MANUAL_SESSION && authorizedRange?.accepts(desired.percent) != true) {
            cancelPending("profile_not_authorized"); return null
        }
        pendingDesired = null
        if (mode == ManualControlMode.ISOLATED_TWO && desired.percent == 2.0) twoPercentAttempted = true
        if (mode == ManualControlMode.ISOLATED_THREE && desired.percent == 3.0) threePercentAttempted = true
        return send(desired.percent, desired.bytes, false, desired = desired)
    }
    /** Manual work always wins; missed refreshes never form a catch-up queue. */
    fun refreshTarget(): Map<String, Any?>? {
        if (pendingDesired != null) return flushPending()
        if (!mode.refreshes || !enabled || stopped || faulted || targetsInvalidated || abortReason() != null || manualPriorityWaiting()) return null
        val current = refreshGoal ?: return null
        val previous = lastAcceptedAt ?: return null
        if (clock() - previous < ManualControlPolicy.REFRESH_MS) return null
        event("periodic_refresh", mapOf("requestedPercent" to current, "intervalMs" to ManualControlPolicy.REFRESH_MS), result = false)
        return send(current, encodePro1Slope(current), false, periodic = true, desired = acceptedDesired)
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
            "requestId" to desired?.id, "requestedAtMs" to desired?.requestedAt, "requestedAtUtc" to desired?.requestedAtUtc)
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
                acceptedDesired = desired
                lastAcceptedAt = returnedAt
            }
            val accepted = event("api_returned", fields + mapOf(
                "apiReturned" to true, "apiReturnedAtMs" to returnedAt, "apiEnteredAtMs" to apiEnteredAtMs,
                "requestToApiEntryMs" to desired?.let { request -> apiEnteredAtMs?.minus(request.requestedAt) },
                "apiDurationMs" to apiEnteredAtMs?.let { returnedAt - it },
                "apiResult" to "void_return_no_delivery_confirmation",
            ))
            lastApiSuccess = accepted
            if (stopping) {
                lastStopCommand = accepted
            } else {
                lastManualApiSuccess = accepted
                if (!periodic) {
                    pendingObservation = accepted
                    lastCompatiblePage11 = null
                }
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
            "requestedAtUtc" to command["requestedAtUtc"],
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
        stopped = true; enabled = false; stopReason = reason; endedAt = clock()
        supervise()
        event("stop_requested", mapOf("reason" to reason, "zeroIsNotSafeResistance" to true,
            "stopRequestedAtMs" to stopIntent.get()?.requestedAtMs, "stopProcessedAtMs" to clock(), "targetsInvalidated" to true))
        val skip = when {
            !everEnabled -> "never_enabled"
            faulted -> "api_fault_no_retry"
            !allowZero -> "link_or_channel_unavailable"
            else -> link().stopReason(target)
        }
        if (skip != null) {
            stopResult = "zero_not_requested:$skip"
            event("stop_zero_skipped", mapOf("reason" to skip)); return false
        }
        val result = send(0.0, encodeManualSlope(0.0), true)
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
            if (enabled && deadline?.let { now >= it } == true) add("test_timeout")
            if (terminalAbort != null && terminalAbort != "test_timeout") add(terminalAbort!!)
            addAll(current.blockingReasons(target))
        }
        return mapOf("state" to controlState, "stopReason" to stopReason, "closeComplete" to closeComplete,
            "enabled" to enabled, "everEnabled" to everEnabled,
            "stopped" to stopped, "faulted" to faulted, "eligible" to reasons.isEmpty(),
            "unavailableReason" to reasons.firstOrNull(), "blockingReasons" to reasons,
            "link" to current.toMap(), "remainingMs" to deadline?.let { (it - now).coerceAtLeast(0) },
            "authorizedRange" to authorizedRange?.toMap(),
            "operationalMinPercent" to (authorizedRange?.min ?: 0.0),
            "mode" to mode.wireName, "elapsedControlMs" to activatedAt?.let { (endedAt ?: now) - it },
            "maxDurationMs" to mode.maxDurationMs, "operationalMaxPercent" to (if (mode == ManualControlMode.MANUAL_SESSION) authorizedRange?.max else if (mode == ManualControlMode.REFRESH_TRIAL || mode == ManualControlMode.LOW_LOAD) 0.5 else mode.isolatedTarget ?: ManualControlPolicy.MAX_PERCENT),
            "isolatedTargetPercent" to mode.isolatedTarget,
            "isolatedTargetAttempted" to (twoPercentAttempted || threePercentAttempted),
            "threePercentAttempted" to threePercentAttempted, "twoPercentAttempted" to twoPercentAttempted, "stepPercent" to ManualControlPolicy.STEP_PERCENT,
            "lowLoadPhysicalEnabled" to ManualControlPolicy.LOW_LOAD_PHYSICAL_ENABLED,
            "manualSessionPhysicalEnabled" to manualSessionAllowed,
            "periodicRefreshEnabled" to (enabled && mode.refreshes && !faulted && terminalAbort == null && stopIntent.get() == null),
            "refreshTargetPercent" to if (enabled && !faulted && stopIntent.get() == null) refreshGoal else null,
            "targetRevision" to targetRevision, "targetsInvalidated" to (stopIntent.get() != null),
            "stopRequestedAtMs" to stopIntent.get()?.requestedAtMs, "stopIntentReason" to stopIntent.get()?.reason,
            "continuousControlEnabled" to continuousAllowed,
            "continuousBlockReason" to if (continuousAllowed) null else "physical_stop_and_radio_buffer_validation_required", "lastRequestedPercent" to lastRequested,
            "lastManualApiSuccess" to lastManualApiSuccess, "lastCompatiblePage11" to lastCompatiblePage11, "lastStopCommand" to lastStopCommand,
            "pendingManualChange" to pendingDesired?.takeIf { enabled && !faulted && !targetsInvalidated && terminalAbort == null }?.let {
                mapOf("percent" to it.percent, "requestId" to it.id, "requestedAtMs" to it.requestedAt,
                    "dueAtMs" to (lastAttemptAt?.plus(ManualControlPolicy.MIN_COMMAND_MS) ?: now), "reason" to "transport_interval") },
            "lastApiSuccess" to lastApiSuccess, "lastApiError" to lastApiError, "lastSubmittedPercent" to lastSubmitted,
            "attempts" to attempts, "pendingCommands" to 0, "stopResult" to stopResult,
            "lastManualRejection" to lastManualRejection,
            "lastResult" to lastResult, "physicalApplication" to "unconfirmed", "resistanceAfterClose" to "unknown")
    }
}
