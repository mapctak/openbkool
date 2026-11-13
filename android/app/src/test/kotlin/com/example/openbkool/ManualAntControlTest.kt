package com.example.openbkool

import org.junit.Assert.*
import org.junit.Test

class ManualAntControlTest {
    private class Rig(val target: AntTrainerIdentity = AntTrainerIdentity(30064,112,5)) {
        var time = 0L
        var link = ManualControlLink(true,true,67,22,0,true)
        var failure: Exception? = null
        val frames = mutableListOf<ByteArray>()
        val events = mutableListOf<Map<String,Any?>>()
        val c = ManualAntControl(target, { time }, { link }, { bytes, _ ->
            failure?.let { throw it }; frames.add(bytes.copyOf())
        }, events::add)
    }
    @Test fun exactOriginalEncodingAndHardBounds() {
        assertEquals("33 FF FF FF FF 20 4E FF", hex(encodeManualSlope(0.0)))
        assertEquals("33 FF FF FF FF 52 4E FF", hex(encodeManualSlope(0.5)))
        assertEquals("33 FF FF FF FF 84 4E FF", hex(encodeManualSlope(1.0)))
        for (v in listOf(-0.5,1.5,0.25,Double.NaN,Double.POSITIVE_INFINITY,Double.NEGATIVE_INFINITY)) {
            try { encodeManualSlope(v); fail("Debe rechazar $v") } catch (_: IllegalArgumentException) {}
        }
    }
    @Test fun explicitActivationSendsNothingAndDefaultStopSendsNothing() {
        val r = Rig()
        assertEquals("rejected", r.c.request(0.5)["event"])
        assertEquals("activation_rejected", r.c.enable(false)["event"])
        assertTrue(r.frames.isEmpty())
        assertFalse(r.c.stop("exit", true)); assertTrue(r.frames.isEmpty())
        val armed = Rig()
        assertEquals("enabled", armed.c.enable(true)["event"])
        assertTrue(armed.frames.isEmpty())
        assertEquals("already_enabled", armed.c.enable(true)["reason"])
    }
    @Test fun onlyExactIdentityModelAndFreshDedicatedTelemetryCanEnable() {
        val wrong = Rig(AntTrainerIdentity(1,112,5)); wrong.c.enable(true)
        assertEquals("wrong_target", wrong.events.last()["reason"]); assertTrue(wrong.frames.isEmpty())
        val r = Rig()
        for (link in listOf(r.link.copy(dedicated=false),r.link.copy(identityVerified=false),r.link.copy(model=24),r.link.copy(manufacturer=1),
            r.link.copy(signalAgeMs=null), r.link.copy(signalAgeMs=3000),r.link.copy(telemetryFresh=false))) {
            r.link=link; assertEquals("activation_rejected",r.c.enable(true)["event"])
        }
        assertTrue(r.frames.isEmpty())
    }
    @Test fun noDuplicateNoUnnecessaryRetryAndThrottle() {
        val r = Rig(); r.c.enable(true)
        r.c.request(0.0); assertEquals(1,r.frames.size)
        r.c.request(0.0); assertEquals("duplicate_skipped",r.events.last()["event"])
        r.c.request(0.5); assertEquals("rate_limited",r.events.last()["reason"])
        r.time=1000; r.c.request(0.5)
        r.time=2000; r.c.request(1.0)
        assertEquals(listOf("33 FF FF FF FF 20 4E FF","33 FF FF FF FF 52 4E FF","33 FF FF FF FF 84 4E FF"),r.frames.map(::hex))
        assertEquals("unconfirmed",r.c.snapshot()["physicalApplication"])
        assertEquals(0,r.c.snapshot()["pendingCommands"])
    }
    @Test fun stopRequestsZeroOnceEvenIfZeroWasPreviouslySubmittedAndNeverRearms() {
        val r = Rig();r.c.enable(true);r.c.request(0.0)
        assertTrue(r.c.stop("user_stop",true)); assertEquals(2,r.frames.size)
        assertEquals("33 FF FF FF FF 20 4E FF",hex(r.frames.last()))
        assertFalse(r.c.stop("duplicate_stop",true));assertEquals(2,r.frames.size)
        assertEquals("session_requires_reconnect",r.c.enable(true)["reason"])
        r.c.request(1.0);assertEquals(2,r.frames.size)
        assertEquals("zero_api_returned_unconfirmed",r.c.snapshot()["stopResult"])
    }
    @Test fun timeoutDoesNotExtendOnRepeatedActivationAndStopsAtZero() {
        val r = Rig();r.c.enable(true);r.time=29000;r.c.enable(true);r.time=30000
        assertEquals("test_timeout",r.c.abortReason())
        r.c.request(1.0);assertTrue(r.frames.isEmpty())
        assertTrue(r.c.stop("test_timeout",true));assertEquals(1,r.frames.size)
    }
    @Test fun signalLossBlocksPendingCommandAndRecoveryNeverReplays() {
        val r=Rig();r.c.enable(true);r.c.request(0.5);r.time=1000;r.link=r.link.copy(signalAgeMs=3000)
        assertTrue(r.c.abortReason()!!.startsWith("link_lost"))
        r.c.request(1.0);assertEquals(1,r.frames.size)
        assertFalse(r.c.stop("signal_lost",false));r.link=r.link.copy(signalAgeMs=0)
        r.c.request(1.0);r.c.enable(true);assertEquals(1,r.frames.size)
    }
    @Test fun apiErrorRetainsBytesExceptionAndDisablesFurtherTransmission() {
        val r=Rig();r.c.enable(true);r.failure=IllegalStateException("simulated IPC failure")
        val e=r.c.request(0.5)
        assertEquals("api_error",e["event"])
        assertEquals("33 FF FF FF FF 52 4E FF",e["payloadHex"])
        assertEquals("simulated IPC failure",(e["error"] as Map<*,*>)["message"])
        assertEquals(false,e["apiReturned"])
        assertTrue(r.frames.isEmpty());assertEquals(true,r.c.snapshot()["faulted"])
        r.failure=null;r.time=2000;r.c.request(1.0)
        assertFalse(r.c.stop("api_error",true));assertTrue(r.frames.isEmpty())
        assertEquals(1,r.events.count { it["event"]=="api_attempt" })
    }
    @Test fun freshLinkIsRecheckedForEveryRequestAndStop() {
        val r=Rig();r.c.enable(true);r.link=r.link.copy(model=24)
        r.c.request(0.5);assertTrue(r.frames.isEmpty())
        assertFalse(r.c.stop("model_changed",true));assertTrue(r.frames.isEmpty())
    }
}
