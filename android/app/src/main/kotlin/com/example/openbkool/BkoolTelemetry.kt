package com.example.openbkool

/** Decoder puro. Índices del payload ANT de ocho bytes, sin cabecera/ID extendido. */
internal data class BkoolPage(val page: Int, val speedKmh: Double? = null,
    val distanceCounter: Int? = null, val powerW: Int? = null, val cadenceRpm: Int? = null)

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

internal class BkoolTelemetry(private val startedMs: Long) {
    var lastReceivedMs: Long? = null; private set
    private var speedAt: Long? = null
    private var powerAt: Long? = null
    private var speed: Double? = null
    private var power: Int? = null
    private var cadence: Int? = null
    private var counter: Int? = null
    private var distanceAt: Long? = null
    private var distance = 0L
    private var partial = false
    private var signalLost = false
    fun accepts(f: AntReceivedFrame) = f.deviceNumber == 30064 && f.deviceType == 112 && f.transmissionType == 5
    fun receive(frame: AntReceivedFrame, ms: Long): BkoolPage? {
        if (!accepts(frame)) return null
        if (lastReceivedMs?.let { ms - it >= 5000 } == true) loseSignal()
        lastReceivedMs = ms
        signalLost = false
        val p = decodeBkoolPage(frame.payload) ?: return null
        when (p.page) {
            0x10 -> {
                speed = p.speedKmh; speedAt = ms
                val next = p.distanceCounter!!
                // Never invent complete turns of the counter or distance before this session.
                if (counter != null) {
                    val delta = (next - counter!! + 256) % 256
                    val gap = ms - distanceAt!!
                    if (gap >= 10000 || delta > 65.534 * (gap / 1000.0 + 1) + 2) {
                        partial = true // gap/reset cannot be reconstructed safely
                    } else {
                        distance += delta
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
        if (age >= 5000) loseSignal()
        return if (age >= 15000) "disconnected" else if (signalLost) "signal_lost" else "receiving"
    }
    fun snapshot(ms: Long): Map<String, Any?> {
        val state = signal(ms)
        val freshSpeed = state == "receiving" && speedAt?.let { ms - it < 10000 } == true
        val freshPower = state == "receiving" && powerAt?.let { ms - it < 10000 } == true
        return mapOf("signal" to state, "speedKmh" to speed.takeIf { freshSpeed },
            "powerW" to power.takeIf { freshPower }, "cadenceRpm" to cadence.takeIf { freshPower },
            "distanceM" to distance, "distancePartial" to partial,
            "speedAgeMs" to speedAt?.let { ms - it }, "powerAgeMs" to powerAt?.let { ms - it },
            "signalAgeMs" to lastReceivedMs?.let { ms - it }, "elapsedMs" to ms - startedMs,
            "deviceNumber" to 30064, "deviceType" to 112, "transmissionType" to 5,
            "protocol" to "BKOOL_V1_PUBLIC")
    }
}

internal fun csvRow(values: List<Any?>): String = values.joinToString(",") {
    val s = it?.toString() ?: ""
    if (s.any { c -> c == ',' || c == '"' || c == '\n' || c == '\r' }) "\"${s.replace("\"", "\"\"")}\"" else s
} + "\r\n"
