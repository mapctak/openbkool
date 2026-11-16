package com.example.openbkool

import org.junit.Assert.*
import org.junit.Test

class IsolatedThreePercentTest {
    private class Sim {
        var now = 0L
        var link = ManualControlLink(true,true,67,22,0,true)
        var fail = false
        val frames = mutableListOf<String>()
        val events = mutableListOf<Map<String,Any?>>()
        val c = ManualAntControl(AntTrainerIdentity(30064,112,5), {now}, {link}, {b,_ ->
            if(fail) throw IllegalStateException("simulated IPC failure")
            frames.add(hex(b))
        }, events::add)
        fun arm() = c.enable(true,"isolated_three_percent",true)
    }
    @Test fun consentIsSpecificAndArmingDoesNotTransmit() {
        val s=Sim()
        assertEquals("explicit_activation_required",s.c.enable(false,"isolated_three_percent",true)["reason"])
        assertEquals("isolated_three_confirmation_required",s.c.enable(true,"isolated_three_percent")["reason"])
        s.c.enable(true);assertEquals("experimental_level_not_authorized",s.c.request(3.0)["reason"])
        assertEquals("already_enabled",s.arm()["reason"])
        assertTrue(s.frames.isEmpty())
        val fresh=Sim();assertEquals("enabled",fresh.arm()["event"]);assertTrue(fresh.frames.isEmpty())
        assertEquals("invalid_control_mode",Sim().c.enable(true,"isolated_four_percent",true)["reason"])
    }
    @Test fun threeIsSingleUseAndFourNeverUnlocksAfterAcceptedThree() {
        val s=Sim();s.arm();s.c.request(3.0)
        assertEquals(listOf("33 FF FF FF FF 4C 4F FF"),s.frames)
        assertEquals("api_returned",s.c.snapshot()["lastResult"].let{(it as Map<*,*>)["event"]})
        s.now=1000;s.c.request(0.0);s.now=2000
        assertEquals("isolated_three_already_attempted",s.c.request(3.0)["reason"])
        assertEquals("experimental_level_not_authorized",s.c.request(4.0)["reason"])
        assertEquals("experimental_level_not_authorized",s.c.request(2.0)["reason"])
        assertEquals("invalid_control_mode",s.c.enable(true,"isolated_four_percent",true)["reason"])
        assertEquals(2,s.frames.size)
        assertEquals(3.0,s.c.snapshot()["operationalMaxPercent"])
        assertTrue(s.c.snapshot()["threePercentAttempted"]==true)
    }
    @Test fun rateLimitAndDeadlineAreNotExtendedByRequests() {
        val s=Sim();s.arm();s.c.request(1.0);s.now=999
        assertEquals("rate_limited",s.c.request(3.0)["reason"])
        assertFalse(s.c.snapshot()["threePercentAttempted"] as Boolean)
        s.now=1000;s.c.request(3.0)
        for(second in 2L..29L){s.now=second*1000;s.c.supervise()}
        assertEquals(2,s.frames.size)
        s.now=30000;assertEquals("test_timeout",s.c.abortReason());s.c.request(0.5)
        s.c.stop("test_timeout",true);s.c.completeStop(true)
        assertEquals(3,s.frames.size);assertEquals("33 FF FF FF FF 20 4E FF",s.frames.last())
        assertEquals("unknown",s.c.snapshot()["resistanceAfterClose"])
        assertEquals("activation_rejected",s.arm()["event"])
    }
    @Test fun identityAndLinkGuardsCannotBeBypassed() {
        for(link in listOf(ManualControlLink(true,true,67,24,0,true),
            ManualControlLink(true,false,67,22,0,true),
            ManualControlLink(true,true,67,22,0,true,activeIdentityMatches=false))) {
            val s=Sim();s.link=link;assertEquals("activation_rejected",s.arm()["event"])
            s.c.request(3.0);assertTrue(s.frames.isEmpty())
        }
        val s=Sim();s.arm();s.link=s.link.copy(channelOpen=false)
        s.c.request(3.0);s.c.stop("disconnected",false);s.c.completeStop(true)
        assertTrue(s.frames.isEmpty());assertEquals("error",s.c.snapshot()["state"])
    }
    @Test fun manualAndBackgroundStopsRequestZeroAndDoNotRearm() {
        for(reason in listOf("manual_stop","app_background","screen_closed")) {
            val s=Sim();s.arm();s.c.request(3.0);s.c.stop(reason,true);s.c.completeStop(true)
            assertEquals("33 FF FF FF FF 20 4E FF",s.frames.last())
            assertEquals(reason,s.c.snapshot()["stopReason"])
            assertEquals("activation_rejected",s.arm()["event"])
            s.c.request(3.0);assertEquals(2,s.frames.size)
        }
    }
    @Test fun failureConsumesAttemptAndStopDoesNotClaimMechanicalReset() {
        val s=Sim();s.arm();s.fail=true;s.c.request(3.0)
        assertTrue(s.c.snapshot()["threePercentAttempted"]==true)
        assertNull(s.c.snapshot()["lastManualApiSuccess"])
        assertTrue(s.events.any{it["event"]=="api_error"})
        s.fail=false;s.c.stop("manual_api_error",true);s.c.completeStop(true)
        assertTrue(s.frames.isEmpty());assertEquals("error",s.c.snapshot()["state"])
        assertEquals("unknown",s.c.snapshot()["resistanceAfterClose"])
    }
}
