package com.example.openbkool

internal data class AntTrainerIdentity(val number: Int, val type: Int, val transmission: Int) {
    init { require(number in 1..65535 && type == 112 && transmission in 1..255) { "Identidad V1 específica inválida (sin comodines)" } }
    fun matches(f: AntReceivedFrame) = number == f.deviceNumber && type == f.deviceType && transmission == f.transmissionType
    fun toMap() = mapOf("deviceNumber" to number, "deviceType" to type, "transmissionType" to transmission, "protocol" to "BKOOL_V1_PUBLIC")
}

internal interface V1DedicatedChannel {
    fun assignBidirectionalSlave()
    fun setId(number: Int, type: Int, transmission: Int)
    fun setPeriod(period: Int)
    fun setRfFrequency(rf: Int)
    fun setLowPrioritySearchOnly()
    fun enableExtendedIdentity()
    fun open()
}

/** No data-send operation exists in this configuration interface. */
internal fun configureV1Dedicated(c: V1DedicatedChannel, target: AntTrainerIdentity,
    rfMin: Int, rfMax: Int, trace: AntOperationTrace) {
    trace.run("connection.validateRf", mapOf("rfMin" to rfMin, "rfMax" to rfMax)) {
        require(40 in rfMin..rfMax) { "RF=40 no disponible" }
    }
    trace.run("connection.assign", mapOf("type" to "BIDIRECTIONAL_SLAVE", "backgroundScanning" to false)) { c.assignBidirectionalSlave() }
    trace.run("connection.setChannelId", target.toMap()) { c.setId(target.number, target.type, target.transmission) }
    trace.run("connection.setPeriod", mapOf("period" to 32768)) { c.setPeriod(32768) }
    trace.run("connection.setRfFrequency", mapOf("rf" to 40)) { c.setRfFrequency(40) }
    trace.run("connection.setSearchTimeout", mapOf("lowPrioritySeconds" to 25, "highPriority" to "DISABLED")) { c.setLowPrioritySearchOnly() }
    c.enableExtendedIdentity()
    trace.run("connection.open") { c.open() }
}

/** A dry-run plan is NOT an accepted command. There is deliberately no radio transport here. */
internal class ManualSlopePreparation(private val target: AntTrainerIdentity) {
    private var connected = false
    private var stopped = false
    private var lastRequest: Int? = null
    private var lastAt: Long? = null
    var lastResult: Map<String, Any?>? = null; private set
    fun connectionVerified(value: Boolean) { connected = value && !stopped }
    fun stop() { stopped = true; connected = false; lastRequest = null; lastAt = null }
    fun prepare(percent: Double, nowMs: Long): Map<String, Any?> {
        val reason = when {
            !percent.isFinite() || percent < 0 || percent > 1 -> "invalid_range"
            kotlin.math.abs(percent * 100 - Math.round(percent * 100)) > 0.000001 -> "unsupported_precision"
            stopped -> "session_stopped"
            !connected -> "not_connected"
            lastRequest == Math.round(percent * 100).toInt() -> "duplicate"
            lastAt?.let { nowMs - it < 1000 } == true -> "rate_limited"
            else -> "transmission_disabled"
        }
        val validPlan = reason == "transmission_disabled"
        // Deliberately restricted to integral hundredths, no out-of-range wrap or truncation.
        val hundredths = if (percent.isFinite() && percent in 0.0..1.0) Math.round(percent * 100).toInt() else null
        val payload = if (validPlan) {
            val grade = 20000 + hundredths!!
            hex(byteArrayOf(0x33, -1, -1, -1, -1, (grade and 255).toByte(), (grade shr 8).toByte(), -1))
        } else null
        if (validPlan) { lastRequest = hundredths; lastAt = nowMs }
        return mapOf("state" to reason, "requestedPercent" to percent.takeIf { it.isFinite() },
            "quantizedPercent" to hundredths?.div(100.0), "candidatePayloadHex" to payload,
            "sent" to false, "transmissionEnabled" to false, "target" to target.toMap()).also { lastResult = it }
    }
    fun snapshot(): Map<String, Any?> = mapOf("transmissionEnabled" to false, "connectedIdentityVerified" to connected,
        "pendingCommands" to 0, "stopPolicy" to "cancel_and_close_without_reset", "resistanceAfterClose" to "unknown", "lastPreparation" to lastResult)
}

/** Every identity must be exact, including transmission type; wildcards are not proof. */
internal fun channelIdentitiesMatch(target: AntTrainerIdentity, configured: Map<String, Any?>?,
    adapter: Map<String, Any?>?, received: Map<String, Any?>?): Boolean =
    listOf(configured, adapter, received).all {
        it != null && it["deviceNumber"] == target.number && it["deviceType"] == target.type && it["transmissionType"] == target.transmission
    }
