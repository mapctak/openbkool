package com.example.openbkool

import org.junit.Assert.*
import org.junit.Test

/** Adversarial models, NOT a claim that ANT Radio Service implements either policy. */
class BroadcastBufferFaultTest {
    private class Radio(val replace: Boolean) {
        val pending = ArrayDeque<String>()
        val aired = mutableListOf<String>()
        fun set(bytes: ByteArray) { if(replace)pending.clear();pending.addLast(hex(bytes)) }
        fun slot() { if(pending.isNotEmpty())aired.add(pending.removeFirst()) }
        fun close(drop: Boolean) { if(drop)pending.clear() else slot() }
    }
    private class Rig(val replace: Boolean) {
        var now = 0L
        val radio = Radio(replace)
        val c=ManualAntControl(AntTrainerIdentity(30064,112,5),{now},
            {ManualControlLink(true,true,67,22,0,true)}, {bytes,_->radio.set(bytes)}, {})
        init{c.enable(true)}
    }
    @Test fun acceptedIncreaseMayNeverBeAiredWhenFuturePayloadReplacesIt() {
        val r=Rig(true);r.c.request(1.0);r.now=1000;r.c.request(0.0)
        assertEquals(0.0,(r.c.snapshot()["lastManualApiSuccess"] as Map<*,*>)["requestedPercent"])
        assertTrue(r.radio.aired.isEmpty())
        r.radio.slot();assertEquals(listOf("33 FF FF FF FF 20 4E FF"),r.radio.aired)
        assertEquals("unconfirmed",r.c.snapshot()["physicalApplication"])
    }
    @Test fun acceptedFlatDoesNotProvePreviouslyQueuedIncreaseCannotStillBeAired() {
        val r=Rig(false);r.c.request(1.0);r.now=1000;r.c.request(0.0)
        assertEquals(0.0,(r.c.snapshot()["lastManualApiSuccess"] as Map<*,*>)["requestedPercent"])
        r.radio.slot();assertEquals("33 FF FF FF FF 84 4E FF",r.radio.aired.single())
        assertEquals("unconfirmed",r.c.snapshot()["physicalApplication"])
    }
    @Test fun zeroApiReturnDoesNotProveDeliveryBeforeCloseInEitherModel() {
        for(replace in listOf(true,false))for(drop in listOf(true,false)){
            val r=Rig(replace);r.c.request(1.0);r.now=1000
            assertTrue(r.c.stop("manual_stop",true))
            r.radio.close(drop);r.c.completeStop(true)
            assertEquals("zero_api_returned_unconfirmed",r.c.snapshot()["stopResult"])
            assertEquals("unknown",r.c.snapshot()["resistanceAfterClose"])
            assertEquals("unconfirmed",r.c.snapshot()["physicalApplication"])
            if(drop)assertTrue(r.radio.aired.isEmpty())
        }
    }
}
