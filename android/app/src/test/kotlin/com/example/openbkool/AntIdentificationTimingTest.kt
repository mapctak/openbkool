package com.example.openbkool

import org.junit.Assert.*
import org.junit.Test

class AntIdentificationTimingTest {
    private class Rig {
        var now = 10000L
        val events = mutableListOf<Map<String, Any?>>()
        val timing = AntIdentificationTiming({ now }, AntTrainerIdentity(30064,112,5), events::add)
        fun page(vararg bytes: Int, number: Int = 30064, type: Int = 112, tx: Int = 5) =
            AntReceivedFrame(number, type, tx, bytes.map { it.toByte() }.toByteArray())
    }
    @Test fun separateOpenTelemetryProductManufacturerAndAvailability() {
        val r = Rig(); r.now += 200; r.timing.channelOpened(15)
        r.now += 100; r.timing.receive(r.page(0x10,0x19,0,0,0x86,0x0d,255,0x3c))
        r.now += 100; r.timing.receive(r.page(0x51,255,6,3,0x70,0x75,0x7a,0x93))
        r.timing.availability(false, listOf("manufacturer_model_not_verified"), true)
        r.now += 25000
        val waiting = r.timing.snapshot()
        assertEquals(25000L, waiting["waitingForConditionMs"])
        assertEquals(25200L, waiting["waitingSinceChannelOpenMs"])
        assertNull((waiting["milestonesMs"] as Map<*,*>)["identificationComplete"])
        r.timing.receive(r.page(0x50,255,255,255,67,0,22,0))
        r.now += 200; r.timing.availability(true, emptyList(), true)
        val snapshot = r.timing.snapshot()
        val durations = snapshot["durationsMs"] as Map<*,*>
        assertEquals(200L, durations["startToChannelOpen"])
        assertEquals(100L, durations["channelOpenToFirstTelemetry"])
        assertEquals(25200L, durations["channelOpenToIdentification"])
        assertEquals(25400L, durations["channelOpenToControlAvailable"])
        assertEquals(200L, durations["identificationToControlAvailable"])
        assertEquals(false, snapshot["waiting"])
        assertEquals(15L, snapshot["channelOpenApiDurationMs"])
        assertEquals(0, (snapshot["pageRequest"] as Map<*,*>)["attempts"])
    }
    @Test fun longWaitDoesNotPromoteProductOrForeignFrameAndRecoversWithValidPage50() {
        val r = Rig()
        r.timing.channelOpened(1)
        r.timing.receive(r.page(0x10, 0, 0, 0, 0x86, 0x0d, 0, 0))
        r.now += 53_000
        r.timing.receive(r.page(0x51, 255, 6, 3, 1, 2, 3, 4))
        repeat(2) { r.timing.availability(false, listOf("manufacturer_model_not_verified"), true) }
        assertEquals(true, r.timing.snapshot()["manufacturerWaitLong"])
        assertEquals(1, r.events.count { it["milestone"] == "manufacturer_model_wait_long" })
        assertNull(r.timing.snapshot()["lastPage50"])
        assertNotNull(r.timing.snapshot()["lastPage51"])
        r.timing.receive(r.page(0x50, 255, 255, 255, 67, 0, 22, 0, tx = 6))
        assertNull(r.timing.snapshot()["lastPage50"])
        r.timing.receive(r.page(0x50, 255, 255, 255, 67, 0, 22, 0))
        r.timing.availability(true, emptyList(), true)
        assertEquals(false, r.timing.snapshot()["manufacturerWaitLong"])
        assertEquals(22, (r.timing.snapshot()["lastPage50"] as Map<*, *>)["modelNumber"])
        assertEquals(53_000L, (r.timing.snapshot()["milestonesMs"] as Map<*, *>)["controlAvailable"])
    }
    @Test fun foreignIdentityWrongModelAndPage51CannotVerifyManufacturer() {
        val r = Rig()
        r.timing.receive(r.page(0x50,255,255,255,67,0,22,0, number=1))
        r.timing.receive(r.page(0x50,255,255,255,67,0,22,0, tx=6))
        r.timing.receive(r.page(0x50,255,255,255,67,0,22,0, type=17))
        assertTrue((r.timing.snapshot()["milestonesMs"] as Map<*,*>).isEmpty())
        r.timing.receive(r.page(0x50,255,255,255,67,0,24,0))
        r.timing.receive(r.page(0x50,255,255,255,1,0,22,0))
        r.timing.receive(r.page(0x51,255,6,3,0x70,0x75,0x7a,0x93))
        assertNull((r.timing.snapshot()["milestonesMs"] as Map<*,*>)["identificationComplete"])
        assertNull((r.timing.snapshot()["milestonesMs"] as Map<*,*>)["controlAvailable"])
    }
    @Test fun milestonesAreFirstOnlyAndEachConnectionStartsEmpty() {
        val r = Rig(); r.timing.channelOpened(10)
        r.timing.receive(r.page(0x50,255,255,255,67,0,22,0))
        r.now += 5000; r.timing.receive(r.page(0x50,255,255,255,67,0,22,0))
        assertEquals(1, r.events.count { it["milestone"] == "identificationComplete" })
        assertEquals(0L, (r.timing.snapshot()["milestonesMs"] as Map<*,*>)["identificationComplete"])
        val next = AntIdentificationTiming({ r.now }, AntTrainerIdentity(30064,112,5), {})
        assertTrue((next.snapshot()["milestonesMs"] as Map<*,*>).isEmpty())
        r.timing.finish(); val before = r.timing.snapshot()["elapsedMs"]
        r.now += 10000; assertEquals(before, r.timing.snapshot()["elapsedMs"])
    }
    @Test fun waitingClockResetsForEachBlockerWithoutInventingAvailability() {
        val r = Rig(); r.timing.availability(false, listOf("channel_not_open"), true)
        r.now += 5000; r.timing.availability(false, listOf("manufacturer_model_not_verified"), true)
        r.now += 1000; assertEquals(1000L, r.timing.snapshot()["waitingForConditionMs"])
        r.timing.availability(false, listOf("signal_not_fresh"), true)
        assertEquals(0L, r.timing.snapshot()["waitingForConditionMs"])
        assertNull((r.timing.snapshot()["milestonesMs"] as Map<*,*>)["controlAvailable"])
        r.timing.availability(false, listOf("session_stopped"), false)
        assertEquals(false, r.timing.snapshot()["waiting"])
    }
}
