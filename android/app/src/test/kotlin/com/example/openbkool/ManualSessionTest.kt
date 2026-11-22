package com.example.openbkool

import org.junit.Assert.*
import org.junit.Test

class ManualSessionTest {
    private class Sim {
        var time = 0L
        var link = ManualControlLink(true,true,67,22,0,true)
        var fail = false
        val frames = mutableListOf<String>()
        val events = mutableListOf<Map<String,Any?>>()
        val c = ManualAntControl(AntTrainerIdentity(30064,112,5),{time},{link},{b,_ ->
            if(fail) throw IllegalStateException("simulated IPC error")
            frames.add(hex(b))
        },events::add)
        fun arm()=c.enable(true)
        fun tick(t: Long) { time=t;c.supervise();c.refreshTarget() }
    }
    @Test fun fullOriginalDomainHasExactly41HalfPointEncodingsAndRejectsInvalidValues() {
        val values=(-10..30).map{it/2.0}
        assertEquals(41,values.size);assertEquals(1,values.count{it==0.0})
        for(p in values){
            val expected=((p.toFloat()+200f)*100f).toInt()
            val b=encodePro1Slope(p)
            assertEquals(expected,(b[5].toInt() and 255) or ((b[6].toInt() and 255) shl 8))
            assertEquals("33 FF FF FF FF",hex(b.copyOfRange(0,5)))
            assertEquals(255,b[7].toInt() and 255)
        }
        assertEquals("33 FF FF FF FF 2C 4C FF",hex(encodePro1Slope(-5.0)))
        assertEquals("33 FF FF FF FF EE 4D FF",hex(encodePro1Slope(-0.5)))
        assertEquals("33 FF FF FF FF 20 4E FF",hex(encodePro1Slope(0.0)))
        assertEquals("33 FF FF FF FF FC 53 FF",hex(encodePro1Slope(15.0)))
        for(p in listOf(-5.5,15.5,0.25,-0.25,Double.NaN,Double.NEGATIVE_INFINITY,Double.POSITIVE_INFINITY)){
            try{encodePro1Slope(p);fail("invalid $p")}catch(_:IllegalArgumentException){}
        }
    }
    @Test fun fullRangeRequiresExplicitAuthorizationForEverySession() {
        val s = Sim()
        assertEquals("explicit_full_range_authorization_required", s.c.enable(false)["reason"])
        for (value in -10..30) assertEquals("rejected", s.c.request(value / 2.0)["event"])
        assertTrue(s.frames.isEmpty())
        assertEquals("enabled", s.arm()["event"])
        assertTrue(s.frames.isEmpty())
        for (value in -10..30) {
            s.time += 1000
            assertEquals("api_returned", s.c.request(value / 2.0)["event"])
            assertEquals(hex(encodePro1Slope(value / 2.0)), s.frames.last())
        }
        assertEquals(41, s.frames.size)
        s.c.stop("user_finish", true)
        assertEquals("activation_rejected", s.arm()["event"])
        assertEquals("rejected", Sim().c.request(15.0)["event"])
    }
    @Test fun twoHoursRefreshCurrentGoalWithoutDeadlineAndStopLeavesNoScheduledSends() {
        val s=Sim();s.arm();s.c.request(15.0)
        for(second in 1L..7200L){s.tick(second*1000);assertNull(s.c.abortReason())}
        assertEquals(1441,s.frames.size)
        assertEquals(1440,s.events.count{it["event"]=="periodic_refresh"})
        assertEquals("active",s.c.snapshot()["state"])
        s.c.stop("user_finish",true);s.c.completeStop(true)
        assertEquals("33 FF FF FF FF 20 4E FF",s.frames.last())
        val count=s.frames.size
        for(second in 7201L..7300L){s.tick(second*1000);s.c.request(15.0)}
        assertEquals(count,s.frames.size);assertEquals("stopped",s.c.snapshot()["state"])
        assertEquals("unknown",s.c.snapshot()["resistanceAfterClose"])
    }
    @Test fun refreshUsesLastAcceptedGoalAndCoalescesMissedIntervalsWithoutCatchUpQueue() {
        val s=Sim();s.arm();s.c.request(3.0)
        s.tick(4999);assertEquals(1,s.frames.size)
        s.c.request(-2.0);s.tick(5000);assertEquals(2,s.frames.size)
        s.tick(9999);assertEquals(3,s.frames.size)
        assertEquals(hex(encodePro1Slope(-2.0)),s.frames.last())
        s.tick(60000);assertEquals(4,s.frames.size)
        s.tick(60000);assertEquals(4,s.frames.size)
        s.c.request(15.0);assertEquals("manual_pending",(s.c.snapshot()["lastResult"] as Map<*,*>)["event"])
        s.tick(65000);assertEquals(hex(encodePro1Slope(15.0)),s.frames.last())
        s.time=66000;s.c.request(0.0);s.tick(71000)
        assertEquals(hex(encodePro1Slope(0.0)),s.frames.last())
    }
    @Test fun rateLimitsAndDuplicateChangesDoNotReplaceAcceptedTarget() {
        val s=Sim();s.arm();s.c.request(0.5)
        s.time=999;assertEquals("manual_pending",s.c.request(15.0)["event"])
        assertEquals("duplicate_skipped",s.c.request(0.5)["event"])
        s.tick(5000);assertEquals(hex(encodePro1Slope(0.5)),s.frames.last())
        s.time=6000;s.c.request(15.0);s.tick(11000)
        assertEquals(hex(encodePro1Slope(15.0)),s.frames.last())
    }
    @Test fun staleTelemetryLatchesLossAndCancelsRefreshEvenAfterFreshDataReturns() {
        val s=Sim();s.arm();s.c.request(3.0)
        s.link=s.link.copy(signalAgeMs=3000,telemetryFresh=false);s.tick(5000)
        assertEquals(1,s.frames.size);assertEquals("error",s.c.snapshot()["state"])
        s.link=s.link.copy(signalAgeMs=0,telemetryFresh=true);s.tick(10000);s.c.request(4.0)
        assertEquals(1,s.frames.size)
        s.c.stop("link_lost:signal_not_fresh",true);s.c.completeStop(true)
        assertEquals(hex(encodePro1Slope(0.0)),s.frames.last())
        assertEquals("activation_rejected",s.arm()["event"])
    }
    @Test fun channelLossWrongIdentityOrManufacturerCannotRefreshOrRearm() {
        for(link in listOf(ManualControlLink(true,true,67,22,0,true,channelOpen=false),
            ManualControlLink(true,true,67,22,0,true,activeIdentityMatches=false),
            ManualControlLink(true,true,67,24,0,true))) {
            val s=Sim();s.arm();s.c.request(3.0);s.link=link;s.tick(5000)
            s.c.request(15.0);s.c.stop("disconnected",true);s.c.completeStop(true)
            assertEquals(1,s.frames.size);assertEquals("error",s.c.snapshot()["state"])
            s.link=ManualControlLink(true,true,67,22,0,true);s.arm();s.tick(10000)
            assertEquals(1,s.frames.size)
        }
    }
    @Test fun backgroundScreenExitAndManualStopPreventPendingOrLateRefreshes() {
        for(reason in listOf("app_background","screen_closed","user_finish")) {
            val s=Sim();val queue=ManualCommandFence();s.arm();s.c.request(-5.0)
            queue.enqueue();queue.cancel(reason)
            s.c.stop(reason,true);s.c.completeStop(true)
            if(queue.dequeue()==null)s.c.request(15.0)
            s.tick(30000);assertEquals(2,s.frames.size)
            assertEquals(hex(encodePro1Slope(0.0)),s.frames.last())
            assertEquals(reason,s.c.snapshot()["stopReason"])
        }
    }
    @Test fun failedRefreshOrStopIsLoggedWithoutClearingLastAcceptedTargetOrClaimingPhysicalReset() {
        for(failOnRefresh in listOf(true,false)) {
            val s=Sim();s.arm();s.c.request(3.0);s.fail=true
            if(failOnRefresh)s.tick(5000)
            s.c.stop("user_finish",true);s.c.completeStop(true)
            assertEquals(1,s.frames.size);assertEquals("error",s.c.snapshot()["state"])
            assertEquals(3.0,(s.c.snapshot()["lastManualApiSuccess"] as Map<*,*>)["requestedPercent"])
            assertEquals("unknown",s.c.snapshot()["resistanceAfterClose"])
            assertTrue(s.events.any{it["event"]=="api_error"})
        }
    }
}
