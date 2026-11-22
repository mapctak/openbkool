package com.example.openbkool

import org.junit.Assert.*
import org.junit.Test

/** Simulated API and monotonic clock; never opens an ANT channel. */
class LatestManualChangeTest {
    private class Sim {
        var now=0L
        var link=ManualControlLink(true,true,67,22,0,true)
        var waiting=false
        var beforeApi:((Map<String,Any?>)->Unit)?=null
        var inApi:((Boolean)->Unit)?=null
        var fail=false
        val frames=mutableListOf<Pair<Long,String>>()
        val events=mutableListOf<Map<String,Any?>>()
        val c:ManualAntControl by lazy { ManualAntControl(AntTrainerIdentity(30064,112,5),{now},{link}, {bytes,stop ->
            c.recordApiEntry();frames.add(now to hex(bytes));inApi?.invoke(stop)
            if(fail)throw IllegalStateException("simulated IPC failure")
        }, {events.add(it);if(it["event"]=="api_attempt")beforeApi?.invoke(it)},manualPriorityWaiting={waiting}) }
        fun arm()=c.enable(true)
        fun tick(t:Long){now=t;c.supervise();c.refreshTarget()}
        fun pending()=c.snapshot()["pendingManualChange"] as Map<*,*>?
    }
    @Test fun rapidStepsKeepOnlyLatestAndDoNotRaiseTransportRate() {
        val sim = Sim()
        sim.arm()
        assertEquals("api_returned", sim.c.request(0.5, rapidAdjustment = true)["event"])
        for (step in 2..6) {
            sim.now = 800L + (step - 2) * 100L
            assertEquals("manual_pending", sim.c.request(step / 2.0, rapidAdjustment = true)["event"])
            sim.c.refreshTarget()
        }
        sim.tick(1379)
        assertEquals(listOf(0L to hex(encodePro1Slope(0.5))), sim.frames)
        sim.tick(1380)
        assertEquals(1380L to hex(encodePro1Slope(3.0)), sim.frames.last())
        assertEquals(2, sim.frames.size)
    }

    @Test fun individualDirectAndFlatBypassQuietWindowWhileStopCancelsAdjustment() {
        val sim = Sim()
        sim.arm()
        assertEquals("api_returned", sim.c.request(3.0)["event"])
        sim.now = 950
        sim.c.request(3.5, rapidAdjustment = true)
        sim.now = 1000
        assertEquals("api_returned", sim.c.request(0.0)["event"])
        assertEquals(1000L to hex(encodePro1Slope(0.0)), sim.frames.last())
        sim.now = 1950
        sim.c.request(4.0, rapidAdjustment = true)
        sim.now = 2000
        assertTrue(sim.c.stop("manual_stop", allowZero = true))
        sim.tick(3000)
        assertEquals(3, sim.frames.size)
        assertEquals(2000L to hex(encodePro1Slope(0.0)), sim.frames.last())
    }

    @Test fun refreshHasSdkTimingWithoutManualRequestLatency() {
        val sim = Sim()
        sim.arm()
        sim.now = 100
        sim.c.request(0.5, requestedAt = 90, uiQueueMs = 30)
        sim.tick(5100)
        val manual = sim.events.first { it["event"] == "api_returned" }
        val refresh = sim.events.last { it["event"] == "api_returned" }
        assertEquals(30L, manual["uiQueueMs"])
        assertEquals(10L, manual["requestToApiEntryMs"])
        assertEquals(true, refresh["periodicRefresh"])
        assertNull(refresh["requestId"])
        assertNull(refresh["requestedAtMs"])
        assertNull(refresh["requestToApiEntryMs"])
        assertEquals(0L, refresh["apiDurationMs"])
    }

    @Test fun firstSubsequentMatchingPage11IsCorrelatedWithoutAcknowledgement() {
        val sim = Sim()
        sim.now = 1000
        sim.arm()
        sim.c.request(0.5, requestedAt = 900, requestedAtUtc = "2026-11-20T19:11:00Z")
        val matching = mapOf("rawWordAtBytes4And5" to 20050, "mechanicalConfirmation" to false,
            "commandAcknowledgement" to false)
        sim.c.observePage11(matching, 1000)
        sim.c.observePage11(matching + ("rawWordAtBytes4And5" to 20000), 1200)
        assertNull(sim.c.snapshot()["lastCompatiblePage11"])
        sim.now = 1500
        sim.c.observePage11(matching, 1500)
        sim.c.observePage11(matching, 1600)
        val observed = sim.events.single { it["event"] == "page11_numeric_match" }
        assertEquals(500L, observed["apiReturnToObservationMs"])
        assertEquals(600L, observed["requestToObservationMs"])
        assertEquals(false, observed["commandAcknowledgement"])
        assertEquals(false, observed["mechanicalConfirmation"])
    }

    @Test fun replayAllEightActualRejectedTimingsNowDefersWithoutRefreshingOldGoal() {
        val rows=javaClass.getResourceAsStream("/s20_rate_limit_1_4_0.csv")!!.bufferedReader().readLines().drop(1)
        for(row in rows) {
            val a=row.split(',');val requested=a[0].toLong();val goal=a[1].toDouble();val previous=a[2].toLong()
            val x=Sim();x.now=previous-5000;x.arm()
            if(a[3]=="true") {x.c.request(a[4].toDouble());x.tick(previous)}
            else {x.now=previous;x.c.request(a[4].toDouble())}
            x.now=requested;assertEquals("manual_pending",x.c.request(goal)["event"])
            assertEquals(goal,x.pending()!!["percent"])
            val count=x.frames.size;x.tick(previous+999);assertEquals(count,x.frames.size)
            x.tick(previous+1000);assertEquals(count+1,x.frames.size)
            assertEquals(hex(encodePro1Slope(goal)),x.frames.last().second)
            assertNull(x.pending());x.tick(previous+5999);assertEquals(count+1,x.frames.size)
            x.tick(previous+6000);assertEquals(hex(encodePro1Slope(goal)),x.frames.last().second)
            assertFalse(x.events.any{it["reason"]=="rate_limited"})
        }
    }
    @Test fun manualAndLlanoAtDueRefreshWinWithoutRaisingTransportRate() {
        for(goal in listOf(0.0,2.0)) {
            val s=Sim();s.arm();s.c.request(3.0)
            s.now=5000;s.c.request(goal);s.c.refreshTarget()
            assertEquals(2,s.frames.size);assertEquals(hex(encodePro1Slope(goal)),s.frames.last().second)
            s.tick(9999);assertEquals(2,s.frames.size);s.tick(10000);assertEquals(3,s.frames.size)
        }
    }
    @Test fun latestWinsAndDuplicateOfAcceptedGoalCancelsDeferredIncrease() {
        val s=Sim();s.arm();s.c.request(3.0);s.tick(5000)
        for((t,p) in listOf(5100L to 2.0,5200L to 1.0,5300L to 0.0)) {s.now=t;s.c.request(p)}
        s.tick(5999);assertEquals(2,s.frames.size);s.tick(6000)
        assertEquals(0.0,(s.c.snapshot()["lastManualApiSuccess"] as Map<*,*>)["requestedPercent"])
        assertEquals(3,s.frames.size)
        s.now=6100;s.c.request(3.0);s.now=6200;s.c.request(0.0)
        assertNull(s.pending());s.tick(7000);assertEquals(3,s.frames.size)
    }
    @Test fun pendingZeroCancelledByStopBackgroundScreenExitOrLinkLossNeverReappears() {
        for(reason in listOf("manual_stop","app_background","screen_closed","channel_closed")) {
            val s=Sim();s.arm();s.c.request(3.0);s.now=100;s.c.request(0.0)
            s.c.invalidateTargets(reason);assertNull(s.pending())
            s.c.stop(reason,reason!="channel_closed");s.c.completeStop(true)
            val count=s.frames.size;s.tick(100000);s.c.flushPending();assertEquals(count,s.frames.size)
        }
        val s=Sim();s.arm();s.c.request(3.0);s.now=100;s.c.request(0.0)
        s.link=s.link.copy(signalAgeMs=3000);s.tick(1000);assertNull(s.pending());assertEquals(1,s.frames.size)
        s.link=s.link.copy(signalAgeMs=0);s.tick(5000);assertEquals(1,s.frames.size)
    }
    @Test fun invalidSlopeDoesNotReplacePendingSlotAndSendErrorKeepsAcceptedValue() {
        val s=Sim();s.arm();s.c.request(3.0);s.now=100;s.c.request(0.0)
        for(p in listOf(-5.5,15.5,Double.NaN)) {assertEquals("rejected",s.c.request(p)["event"]);assertEquals(0.0,s.pending()!!["percent"])}
        s.fail=true;s.tick(1000);assertNull(s.pending())
        assertEquals(3.0,(s.c.snapshot()["lastManualApiSuccess"] as Map<*,*>)["requestedPercent"])
        assertNotNull(s.c.snapshot()["lastApiError"])
        s.tick(10000);assertEquals(2,s.frames.size)
    }
    @Test fun queuedManualInputMakesRefreshYieldEvenJustBeforeApiEntry() {
        val s=Sim();s.arm();s.c.request(3.0)
        s.beforeApi={if(it["periodicRefresh"]==true)s.waiting=true}
        s.tick(5000);assertEquals(1,s.frames.size)
        assertTrue(s.events.any{it["event"]=="refresh_yielded" && it["apiCalled"]==false})
        s.waiting=false;s.c.request(0.0);assertEquals(2,s.frames.size)
        assertEquals(hex(encodePro1Slope(0.0)),s.frames.last().second)
    }
    @Test fun refreshAlreadyInIpcFinishesButNextZeroIsDeferredOnlyUntilItsWindow() {
        val s=Sim();s.arm();s.c.request(3.0)
        s.inApi={if(!it)s.waiting=true};s.tick(5000)
        assertEquals(2,s.frames.size);s.waiting=false;s.now=5100;s.c.request(0.0)
        assertEquals(900L,s.c.nextManualDelayMs());s.tick(6000)
        assertEquals(hex(encodePro1Slope(0.0)),s.frames.last().second)
    }
    @Test fun prolongedRapidChangesKeepOneSlotAndNeverCatchUpOldSteps() {
        val s=Sim();s.arm();s.c.request(0.0)
        for(t in 100L..7200000L step 100L) {
            s.now=t;s.c.request(if((t/100)%2==0L)0.5 else 1.0);s.c.refreshTarget()
            if(t%60000L==0L)s.events.clear()
            assertTrue(s.c.nextManualDelayMs()==null || s.c.nextManualDelayMs()!! in 0L..1000L)
        }
        assertTrue(s.frames.size<=7201)
        assertTrue(s.frames.zipWithNext().all{(a,b)->b.first-a.first>=1000})
        s.c.stop("manual_stop",true);val count=s.frames.size;s.tick(8000000);assertEquals(count,s.frames.size)
    }
}
