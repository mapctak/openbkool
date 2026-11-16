package com.example.openbkool

import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicReference

/** Non-blocking cancellation of commands not yet entered on the serial worker.
 * A command already inside the ANT IPC call cannot be recalled by this fence. */
internal class ManualCommandFence {
    private val reason = AtomicReference<String?>(null)
    private val queued = AtomicInteger(0)
    fun enqueue() { queued.incrementAndGet() }
    fun dequeue(): String? { queued.decrementAndGet(); return reason.get() }
    fun cancel(cause: String) { reason.compareAndSet(null, cause) }
    fun snapshot(): Map<String, Any?> = mapOf("pendingApplicationCommands" to queued.get(),
        "cancelled" to (reason.get() != null), "cancelReason" to reason.get(),
        "radioBufferPending" to "unknown", "radioBufferCancellation" to "not_verified")
}
