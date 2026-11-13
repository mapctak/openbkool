package com.example.openbkool

import org.junit.Assert.*
import org.junit.Test
import java.time.Instant

class BkoolTelemetryTest {
    private fun bytes(s: String) = s.split(" ").map { it.toInt(16).toByte() }.toByteArray()
    private fun frame(s: String, id: Int = 30064) = AntReceivedFrame(id, 112, 5, bytes(s))
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
    @Test fun csvEscapesAndUsesDecimalPoint() {
        assertEquals("1.5,\"a,b\",\"a\"\"b\",\r\n", csvRow(listOf(1.5, "a,b", "a\"b", null)))
    }
}
