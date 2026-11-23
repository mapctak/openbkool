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
    private var longWaitReported = false
    private var page50: Map<String, Any?>? = null
    private var page51: Map<String, Any?>? = null
    private fun elapsed() = ((ended ?: clock()) - started).coerceAtLeast(0)
    private fun mark(name: String, at: Long = elapsed()) {
        if (marks.containsKey(name)) return
        marks[name] = at
        emit(mapOf("milestone" to name, "elapsedMs" to at, "identity" to target.toMap()))
    }
    fun channelOpened(apiDurationMs: Long) {
        if (openCallMs == null) openCallMs = apiDurationMs
        mark("channelOpen")
    }
    fun receive(frame: AntReceivedFrame, receivedAt: Long = clock()) {
        if (!target.matches(frame)) return
        val elapsedAt = (receivedAt - started).coerceAtLeast(0)
        mark("firstIdentityFrame", elapsedAt)
        val page = decodeBkoolPage(frame.payload)
        if (page != null && (page.speedKmh != null || page.powerW != null || page.cadenceRpm != null)) mark("firstTelemetry", elapsedAt)
        val info = manufacturerPage(frame.payload) ?: return
        when (frame.payload[0].toInt() and 255) {
            0x50 -> {
                page50 = info + mapOf("elapsedMs" to elapsedAt, "receivedAtMs" to receivedAt)
                mark("firstPage50", elapsedAt)
                if (info["manufacturerId"] == 67 && info["modelNumber"] == 22) mark("identificationComplete", elapsedAt)
            }
            0x51 -> {
                page51 = info + mapOf("elapsedMs" to elapsedAt, "receivedAtMs" to receivedAt)
                mark("firstPage51", elapsedAt)
            }
        }
    }
    fun availability(eligible: Boolean, reasons: List<String>, sessionActive: Boolean) {
        if (eligible && sessionActive) mark("controlAvailable")
        waiting = sessionActive && !eligible
        val next = if (waiting) reasons.firstOrNull() else null
        if (next != blocker) { blocker = next; blockerAt = elapsed() }
        if (longWait() && !longWaitReported) {
            longWaitReported = true
            emit(mapOf("milestone" to "manufacturer_model_wait_long", "elapsedMs" to elapsed(),
                "page50" to page50, "page51" to page51, "identity" to target.toMap()))
        }
    }
    private fun longWait(): Boolean = waiting && blocker == "manufacturer_model_not_verified" &&
        (marks["channelOpen"]?.let { elapsed() - it >= 45_000 } == true)

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
            "waiting" to waiting, "waitingReason" to blocker, "manufacturerWaitLong" to longWait(),
            "lastPage50" to page50, "lastPage51" to page51,
            "waitingForConditionMs" to if (waiting) now - blockerAt else null,
            "waitingSinceChannelOpenMs" to if (waiting) marks["channelOpen"]?.let { now - it } else null,
            "pageRequest" to mapOf("enabled" to false, "attempts" to 0, "maxAttempts" to 0,
                "reason" to "bkool_v1_page70_support_unverified"))
    }
}
