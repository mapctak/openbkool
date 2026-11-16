package com.example.openbkool

/** Passive, per-connection measurements only. Never supplies safety identity or transmits. */
internal class AntIdentificationTiming(
    private val clock: () -> Long,
    private val target: AntTrainerIdentity,
    private val emit: (Map<String, Any?>) -> Unit,
) {
    private val started = clock()
    private val marks = linkedMapOf<String, Long>()
    private var ended: Long? = null
    private var openCallMs: Long? = null
    private var blocker: String? = null
    private var blockerAt = 0L
    private var waiting = false
    private fun elapsed() = ((ended ?: clock()) - started).coerceAtLeast(0)
    private fun mark(name: String) {
        if (marks.containsKey(name)) return
        val at = elapsed()
        marks[name] = at
        emit(mapOf("milestone" to name, "elapsedMs" to at, "identity" to target.toMap()))
    }
    fun channelOpened(apiDurationMs: Long) {
        if (openCallMs == null) openCallMs = apiDurationMs
        mark("channelOpen")
    }
    fun receive(frame: AntReceivedFrame) {
        if (!target.matches(frame)) return
        mark("firstIdentityFrame")
        val page = decodeBkoolPage(frame.payload)
        if (page != null && (page.speedKmh != null || page.powerW != null || page.cadenceRpm != null)) mark("firstTelemetry")
        val info = manufacturerPage(frame.payload) ?: return
        when (frame.payload[0].toInt() and 255) {
            0x50 -> {
                mark("firstPage50")
                if (info["manufacturerId"] == 67 && info["modelNumber"] == 22) mark("identificationComplete")
            }
            0x51 -> mark("firstPage51") // Software/serial is not manufacturer/model verification.
        }
    }
    fun availability(eligible: Boolean, reasons: List<String>, sessionActive: Boolean) {
        if (eligible && sessionActive) mark("controlAvailable")
        waiting = sessionActive && !eligible
        val next = if (waiting) reasons.firstOrNull() else null
        if (next != blocker) { blocker = next; blockerAt = elapsed() }
    }
    fun finish() { if (ended == null) ended = clock(); waiting = false }
    fun snapshot(): Map<String, Any?> {
        fun duration(from: String, to: String): Long? {
            val a = marks[from] ?: return null
            val b = marks[to] ?: return null
            return b - a
        }
        val now = elapsed()
        return mapOf(
            "clock" to "monotonic_elapsed_realtime", "elapsedMs" to now,
            "milestonesMs" to HashMap(marks), "channelOpenApiDurationMs" to openCallMs,
            "durationsMs" to mapOf(
                "startToChannelOpen" to marks["channelOpen"],
                "channelOpenToFirstTelemetry" to duration("channelOpen", "firstTelemetry"),
                "channelOpenToIdentification" to duration("channelOpen", "identificationComplete"),
                "channelOpenToControlAvailable" to duration("channelOpen", "controlAvailable"),
                "identificationToControlAvailable" to duration("identificationComplete", "controlAvailable")),
            "waiting" to waiting, "waitingReason" to blocker,
            "waitingForConditionMs" to if (waiting) now - blockerAt else null,
            "waitingSinceChannelOpenMs" to if (waiting) marks["channelOpen"]?.let { now - it } else null,
            "pageRequest" to mapOf("enabled" to false, "attempts" to 0, "maxAttempts" to 0,
                "reason" to "bkool_v1_page70_support_unverified"))
    }
}
