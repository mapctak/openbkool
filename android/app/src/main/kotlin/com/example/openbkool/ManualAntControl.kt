package com.example.openbkool

/** Operational policy is deliberately separate from offline protocol candidates.
 * Raising either bound requires reviewed physical transmission and stop evidence. */
internal object ManualControlPolicy {
    const val CONTINUOUS_PHYSICAL_ENABLED = false
    const val MANUAL_SESSION_PHYSICAL_ENABLED = false
    const val FULL_MIN_PERCENT = -5.0
    const val FULL_MAX_PERCENT = 15.0
    const val REFRESH_MS = 5000L
    const val MAX_PERCENT = 1.0
    const val STEP_PERCENT = 0.5
    const val MAX_DURATION_MS = 30000L
}

internal enum class ManualControlMode(val wireName: String, val maxDurationMs: Long?) {
    TRIAL("trial_30s", ManualControlPolicy.MAX_DURATION_MS),
    ISOLATED_TWO("isolated_two_percent", ManualControlPolicy.MAX_DURATION_MS),
    ISOLATED_THREE("isolated_three_percent", ManualControlPolicy.MAX_DURATION_MS),
    MANUAL_SESSION("manual_session", null),
    CONTINUOUS("continuous_experimental", null);
    val isolatedTarget: Double? get() = when(this) { ISOLATED_TWO -> 2.0; ISOLATED_THREE -> 3.0; else -> null }
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

/** Serial-worker state machine; injected transport is fake in every automated test. */
internal class ManualAntControl(
    private val target: AntTrainerIdentity,
    private val clock: () -> Long,
    private val link: () -> ManualControlLink,
    private val transport: (ByteArray, Boolean) -> Unit,
    private val emit: (Map<String, Any?>) -> Unit,
    private val continuousAllowed: Boolean = ManualControlPolicy.CONTINUOUS_PHYSICAL_ENABLED,
    private val manualSessionAllowed: Boolean = ManualControlPolicy.MANUAL_SESSION_PHYSICAL_ENABLED,
    private val describeError: (Exception) -> Map<String, Any?> = { mapOf("type" to it.javaClass.name, "message" to it.message) },
) {
    companion object { const val MAX_TEST_MS = ManualControlPolicy.MAX_DURATION_MS; const val DRAIN_MS = 1500L }
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
    private var twoPercentAttempted = false
    private var threePercentAttempted = false
    private var terminalAbort: String? = null
    private var lastSubmitted: Double? = null
    private var lastRequested: Double? = null
    private var lastApiSuccess: Map<String, Any?>? = null
    private var lastManualApiSuccess: Map<String, Any?>? = null
    private var lastStopCommand: Map<String, Any?>? = null
    private var lastApiError: Map<String, Any?>? = null
    private var lastAttemptAt: Long? = null
    private var sequence = 0
    private var attempts = 0
    private var stopResult: String? = null
    private var lastResult: Map<String, Any?>? = null
    private fun event(kind: String, fields: Map<String, Any?> = emptyMap(), result: Boolean = true): Map<String, Any?> {
        val e = mapOf("sequence" to ++sequence, "event" to kind, "monotonicMs" to clock(), "target" to target.toMap(),
            "physicalApplication" to "unconfirmed") + fields
        if (result) lastResult = e
        emit(e); return e
    }
    /** Observe from the serial worker; transitions are logged, never transmit. */
    fun supervise() {
        val failure = abortReason()
        val next = when {
            stopped && !closeComplete -> "stopping"
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
    fun enable(explicit: Boolean, requestedMode: String? = ManualControlMode.TRIAL.wireName, experimentalConfirmed: Boolean = false): Map<String, Any?> {
        val selectedMode = ManualControlMode.parse(requestedMode)
        val reason = when {
            !explicit -> "explicit_activation_required"
            selectedMode == null -> "invalid_control_mode"
            selectedMode == ManualControlMode.ISOLATED_TWO && !experimentalConfirmed -> "isolated_two_confirmation_required"
            selectedMode == ManualControlMode.ISOLATED_THREE && !experimentalConfirmed -> "isolated_three_confirmation_required"
            selectedMode == ManualControlMode.MANUAL_SESSION && !manualSessionAllowed -> "manual_session_stop_and_radio_buffer_validation_required"
            selectedMode == ManualControlMode.CONTINUOUS && !continuousAllowed -> "continuous_physical_validation_required"
            stopped || faulted -> "session_requires_reconnect"
            enabled -> "already_enabled"
            else -> link().reason(target)
        }
        if (reason != null) return event("activation_rejected", mapOf("reason" to reason))
        mode = selectedMode!!
        enabled = true; everEnabled = true; activatedAt = clock()
        deadline = mode.maxDurationMs?.let { activatedAt!! + it }
        supervise()
        return event("enabled", mapOf("mode" to mode.wireName, "maxDurationMs" to mode.maxDurationMs, "noCommandSent" to true,
            "experimentalConfirmed" to experimentalConfirmed))
    }
    fun abortReason(): String? {
        if (!enabled) return null
        if (terminalAbort == null) terminalAbort =
            if (deadline?.let { clock() >= it } == true) "test_timeout" else link().reason(target)?.let { "link_lost:$it" }
        return terminalAbort
    }
    fun request(percent: Double): Map<String, Any?> {
        attempts++
        val value = percent.takeIf { it.isFinite() }
        lastRequested = value
        event("request", mapOf("attempt" to attempts, "requestedPercent" to value))
        if (mode != ManualControlMode.MANUAL_SESSION && percent in listOf(2.0,3.0,4.0) && percent != mode.isolatedTarget) return event("rejected", mapOf(
            "reason" to "experimental_level_not_authorized", "requestedPercent" to percent,
            "attempt" to attempts, "apiCalled" to false))
        val bytes = try { when { mode == ManualControlMode.MANUAL_SESSION -> encodePro1Slope(percent); percent == mode.isolatedTarget -> encodeSlopeCandidate(percent); else -> encodeManualSlope(percent) } } catch (_: IllegalArgumentException) {
            return event("rejected", mapOf("reason" to "invalid_slope", "attempt" to attempts))
        }
        val reason = when {
            stopped || faulted -> "session_requires_reconnect"
            !enabled -> "explicit_activation_required"
            else -> abortReason()
        }
        if (reason != null) return event("rejected", mapOf("reason" to reason, "attempt" to attempts))
        if (mode == ManualControlMode.ISOLATED_TWO && percent == 2.0 && twoPercentAttempted) return event("rejected", mapOf("reason" to "isolated_two_already_attempted", "apiCalled" to false))
        if (mode == ManualControlMode.ISOLATED_THREE && percent == 3.0 && threePercentAttempted) return event("rejected", mapOf("reason" to "isolated_three_already_attempted", "apiCalled" to false))
        if (lastSubmitted == percent) return event("duplicate_skipped", mapOf("requestedPercent" to percent))
        if (lastAttemptAt?.let { clock() - it < 1000 } == true) return event("rejected", mapOf("reason" to "rate_limited"))
        if (mode == ManualControlMode.ISOLATED_TWO && percent == 2.0) twoPercentAttempted = true
        if (mode == ManualControlMode.ISOLATED_THREE && percent == 3.0) threePercentAttempted = true
        return send(percent, bytes, false)
    }
    /** Called only on the serial worker. No timer, captured payload or queue of targets.
     * A late heartbeat sends at most once using the current API-accepted goal. */
    fun refreshTarget(): Map<String, Any?>? {
        if (mode != ManualControlMode.MANUAL_SESSION || !enabled || stopped || faulted || abortReason() != null) return null
        val current = lastSubmitted ?: return null
        val previous = lastAttemptAt ?: return null
        if (clock() - previous < ManualControlPolicy.REFRESH_MS) return null
        event("periodic_refresh", mapOf("requestedPercent" to current, "intervalMs" to ManualControlPolicy.REFRESH_MS), result = false)
        return send(current, encodePro1Slope(current), false, periodic = true)
    }
    private fun send(percent: Double, bytes: ByteArray, stopping: Boolean, periodic: Boolean = false): Map<String, Any?> {
        lastAttemptAt = clock()
        val fields = mapOf("requestedPercent" to percent, "payloadHex" to hex(bytes), "stopRequest" to stopping,
            "api" to "AntChannel.setBroadcastData", "apiReturned" to false, "periodicRefresh" to periodic)
        event("api_attempt", fields)
        return try {
            transport(bytes.copyOf(), stopping)
            lastSubmitted = percent
            event("api_returned", fields + mapOf("apiReturned" to true, "apiResult" to "void_return_no_delivery_confirmation")).also { lastApiSuccess = it; if (stopping) lastStopCommand = it else lastManualApiSuccess = it }
        } catch (error: Exception) {
            faulted = true; enabled = false
            supervise()
            val details = try { describeError(error) } catch (_: Exception) { mapOf("type" to error.javaClass.name, "message" to error.message) }
            event("api_error", fields + mapOf("error" to details)).also { lastApiError = it; if (stopping) lastStopCommand = it }
        }
    }
    /** Exactly one zero attempt, only after activation and with a still usable link.
     * Force this one duplicate zero for stop; a previous void return proves no delivery.
     * Returns whether radio drain time is needed before closing. Never retries. */
    fun stop(reason: String, allowZero: Boolean): Boolean {
        if (stopped) return false
        stopped = true; enabled = false; stopReason = reason; endedAt = clock()
        supervise()
        event("stop_requested", mapOf("reason" to reason, "zeroIsNotSafeResistance" to true))
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
            if (stopped) add("session_stopped")
            if (enabled && deadline?.let { now >= it } == true) add("test_timeout")
            if (terminalAbort != null && terminalAbort != "test_timeout") add(terminalAbort!!)
            addAll(current.blockingReasons(target))
        }
        return mapOf("state" to controlState, "stopReason" to stopReason, "closeComplete" to closeComplete,
            "enabled" to enabled, "everEnabled" to everEnabled,
            "stopped" to stopped, "faulted" to faulted, "eligible" to reasons.isEmpty(),
            "unavailableReason" to reasons.firstOrNull(), "blockingReasons" to reasons,
            "link" to current.toMap(), "remainingMs" to deadline?.let { (it - now).coerceAtLeast(0) },
            "mode" to mode.wireName, "elapsedControlMs" to activatedAt?.let { (endedAt ?: now) - it },
            "maxDurationMs" to mode.maxDurationMs, "operationalMaxPercent" to (if (mode == ManualControlMode.MANUAL_SESSION) ManualControlPolicy.FULL_MAX_PERCENT else mode.isolatedTarget ?: ManualControlPolicy.MAX_PERCENT),
            "isolatedTargetPercent" to mode.isolatedTarget,
            "isolatedTargetAttempted" to (twoPercentAttempted || threePercentAttempted),
            "threePercentAttempted" to threePercentAttempted, "twoPercentAttempted" to twoPercentAttempted, "stepPercent" to ManualControlPolicy.STEP_PERCENT,
            "manualSessionPhysicalEnabled" to manualSessionAllowed,
            "periodicRefreshEnabled" to (enabled && mode == ManualControlMode.MANUAL_SESSION && !faulted && terminalAbort == null),
            "continuousControlEnabled" to continuousAllowed,
            "continuousBlockReason" to if (continuousAllowed) null else "physical_stop_and_radio_buffer_validation_required", "lastRequestedPercent" to lastRequested,
            "lastManualApiSuccess" to lastManualApiSuccess, "lastStopCommand" to lastStopCommand,
            "lastApiSuccess" to lastApiSuccess, "lastApiError" to lastApiError, "lastSubmittedPercent" to lastSubmitted,
            "attempts" to attempts, "pendingCommands" to 0, "stopResult" to stopResult,
            "lastResult" to lastResult, "physicalApplication" to "unconfirmed", "resistanceAfterClose" to "unknown")
    }
}
