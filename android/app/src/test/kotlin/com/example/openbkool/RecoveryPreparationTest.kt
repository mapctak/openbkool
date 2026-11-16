package com.example.openbkool

import org.junit.Assert.*
import org.junit.Test

/** Offline original-code evidence and regression guards. No Android radio/API. */
class RecoveryPreparationTest {
    @Test fun originalBasicZeroChangesPageRatherThanEncodingZeroGrade() {
        // BkoolSensorAntPlus:232-237 -> TrainerBkoolPro1:223-224.
        val originalArgument = 0 * 2
        val originalBasicZero = byteArrayOf(48, -1, -1, -1, -1, -1, -1,
            (originalArgument and 255).toByte())
        assertEquals("30 FF FF FF FF FF FF 00", hex(originalBasicZero))
        assertEquals("33 FF FF FF FF 20 4E FF", hex(encodeManualSlope(0.0)))
        assertFalse(originalBasicZero.contentEquals(encodeManualSlope(0.0)))
    }

    @Test fun supervisionDoesNotPeriodicallyResubmitTargetAndStopRemainsSlopeZero() {
        var time = 0L
        val frames = mutableListOf<String>()
        val c = ManualAntControl(AntTrainerIdentity(30064,112,5), {time},
            {ManualControlLink(true,true,67,22,0,true)}, {bytes,_ -> frames.add(hex(bytes))}, {})
        c.enable(true)
        assertTrue(frames.isEmpty())
        c.request(1.0)
        for (second in 1L..29L) {
            time = second * 1000
            c.supervise()
            assertNull(c.abortReason())
        }
        assertEquals(listOf("33 FF FF FF FF 84 4E FF"), frames)
        time = 30000
        assertEquals("test_timeout", c.abortReason())
        c.stop("test_timeout", true)
        c.completeStop(true)
        assertEquals(listOf("33 FF FF FF FF 84 4E FF", "33 FF FF FF FF 20 4E FF"), frames)
        assertEquals("zero_api_returned_unconfirmed", c.snapshot()["stopResult"])
        assertEquals("unknown", c.snapshot()["resistanceAfterClose"])
        c.request(2.0)
        c.request(3.0)
        assertEquals(2, frames.size)
    }
}
