package com.example.openbkool

/** No Android dependency: tests can inject a failure at each driver operation. */
internal class AntOperationTrace(
    private val emit: (Map<String, Any?>) -> Unit,
    private val describeError: (Exception) -> Map<String, Any?> = {
        mapOf("type" to it.javaClass.name, "message" to it.message)
    },
    private val clock: () -> Long = System::nanoTime,
) {
    private var sequence = 0
    var lastOperation: Map<String, Any?>? = null
        private set
    var firstFailure: Map<String, Any?>? = null
        private set
    private var failedException: Exception? = null
    private var failedOperation: Map<String, Any?>? = null

    fun failureFor(error: Exception): Map<String, Any?>? =
        if (failedException === error) failedOperation else null

    fun <T> run(
        name: String,
        arguments: Map<String, Any?> = emptyMap(),
        summarize: (T) -> Any? = { null },
        action: () -> T,
    ): T {
        val id = ++sequence
        val start = clock()
        val base = mapOf("operationId" to id, "operation" to name, "arguments" to arguments)
        record(base + mapOf("state" to "started"))
        try {
            val value = action()
            record(base + mapOf("state" to "succeeded", "durationMs" to (clock() - start) / 1_000_000.0,
                "result" to summarize(value)))
            return value
        } catch (error: Exception) {
            // Never let diagnostic enrichment replace the original exception.
            val details = try { describeError(error) } catch (_: Exception) {
                mapOf("type" to error.javaClass.name, "message" to error.message)
            }
            val failure = base + mapOf("state" to "failed", "durationMs" to (clock() - start) / 1_000_000.0,
                "error" to details)
            failedException = error
            failedOperation = failure
            if (firstFailure == null) firstFailure = failure
            record(failure)
            throw error
        }
    }

    fun skip(name: String, reason: String, arguments: Map<String, Any?> = emptyMap()) {
        record(mapOf("operationId" to ++sequence, "operation" to name, "state" to "skipped",
            "arguments" to arguments, "reason" to reason))
    }
    private fun record(value: Map<String, Any?>) { lastOperation = value; emit(value) }
}

internal data class V1ChannelCapabilities(
    val backgroundScanning: Boolean, val extendedAssign: Boolean,
    val rfMin: Int, val rfMax: Int,
) {
    fun toMap(): Map<String, Any?> = mapOf("backgroundScanning" to backgroundScanning,
        "extendedAssign" to extendedAssign, "rfMin" to rfMin, "rfMax" to rfMax)
    fun unsupportedReason(): String? = when {
        !backgroundScanning -> "La radio no admite background scanning"
        !extendedAssign -> "La radio no admite asignación extendida"
        40 !in rfMin..rfMax -> "RF=40 fuera del rango disponible [$rfMin,$rfMax]"
        else -> null
    }
}

internal interface V1BackgroundChannel {
    fun assignReceiveOnlyBackground()
    fun setId(number: Int, type: Int, transmission: Int)
    fun setPeriod(period: Int)
    fun setRfFrequency(rf: Int)
    fun enableExtendedIdentity()
    fun checkBackgroundAvailable()
    fun open()
}

/** Same receive-only assignment as Bkool's scan branch. The official background
 * scan example configures period too, but never calls setSearchTimeout. */
internal fun configureV1Background(
    channel: V1BackgroundChannel, capabilities: V1ChannelCapabilities, trace: AntOperationTrace,
) {
    trace.run("v1.validateCapabilities", capabilities.toMap()) {
        capabilities.unsupportedReason()?.let { throw UnsupportedOperationException(it) }
    }
    channel.checkBackgroundAvailable()
    trace.run("v1.assign", mapOf("type" to "SLAVE_RECEIVE_ONLY", "backgroundScanning" to true)) {
        channel.assignReceiveOnlyBackground()
    }
    trace.run("v1.setChannelId", mapOf("number" to 0, "type" to 0, "transmission" to 0)) {
        channel.setId(0, 0, 0)
    }
    trace.run("v1.setPeriod", mapOf("period" to 32768)) { channel.setPeriod(32768) }
    trace.run("v1.setRfFrequency", mapOf("rf" to 40)) { channel.setRfFrequency(40) }
    // AntChannel Javadoc 4.16.0 explicitly forbids BOTH overloads on background scans.
    trace.skip("v1.setSearchTimeout", "No válido en background scanning: INVALID_REQUEST según ANTLib 4.16.0",
        mapOf("applied" to false, "applicationWindowSeconds" to 40))
    channel.enableExtendedIdentity()
    channel.checkBackgroundAvailable()
    trace.run("v1.open") { channel.open() }
}
