package com.example.openbkool

import org.junit.Assert.*
import org.junit.Test

class AntOperationTraceTest {
    private class FakeChannel(private val failAt: String? = null) : V1BackgroundChannel {
        val calls = mutableListOf<String>()
        val failure = IllegalStateException("INVALID_REQUEST simulated")
        private fun call(name: String) { calls.add(name); if (name == failAt) throw failure }
        override fun assignReceiveOnlyBackground() = call("assign")
        override fun setId(number: Int, type: Int, transmission: Int) = call("id:$number:$type:$transmission")
        override fun setPeriod(period: Int) = call("period:$period")
        override fun setRfFrequency(rf: Int) = call("rf:$rf")
        override fun enableExtendedIdentity() = call("identity")
        override fun checkBackgroundAvailable() = call("availability")
        override fun open() = call("open")
    }
    private val supported = V1ChannelCapabilities(true, true, 0, 124)

    @Test fun backgroundPlanPreservesParametersAndNeverSendsTimeout() {
        val driver = FakeChannel()
        val events = mutableListOf<Map<String, Any?>>()
        configureV1Background(driver, supported, AntOperationTrace(events::add))
        assertEquals(listOf("availability", "assign", "id:0:0:0", "period:32768", "rf:40", "identity", "availability", "open"), driver.calls)
        assertFalse(events.any { it["operation"] == "v1.setSearchTimeout" && it["state"] == "started" })
        assertTrue(events.any { it["operation"] == "v1.setSearchTimeout" && it["state"] == "skipped" })
        val assign = events.first { it["operation"] == "v1.assign" }
        assertEquals(mapOf("type" to "SLAVE_RECEIVE_ONLY", "backgroundScanning" to true), assign["arguments"])
    }

    @Test fun eachFailureIsAttributedToExactOperationAndStopsConfiguration() {
        val cases = mapOf("assign" to "v1.assign", "id:0:0:0" to "v1.setChannelId",
            "period:32768" to "v1.setPeriod", "rf:40" to "v1.setRfFrequency", "open" to "v1.open")
        for ((call, operation) in cases) {
            val events = mutableListOf<Map<String, Any?>>()
            val driver = FakeChannel(call)
            var ticks = 0L
            val trace = AntOperationTrace(events::add,
                { mapOf("type" to it.javaClass.name, "message" to it.message, "failureReason" to "INVALID_REQUEST") },
                { ticks += 1_000_000; ticks })
            try { configureV1Background(driver, supported, trace); fail("Debe fallar en $operation") }
            catch (error: IllegalStateException) {
                assertSame(driver.failure, error)
                val failure = trace.failureFor(error)!!
                assertEquals(operation, failure["operation"])
                assertEquals("failed", failure["state"])
                assertEquals(1.0, failure["durationMs"])
                assertEquals("INVALID_REQUEST", (failure["error"] as Map<*, *>)["failureReason"])
                assertEquals(call, driver.calls.last())
            }
        }
    }

    @Test fun unsupportedCapabilitiesPreventAssignmentAndKeepReason() {
        for (caps in listOf(V1ChannelCapabilities(false, true, 0, 124),
            V1ChannelCapabilities(true, false, 0, 124), V1ChannelCapabilities(true, true, 41, 124))) {
            val driver = FakeChannel()
            val events = mutableListOf<Map<String, Any?>>()
            try { configureV1Background(driver, caps, AntOperationTrace(events::add)); fail("Capacidad no disponible") }
            catch (error: UnsupportedOperationException) { assertEquals(caps.unsupportedReason(), error.message) }
            assertTrue(driver.calls.isEmpty())
            assertEquals("v1.validateCapabilities", events.last()["operation"])
            assertEquals("failed", events.last()["state"])
        }
    }

    @Test fun cleanupFailureDoesNotEraseOriginalConfigurationFailure() {
        val events = mutableListOf<Map<String, Any?>>()
        val trace = AntOperationTrace(events::add)
        val driver = FakeChannel("period:32768")
        try { configureV1Background(driver, supported, trace) } catch (_: IllegalStateException) { }
        var released = false
        val errors = releaseAntResources(listOf(
            { trace.run("cleanup.close") { throw IllegalStateException("close failed") } },
            { trace.run("cleanup.release") { released = true } },
        ))
        assertTrue(released)
        assertEquals(1, errors.size)
        assertEquals("v1.setPeriod", trace.firstFailure!!["operation"])
        assertTrue(events.any { it["operation"] == "cleanup.close" && it["state"] == "failed" })
        assertEquals("cleanup.release", trace.lastOperation!!["operation"])
    }

    @Test fun diagnosticEnrichmentCannotReplaceDriverException() {
        val events = mutableListOf<Map<String, Any?>>()
        val trace = AntOperationTrace(events::add, { throw IllegalArgumentException("diagnostic failed") })
        val original = IllegalStateException("driver failed")
        try { trace.run<Unit>("v1.assign") { throw original }; fail() }
        catch (error: IllegalStateException) { assertSame(original, error) }
        assertEquals("driver failed", (events.last()["error"] as Map<*, *>)["message"])
    }
}
