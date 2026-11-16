package com.example.openbkool

import org.junit.Assert.*
import org.junit.Test

class IsolatedTwoPercentTest {
    private class Sim {
        var now = 0L
        var link = ManualControlLink(true,true,67,22,0,true)
        var fail = false
        val frames = mutableListOf<String>()
        val events = mutableListOf<Map<String,Any?>>()
        val c = ManualAntControl(AntTrainerIdentity(30064,112,5), {now}, {link}, {b,_ ->
            if (fail) throw IllegalStateException("simulated IPC failure")
            frames.add(hex(b))
        }, events::add)
        fun arm() = c.enable(true,"isolated_two_percent",true)
    }
    @Test fun requiresBothConsentsAndNeverSendsWhenArmed() {
        val s=Sim()
        assertEquals("explicit_activation_required",s.c.enable(false,"isolated_two_percent",true)["reason"])
        assertEquals("isolated_two_confirmation_required",s.c.enable(true,"isolated_two_percent")["reason"])
        s.c.request(2.0); assertTrue(s.frames.isEmpty())
        assertEquals("enabled",s.arm()["event"]); assertTrue(s.frames.isEmpty())
    }
    @Test fun oneTwoPercentOnlyWithNormalZeroStopAndNoPeriodicResend() {
        val s=Sim();s.arm();s.c.request(2.0)
        assertEquals(listOf("33 FF FF FF FF E8 4E FF"),s.frames)
        s.now=1000;s.c.request(0.0);s.now=2000
        assertEquals("isolated_two_already_attempted",s.c.request(2.0)["reason"])
        for(second in 3L..29L){s.now=second*1000;s.c.supervise()}
        assertEquals(2,s.frames.size)
        s.now=30000;assertEquals("test_timeout",s.c.abortReason())
        s.c.stop("test_timeout",true);s.c.completeStop(true)
        assertEquals("33 FF FF FF FF 20 4E FF",s.frames.last())
        assertEquals(3,s.frames.size)
        assertEquals("unknown",s.c.snapshot()["resistanceAfterClose"])
        assertTrue(s.events.any{it["event"]=="api_returned" && it["requestedPercent"]==2.0})
    }
    @Test fun wrongModelOrIdentityAndLostLinkCannotUseExperiment() {
        for(link in listOf(ManualControlLink(true,true,67,24,0,true),
            ManualControlLink(true,true,67,22,0,true,activeIdentityMatches=false),
            ManualControlLink(true,false,67,22,0,true))) {
            val s=Sim();s.link=link;assertEquals("activation_rejected",s.arm()["event"])
            s.c.request(2.0);assertTrue(s.frames.isEmpty())
        }
        val s=Sim();s.arm();s.link=s.link.copy(channelOpen=false)
        s.c.request(2.0);s.c.stop("disconnected",false);assertTrue(s.frames.isEmpty())
    }
    @Test fun noThreeIntermediateOrAutomaticRearmAndApiFailureIsLogged() {
        val s=Sim();s.arm()
        for(p in listOf(-0.5,1.5,2.5,3.0,4.0,Double.NaN)){s.c.request(p)}
        assertTrue(s.frames.isEmpty());s.fail=true;s.c.request(2.0)
        assertEquals("api_error",s.c.snapshot()["lastResult"].let{(it as Map<*,*>)["event"]})
        assertTrue(s.c.snapshot()["twoPercentAttempted"]==true)
        s.fail=false;s.c.stop("manual_api_error",true);s.c.completeStop(true)
        assertEquals("activation_rejected",s.arm()["event"])
        assertTrue(s.frames.isEmpty())
    }
}
