package com.example.openbkool

import org.junit.Assert.*
import org.junit.Test
import java.time.Instant

class BkoolTelemetryTest {
    private fun bytes(s: String) = s.split(" ").map { it.toInt(16).toByte() }.toByteArray()
    private fun frame(s: String, id: Int = 30064) = AntReceivedFrame(id, 112, 5, bytes(s))
    @Test fun suppliedS20Page11IsRawObservationNotMechanicalAcknowledgement() {
        val t=BkoolTelemetry(0)
        val lines=javaClass.getResourceAsStream("/s20_refresh_1_3_1_page11.csv")!!.bufferedReader().readLines().drop(1)
        val first=Instant.parse(lines.first().substringBefore(',')).toEpochMilli()
        val words=mutableListOf<Int>()
        for(line in lines) {
            val ms=Instant.parse(line.substringBefore(',')).toEpochMilli()-first
            assertNull(t.receive(frame(line.substringAfter(',')),ms))
            val observation=t.snapshot(ms)["page11Observation"] as Map<*,*>
            words.add(observation["rawWordAtBytes4And5"] as Int)
            assertEquals(false,observation["commandAcknowledgement"])
            assertEquals(false,observation["mechanicalConfirmation"])
            assertFalse(observation.containsKey("appliedPercent"))
            assertNull(t.snapshot(ms)["powerW"])
        }
        assertEquals(listOf(20000,20050,20050),words)
        assertNull(BkoolTelemetry(0).snapshot(0)["page11Observation"])
        assertNull(observeBkoolPage11(bytes("11 FF")))
        assertNull(observeBkoolPage11(bytes("10 FF FF FF 52 4E 00 34")))
    }
    @Test fun page11DoesNotRefreshMetricAgesAndWrongIdentityIsIgnored() {
        val t=BkoolTelemetry(0)
        t.receive(frame("19 51 00 2D 23 00 40 36"),0)
        t.receive(frame("11 FF FF FF 52 4E 00 34",1),1000)
        assertNull(t.snapshot(1000)["page11Observation"])
        t.receive(frame("11 FF FF FF 52 4E 00 34"),2000)
        assertEquals(2000L,t.snapshot(2000)["powerAgeMs"])
        val old=t.snapshot(10000)["page11Observation"] as Map<*,*>
        assertEquals(true,old["stale"]);assertNull(t.snapshot(10000)["powerW"])
    }
    @Test fun capturedUnitsAndPowerMask() {
        val speed = decodeBkoolPage(bytes("10 19 98 65 86 0D FF 3C"))!!
        assertEquals(12.4632, speed.speedKmh!!, 0.000001)
        assertEquals(101, speed.distanceCounter)
        val power = decodeBkoolPage(bytes("19 BF 17 D2 05 1D 40 36"))!!
        assertEquals(29, power.powerW); assertEquals(23, power.cadenceRpm)
    }
    @Test fun replayActualCapture() {
        val lines = javaClass.getResourceAsStream("/bkool_30064.csv")!!.bufferedReader().readLines().drop(1)
        val first = Instant.parse(lines.first().substringBefore(',')).toEpochMilli()
        val t = BkoolTelemetry(0)
        var ms = 0L
        for (line in lines) {
            ms = Instant.parse(line.substringBefore(',')).toEpochMilli() - first
            val payload = bytes(line.substringAfter(','))
            val content = byteArrayOf(0) + payload + bytes("80 70 75 70 05")
            t.receive(decodeAntFrame(0x4e, content)!!, ms)
        }
        val r = t.snapshot(ms)
        assertEquals(103L, r["distanceM"])
        assertEquals(26, r["powerW"]); assertEquals(17, r["cadenceRpm"])
        assertEquals(13.0608, r["speedKmh"] as Double, 0.000001)
    }
    @Test fun baselineAndSyntheticDistanceWrapAndDuplicates() {
        val t = BkoolTelemetry(0)
        t.receive(frame("10 19 00 FA 86 0D FF 3C"), 0)
        assertEquals(0L, t.snapshot(0)["distanceM"])
        t.receive(frame("10 19 01 04 86 0D FF 3C"), 1000)
        t.receive(frame("10 19 01 04 86 0D FF 3C"), 1100)
        assertEquals(10L, t.snapshot(1100)["distanceM"])
    }
    @Test fun lossRecoveryDoesNotInventDistanceAndOtherIdentityIgnored() {
        val t = BkoolTelemetry(0)
        t.receive(frame("10 19 00 05 86 0D FF 3C"), 0)
        t.receive(frame("10 19 00 15 86 0D FF 3C", 1), 4000)
        assertEquals("signal_lost", t.signal(5000))
        assertNull(t.snapshot(5000)["speedKmh"])
        t.receive(frame("10 19 00 20 86 0D FF 3C"), 6000)
        assertEquals(0L, t.snapshot(6000)["distanceM"])
        assertEquals(true, t.snapshot(6000)["distancePartial"])
        assertEquals("disconnected", t.signal(21000))
        assertEquals("disconnected", BkoolTelemetry(0).signal(30000))
    }
    @Test fun invalidAndStaleAndCadenceChangesWithoutCounterChange() {
        assertNull(decodeBkoolPage(byteArrayOf(0x10)))
        val t = BkoolTelemetry(0)
        t.receive(frame("19 C9 14 FC 06 1C 40 36"), 0)
        t.receive(frame("19 C9 17 FC 06 1C 40 36"), 500)
        assertEquals(23, t.snapshot(500)["cadenceRpm"])
        t.receive(frame("50 FF FF FF 43 00 16 00"), 10000)
        assertNull(t.snapshot(10500)["powerW"])
        assertNull(decodeBkoolPage(bytes("10 19 FF FF FF FF FF FF"))!!.speedKmh)
        val invalid = decodeBkoolPage(bytes("19 FF FF FF FF FF FF FF"))!!
        assertNull(invalid.powerW); assertNull(invalid.cadenceRpm)
    }
    @Test fun ambiguousResetAndLongPageGapRebaseline() {
        val t = BkoolTelemetry(0)
        t.receive(frame("10 19 00 05 86 0D FF 3C"), 0)
        t.receive(frame("10 19 00 00 86 0D FF 3C"), 1000)
        assertEquals(0L, t.snapshot(1000)["distanceM"])
        assertEquals(true, t.snapshot(1000)["distancePartial"])
        t.receive(frame("10 19 00 01 86 0D FF 3C"), 2000)
        assertEquals(1L, t.snapshot(2000)["distanceM"])
    }
    @Test fun prolongedSessionsSuspendControlWithoutStoppingTelemetryAndDetectTotalLoss() {
        for (minutes in listOf(30, 60)) {
            val telemetry = BkoolTelemetry(0)
            val target = AntTrainerIdentity(30064, 112, 5)
            var now = 0L
            val writes = mutableListOf<Boolean>()
            val control = ManualAntControl(target, { now }, {
                val state = telemetry.snapshot(now)
                ManualControlLink(true, true, 67, 22, state["signalAgeMs"] as Long?,
                    state["powerW"] != null && state["cadenceRpm"] != null && state["speedKmh"] != null)
            }, { _, stop -> writes.add(stop) }, {})
            for (second in 0..minutes * 60) {
                now = second * 1000L
                telemetry.receive(frame("10 19 98 65 86 0D FF 3C"), now)
                if (second % 2 == 0) telemetry.receive(frame("11 FF FF FF 52 4E 00 34"), now)
                if (second % 3 == 0) telemetry.receive(frame("54 FF FF FF FF FF FF FF"), now)
                if (second !in 810..825 && second !in 1050..1063) {
                    telemetry.receive(frame("19 BF 17 D2 05 1D 40 36"), now)
                }
                if (second == 0) {
                    assertEquals("enabled", control.enable(true)["event"])
                    control.request(0.5)
                }
                if (control.abortReason() == "link_lost:telemetry_not_fresh") {
                    assertTrue(control.suspendForMissingTelemetry())
                }
                control.refreshTarget()
                assertEquals("receiving", telemetry.signal(now))
                if (second == 821 || second == 1062) {
                    val snapshot = telemetry.snapshot(now)
                    assertEquals(true, snapshot["partial"])
                    assertNull(snapshot["powerW"])
                    assertNotNull(snapshot["speedKmh"])
                    assertEquals("suspended", control.snapshot()["state"])
                }
                if (second == 826 || second == 1064) {
                    assertEquals(29, telemetry.snapshot(now)["powerW"])
                    assertEquals(false, control.snapshot()["enabled"])
                }
            }
            assertEquals(1, writes.count { it })
            assertTrue(writes.last())
            assertEquals("signal_lost", telemetry.signal(now + 5000))
            assertEquals("disconnected", telemetry.signal(now + 15000))
            assertFalse(control.stop("disconnected", allowZero = false))
            assertEquals(1, writes.count { it })
        }
    }

    @Test fun csvEscapesAndUsesDecimalPoint() {
        assertEquals("1.5,\"a,b\",\"a\"\"b\",\r\n", csvRow(listOf(1.5, "a,b", "a\"b", null)))
    }
}
