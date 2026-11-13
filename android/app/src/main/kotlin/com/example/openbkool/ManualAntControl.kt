package com.example.openbkool

/** Only the three values supported by the first physical experiment. No Float truncation. */
internal fun encodeManualSlope(percent: Double): ByteArray {
    require(percent.isFinite() && percent in listOf(0.0, 0.5, 1.0)) { "Solo 0 %, 0,5 % o 1 %" }
    val grade = 20000 + (percent * 100).toInt()
    return byteArrayOf(0x33, -1, -1, -1, -1, grade.toByte(), (grade shr 8).toByte(), -1)
}

internal data class ManualControlLink(val dedicated: Boolean, val identityVerified: Boolean,
    val manufacturer: Int?, val model: Int?, val signalAgeMs: Long?, val telemetryFresh: Boolean) {
    fun reason(target: AntTrainerIdentity): String? = when {
        target != AntTrainerIdentity(30064,112,5) -> "wrong_target"
        !dedicated || !identityVerified -> "dedicated_identity_required"
        manufacturer != 67 || model != 22 -> "manufacturer_model_not_verified"
        signalAgeMs == null || signalAgeMs < 0 || signalAgeMs >= 3000 -> "signal_not_fresh"
        !telemetryFresh -> "telemetry_not_fresh"
        else -> null
    }
}

/** Serial-worker state machine; injected transport is fake in every automated test. */
internal class ManualAntControl(
    private val target: AntTrainerIdentity,
    private val clock: () -> Long,
    private val link: () -> ManualControlLink,
    private val transport: (ByteArray, Boolean) -> Unit,
    private val emit: (Map<String, Any?>) -> Unit,
    private val describeError: (Exception) -> Map<String, Any?> = { mapOf("type" to it.javaClass.name, "message" to it.message) },
) {
    companion object { const val MAX_TEST_MS = 30000L; const val DRAIN_MS = 1500L }
    private var enabled = false
    private var everEnabled = false
    private var stopped = false
    private var faulted = false
    private var deadline: Long? = null
    private var lastSubmitted: Double? = null
    private var lastAttemptAt: Long? = null
    private var sequence = 0
    private var attempts = 0
    private var stopResult: String? = null
    private var lastResult: Map<String, Any?>? = null
    private fun event(kind: String, fields: Map<String, Any?> = emptyMap()): Map<String, Any?> {
        val e = mapOf("sequence" to ++sequence, "event" to kind, "monotonicMs" to clock(), "target" to target.toMap(),
            "physicalApplication" to "unconfirmed") + fields
        lastResult = e; emit(e); return e
    }
    fun enable(explicit: Boolean): Map<String, Any?> {
        val reason = when {
            !explicit -> "explicit_activation_required"
            stopped || faulted -> "session_requires_reconnect"
            enabled -> "already_enabled"
            else -> link().reason(target)
        }
        if (reason != null) return event("activation_rejected", mapOf("reason" to reason))
        enabled = true; everEnabled = true; deadline = clock() + MAX_TEST_MS
        return event("enabled", mapOf("maxDurationMs" to MAX_TEST_MS, "noCommandSent" to true))
    }
    fun abortReason(): String? = if (!enabled) null else
        if (clock() >= deadline!!) "test_timeout" else link().reason(target)?.let { "link_lost:$it" }
    fun request(percent: Double): Map<String, Any?> {
        attempts++
        val value = percent.takeIf { it.isFinite() }
        event("request", mapOf("attempt" to attempts, "requestedPercent" to value))
        val bytes = try { encodeManualSlope(percent) } catch (_: IllegalArgumentException) {
            return event("rejected", mapOf("reason" to "invalid_slope", "attempt" to attempts))
        }
        val reason = when {
            stopped || faulted -> "session_requires_reconnect"
            !enabled -> "explicit_activation_required"
            else -> abortReason()
        }
        if (reason != null) return event("rejected", mapOf("reason" to reason, "attempt" to attempts))
        if (lastSubmitted == percent) return event("duplicate_skipped", mapOf("requestedPercent" to percent))
        if (lastAttemptAt?.let { clock() - it < 1000 } == true) return event("rejected", mapOf("reason" to "rate_limited"))
        return send(percent, bytes, false)
    }
    private fun send(percent: Double, bytes: ByteArray, stopping: Boolean): Map<String, Any?> {
        lastAttemptAt = clock()
        val fields = mapOf("requestedPercent" to percent, "payloadHex" to hex(bytes), "stopRequest" to stopping,
            "api" to "AntChannel.setBroadcastData", "apiReturned" to false)
        event("api_attempt", fields)
        return try {
            transport(bytes.copyOf(), stopping)
            lastSubmitted = percent
            event("api_returned", fields + mapOf("apiReturned" to true, "apiResult" to "void_return_no_delivery_confirmation"))
        } catch (error: Exception) {
            faulted = true; enabled = false
            val details = try { describeError(error) } catch (_: Exception) { mapOf("type" to error.javaClass.name, "message" to error.message) }
            event("api_error", fields + mapOf("error" to details))
        }
    }
    /** Exactly one zero attempt, only after activation and with a still usable link.
     * Force this one duplicate zero for stop; a previous void return proves no delivery.
     * Returns whether radio drain time is needed before closing. Never retries. */
    fun stop(reason: String, allowZero: Boolean): Boolean {
        if (stopped) return false
        stopped = true; enabled = false
        event("stop_requested", mapOf("reason" to reason, "zeroIsNotSafeResistance" to true))
        val skip = when {
            !everEnabled -> "never_enabled"
            faulted -> "api_fault_no_retry"
            !allowZero -> "link_or_channel_unavailable"
            else -> link().reason(target)
        }
        if (skip != null) {
            stopResult = "zero_not_requested:$skip"
            event("stop_zero_skipped", mapOf("reason" to skip)); return false
        }
        val result = send(0.0, encodeManualSlope(0.0), true)
        stopResult = if (result["event"] == "api_returned") "zero_api_returned_unconfirmed" else "zero_api_error"
        return result["event"] == "api_returned"
    }
    fun snapshot(): Map<String, Any?> = mapOf("enabled" to enabled, "everEnabled" to everEnabled,
        "stopped" to stopped, "faulted" to faulted, "eligible" to (link().reason(target) == null && !stopped && !faulted),
        "unavailableReason" to link().reason(target), "remainingMs" to deadline?.let { (it - clock()).coerceAtLeast(0) },
        "maxDurationMs" to MAX_TEST_MS, "lastSubmittedPercent" to lastSubmitted,
        "attempts" to attempts, "pendingCommands" to 0, "stopResult" to stopResult,
        "lastResult" to lastResult, "physicalApplication" to "unconfirmed", "resistanceAfterClose" to "unknown")
}
