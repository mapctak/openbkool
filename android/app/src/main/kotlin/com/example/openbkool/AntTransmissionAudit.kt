package com.example.openbkool

/** Thread-safe observations, not acknowledgements of any particular slope. */
internal class AntTransmissionAudit(private val clock: () -> Long) {
    @Volatile var channelUsable = false; private set
    private var openedAt: Long? = null
    private var closeRequestedAt: Long? = null
    private var closeApiReturnedAt: Long? = null
    private var closedAt: Long? = null
    private var deadAt: Long? = null
    private val events = ArrayDeque<Map<String, Any?>>()
    private val counts = linkedMapOf<Int, Int>()
    private var dropped = 0
    @Synchronized fun opened() { openedAt = clock(); channelUsable = closedAt == null && deadAt == null && (counts[1] ?: 0) == 0 }
    @Synchronized fun closeRequested() { closeRequestedAt = clock(); channelUsable = false }
    @Synchronized fun closeApiReturned() { closeApiReturnedAt = clock() }
    @Synchronized fun died() { deadAt = clock(); channelUsable = false }
    @Synchronized fun observe(code: Int) {
        if (code == 1 || code == 7) channelUsable = false
        if (code == 7) closedAt = clock()
        counts[code] = (counts[code] ?: 0) + 1
        if (events.size == 64) { events.removeFirst(); dropped++ }
        events.addLast(mapOf("code" to code, "name" to name(code), "monotonicMs" to clock(),
            "commandCorrelation" to "unavailable", "physicalApplication" to "unknown"))
    }
    @Synchronized fun snapshot(): Map<String, Any?> = mapOf(
        "channelUsable" to channelUsable, "openedAtMs" to openedAt,
        "closeRequestedAtMs" to closeRequestedAt, "closeApiReturnedAtMs" to closeApiReturnedAt,
        "channelClosedEventAtMs" to closedAt, "channelDeathAtMs" to deadAt,
        "channelEvents" to events.toList(), "droppedChannelEvents" to dropped,
        "txEventCount" to (counts[3] ?: 0), "transferCompletedCount" to (counts[5] ?: 0),
        "broadcastDelivery" to "unacknowledged", "physicalResistance" to "unknown",
        "slaveScheduling" to "once_at_next_transmit_window",
        "multipleWriteOrdering" to "not_guaranteed_by_reviewed_android_contract")
    private fun name(code: Int) = when (code) {
        1 -> "RX_SEARCH_TIMEOUT"; 2 -> "RX_FAIL"; 3 -> "TX"
        4 -> "TRANSFER_RX_FAILED"; 5 -> "TRANSFER_TX_COMPLETED"; 6 -> "TRANSFER_TX_FAILED"
        7 -> "CHANNEL_CLOSED"; 8 -> "RX_FAIL_GO_TO_SEARCH"; 9 -> "CHANNEL_COLLISION"
        10 -> "TRANSFER_TX_START"; else -> "UNKNOWN"
    }
}
