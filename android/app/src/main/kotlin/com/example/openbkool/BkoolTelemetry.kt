package com.example.openbkool

/** Decoder puro. Índices del payload ANT de ocho bytes, sin cabecera/ID extendido. */
internal data class BkoolPage(val page: Int, val speedKmh: Double? = null,
    val distanceCounter: Int? = null, val powerW: Int? = null, val cadenceRpm: Int? = null)

/** Pro1 ignores 0x11. Preserve bytes, never call its unverified word an applied grade. */
internal fun observeBkoolPage11(payload: ByteArray): Map<String, Any?>? {
    if (payload.size != 8 || (payload[0].toInt() and 255) != 0x11) return null
    val word = (payload[4].toInt() and 255) or ((payload[5].toInt() and 255) shl 8)
    return mapOf("page" to 0x11, "payloadHex" to hex(payload), "rawWordAtBytes4And5" to word,
        "rawBytes4And5Hex" to hex(payload.copyOfRange(4,6)),
        "interpretation" to "raw_only_semantics_unverified_for_bkool_v1",
        "commandAcknowledgement" to false, "mechanicalConfirmation" to false)
}

internal fun decodeBkoolPage(payload: ByteArray): BkoolPage? {
    if (payload.size != 8) return null
    fun u(i: Int) = payload[i].toInt() and 255
    return when (u(0)) {
        0x10 -> {
            val speed = u(4) or (u(5) shl 8)
            BkoolPage(0x10, speed.takeUnless { it == 65535 }?.times(0.0036), u(3))
        }
        0x19 -> {
            val power = u(5) or ((u(6) and 15) shl 8)
            BkoolPage(0x19, powerW = power.takeUnless { it == 4095 },
                cadenceRpm = u(2).takeUnless { it == 255 })
        }
        else -> null
    }
}

internal class BkoolTelemetry(private val startedMs: Long,
    private val target: AntTrainerIdentity = AntTrainerIdentity(30064, 112, 5)) {
    companion object { const val SIGNAL_LOST_MS = 5000L }

    var lastReceivedMs: Long? = null; private set
    private var speedAt: Long? = null
    private var powerAt: Long? = null
    private var speed: Double? = null
    private var power: Int? = null
    private var cadence: Int? = null
    private var counter: Int? = null
    private var distanceAt: Long? = null
    var distanceMeters = 0L; private set
    var distanceIntervalValid = false; private set
    private var partial = false
    private var signalLost = false
    private var page11: Map<String, Any?>? = null
    private var page11At: Long? = null
    fun accepts(f: AntReceivedFrame) = target.matches(f)
    fun receive(frame: AntReceivedFrame, ms: Long): BkoolPage? {
        if (!accepts(frame)) return null
        observeBkoolPage11(frame.payload)?.let { page11 = it; page11At = ms }
        if (lastReceivedMs?.let { ms - it >= SIGNAL_LOST_MS } == true) loseSignal()
        lastReceivedMs = ms
        signalLost = false
        val p = decodeBkoolPage(frame.payload) ?: return null
        when (p.page) {
            0x10 -> {
                speed = p.speedKmh; speedAt = ms
                distanceIntervalValid = false
                val next = p.distanceCounter!!
                // Never invent complete turns of the counter or distance before this session.
                if (counter != null) {
                    val delta = (next - counter!! + 256) % 256
                    val gap = ms - distanceAt!!
                    if (gap >= 10000 || delta > 65.534 * (gap / 1000.0 + 1) + 2) {
                        partial = true // gap/reset cannot be reconstructed safely
                    } else {
                        distanceMeters += delta
                        distanceIntervalValid = p.speedKmh != null && 65.534 * gap / 1000 < 256
                        // More than one turn is theoretically possible at the max valid speed.
                        if (65.534 * gap / 1000 >= 256) partial = true
                    }
                }
                counter = next; distanceAt = ms
            }
            0x19 -> { power = p.powerW; cadence = p.cadenceRpm; powerAt = ms }
        }
        return p
    }
    private fun loseSignal() { signalLost = true; counter = null; partial = true; speed = null; power = null; cadence = null }
    fun signal(ms: Long): String {
        val age = ms - (lastReceivedMs ?: startedMs)
        if (lastReceivedMs == null) return if (age >= 30000) "disconnected" else "waiting"
        if (age >= SIGNAL_LOST_MS) loseSignal()
        return if (age >= 15000) "disconnected" else if (signalLost) "signal_lost" else "receiving"
    }
    fun snapshot(ms: Long): Map<String, Any?> {
        val state = signal(ms)
        val freshSpeed = state == "receiving" && speedAt?.let { ms - it < 10000 } == true
        val freshPower = state == "receiving" && powerAt?.let { ms - it < 10000 } == true
        return mapOf("page11Observation" to page11?.plus(mapOf("receivedAtMs" to page11At,
                "ageMs" to (ms - page11At!!), "stale" to (ms - page11At!! >= 5000))),
            "partial" to (state == "receiving" && (!freshSpeed || !freshPower || speed == null || power == null || cadence == null)),
            "signal" to state, "speedKmh" to speed.takeIf { freshSpeed },
            "powerW" to power.takeIf { freshPower }, "cadenceRpm" to cadence.takeIf { freshPower },
            "distanceM" to distanceMeters, "distancePartial" to partial,
            "speedAgeMs" to speedAt?.let { ms - it }, "powerAgeMs" to powerAt?.let { ms - it },
            "signalAgeMs" to lastReceivedMs?.let { ms - it }, "elapsedMs" to ms - startedMs,
            "deviceNumber" to target.number, "deviceType" to target.type, "transmissionType" to target.transmission,
            "protocol" to "BKOOL_V1_PUBLIC")
    }
}

internal fun csvRow(values: List<Any?>): String = values.joinToString(",") {
    val s = it?.toString() ?: ""
    if (s.any { c -> c == ',' || c == '"' || c == '\n' || c == '\r' }) "\"${s.replace("\"", "\"\"")}\"" else s
} + "\r\n"
