package com.example.openbkool

import org.junit.Assert.*
import org.junit.Test

class AntControlPreparationTest {
    private val target = AntTrainerIdentity(30064, 112, 5)
    private class Channel(val failOn: String? = null) : V1DedicatedChannel {
        val calls = mutableListOf<String>()
        fun call(s: String) { calls.add(s); if (s == failOn) throw IllegalStateException("INVALID_REQUEST") }
        override fun assignBidirectionalSlave() = call("assign")
        override fun setId(number: Int, type: Int, transmission: Int) = call("id:$number:$type:$transmission")
        override fun setPeriod(period: Int) = call("period:$period")
        override fun setRfFrequency(rf: Int) = call("rf:$rf")
        override fun setLowPrioritySearchOnly() = call("timeout:25:0")
        override fun enableExtendedIdentity() = call("identity")
        override fun open() = call("open")
    }
    @Test fun installedSdkTimeoutFactoryUsesMilliseconds() {
        assertEquals(25000, com.dsi.ant.message.LowPrioritySearchTimeout.TWENTY_FIVE_SECONDS.convertToMilliseconds())
        assertEquals(25000, com.dsi.ant.message.LowPrioritySearchTimeout.create(30000).convertToMilliseconds())
        assertEquals(2500, com.dsi.ant.message.LowPrioritySearchTimeout.create(16).convertToMilliseconds())
        assertEquals(0, com.dsi.ant.message.HighPrioritySearchTimeout.DISABLED.convertToMilliseconds())
        assertEquals(0, com.dsi.ant.message.ChannelType.BIDIRECTIONAL_SLAVE.rawValue)
    }
    @Test fun dedicatedConfigurationHasExactIdentityWithoutBackgroundScanOrDataSends() {
        val c = Channel()
        val events = mutableListOf<Map<String, Any?>>()
        configureV1Dedicated(c, target, 2, 80, AntOperationTrace(events::add))
        assertEquals(listOf("assign", "id:30064:112:5", "period:32768", "rf:40", "timeout:25:0", "identity", "open"), c.calls)
        assertEquals(false, (events.first { it["operation"] == "connection.assign" }["arguments"] as Map<*, *>)["backgroundScanning"])
    }
    @Test fun dedicatedErrorsStopImmediatelyAtNamedOperation() {
        for ((call, operation) in mapOf("assign" to "assign", "id:30064:112:5" to "setChannelId",
            "period:32768" to "setPeriod", "rf:40" to "setRfFrequency", "timeout:25:0" to "setSearchTimeout", "open" to "open")) {
            val c = Channel(call)
            val trace = AntOperationTrace({})
            try { configureV1Dedicated(c, target, 2, 80, trace); fail("Debe fallar") }
            catch (e: IllegalStateException) { assertEquals("connection.$operation", trace.failureFor(e)?.get("operation")) }
            assertEquals(call, c.calls.last())
        }
        val c = Channel()
        try { configureV1Dedicated(c, target, 41, 80, AntOperationTrace({})); fail("RF incompatible") }
        catch (_: IllegalArgumentException) { assertTrue(c.calls.isEmpty()) }
    }
    @Test fun targetsCannotUseWildcardsOrOtherDeviceTypes() {
        for (id in listOf(Triple(0,112,5), Triple(30064,0,5), Triple(30064,112,0), Triple(65536,112,5), Triple(30064,112,256))) {
            try { AntTrainerIdentity(id.first, id.second, id.third); fail("Comodín inválido") } catch (_: IllegalArgumentException) {}
        }
        val t = BkoolTelemetry(0, AntTrainerIdentity(123,112,6))
        assertFalse(t.accepts(AntReceivedFrame(30064,112,5, ByteArray(8))))
        assertFalse(t.accepts(AntReceivedFrame(123,112,5, ByteArray(8))))
        assertFalse(t.accepts(AntReceivedFrame(123,17,6, ByteArray(8))))
        assertTrue(t.accepts(AntReceivedFrame(123,112,6, ByteArray(8))))
    }
    @Test fun dryRunEndpointsAreExactAndAlwaysBlocked() {
        val p = ManualSlopePreparation(target)
        assertEquals("not_connected", p.prepare(0.0,0)["state"])
        p.connectionVerified(true)
        val zero = p.prepare(0.0,0)
        assertEquals("33 FF FF FF FF 20 4E FF", zero["candidatePayloadHex"])
        assertEquals(false, zero["sent"])
        assertEquals("duplicate", p.prepare(0.0,2000)["state"])
        val one = p.prepare(1.0,2000)
        assertEquals("33 FF FF FF FF 84 4E FF", one["candidatePayloadHex"])
        assertEquals(false, one["transmissionEnabled"])
        assertEquals("rate_limited", p.prepare(0.5,2100)["state"])
    }
    @Test fun invalidGradesDisconnectStopAndFreshSessionNeverSendOrQueue() {
        val p = ManualSlopePreparation(target)
        p.connectionVerified(true)
        for (v in listOf(Double.NaN, Double.POSITIVE_INFINITY, Double.NEGATIVE_INFINITY, -0.01, 1.01)) {
            val plan = p.prepare(v,0)
            assertEquals("invalid_range", plan["state"]); assertNull(plan["candidatePayloadHex"])
            assertEquals(false, plan["sent"])
        }
        assertEquals("unsupported_precision", p.prepare(0.005,0)["state"])
        p.prepare(0.0,0)
        p.connectionVerified(false)
        assertEquals("not_connected", p.prepare(1.0,2000)["state"])
        p.stop(); p.connectionVerified(true)
        assertEquals("session_stopped", p.prepare(1.0,3000)["state"])
        assertEquals(0, p.snapshot()["pendingCommands"])
        assertEquals("unknown", p.snapshot()["resistanceAfterClose"])
        assertEquals("not_connected", ManualSlopePreparation(target).prepare(1.0,4000)["state"])
    }
    @Test fun coordinatorPreventsOverlappingHandoffs() {
        val scan = Any(); val connection = Any()
        assertTrue(AntRadioCoordinator.acquire(scan))
        try { assertFalse(AntRadioCoordinator.acquire(connection)) } finally { AntRadioCoordinator.release(scan) }
        assertTrue(AntRadioCoordinator.acquire(connection)); AntRadioCoordinator.release(connection)
    }
    @Test fun configuredAdapterAndReceivedIdsMustAllMatchSelectedIncludingTransmission() {
        val exact = target.toMap()
        assertTrue(channelIdentitiesMatch(target, exact, exact, exact))
        for (wrong in listOf(null, exact + mapOf("deviceNumber" to 0), exact + mapOf("deviceNumber" to 30065),
            exact + mapOf("deviceType" to 17), exact + mapOf("transmissionType" to 6))) {
            assertFalse(channelIdentitiesMatch(target, wrong, exact, exact))
            assertFalse(channelIdentitiesMatch(target, exact, wrong, exact))
            assertFalse(channelIdentitiesMatch(target, exact, exact, wrong))
        }
    }

}
