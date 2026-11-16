package com.example.openbkool

import org.junit.Assert.*
import org.junit.Test
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

class ContinuousManualControlTest {
    private class Sim(allowContinuous: Boolean = true) {
        var time = 0L
        var link = ManualControlLink(true,true,67,22,0,true)
        var failZero = false
        val frames = mutableListOf<String>()
        val events = mutableListOf<Map<String,Any?>>()
        val c = ManualAntControl(AntTrainerIdentity(30064,112,5), {time}, {link}, {bytes,_ ->
            if (failZero && bytes.contentEquals(encodeManualSlope(0.0))) throw IllegalStateException("zero IPC failed")
            frames.add(hex(bytes))
        }, events::add, continuousAllowed = allowContinuous)
        fun arm() = c.enable(true, "continuous_experimental")
    }
    @Test fun productionDefaultRejectsContinuousEvenWithExplicitActivation() {
        assertFalse(ManualControlPolicy.CONTINUOUS_PHYSICAL_ENABLED)
        val s = Sim(false)
        assertEquals("continuous_physical_validation_required", s.arm()["reason"])
        s.c.request(1.0); assertTrue(s.frames.isEmpty())
        assertEquals("trial_30s", s.c.snapshot()["mode"])
        assertEquals("enabled", s.c.enable(true)["event"])
        s.time=30000; assertEquals("test_timeout",s.c.abortReason())
    }
    @Test fun twoHoursWithRepeatedChangesAndExplicitStopNoFixedDeadlineInSimulation() {
        val s = Sim(); assertEquals("enabled", s.arm()["event"])
        assertTrue(s.frames.isEmpty())
        for (second in 0L..7200L) {
            s.time=second*1000
            s.c.supervise(); assertNull(s.c.abortReason())
            if (second % 30L == 0L) s.c.request(if ((second/30)%2 == 0L) 0.5 else 1.0)
        }
        val state=s.c.snapshot()
        assertNull(state["maxDurationMs"]); assertNull(state["remainingMs"])
        assertEquals(7200000L,state["elapsedControlMs"])
        assertEquals("active",state["state"]); assertEquals(241,s.frames.size)
        s.c.stop("manual_stop",true);s.c.completeStop(true)
        assertEquals("stopped",s.c.snapshot()["state"])
        assertEquals("33 FF FF FF FF 20 4E FF",s.frames.last())
        s.time+=86400000; s.arm();s.c.request(1.0)
        assertEquals(242,s.frames.size);assertEquals(7200000L,s.c.snapshot()["elapsedControlMs"])
    }
    @Test fun lostTelemetryBlocksIncreasesButStopZeroUsesStillIdentifiedOpenChannel() {
        val s=Sim();s.arm();s.c.request(1.0);s.time=45000
        s.link=s.link.copy(signalAgeMs=3000,telemetryFresh=false)
        s.c.supervise();s.c.request(0.5)
        assertEquals(1,s.frames.size)
        assertTrue(s.c.stop("link_lost:signal_not_fresh",true));s.c.completeStop(true)
        assertEquals(2,s.frames.size);assertEquals("error",s.c.snapshot()["state"])
        s.link=s.link.copy(signalAgeMs=0,telemetryFresh=true);s.arm();s.c.request(1.0)
        assertEquals(2,s.frames.size)
    }
    @Test fun closedChannelOrWrongIdentityCannotReceiveStopAndEndsInError() {
        for (link in listOf(ManualControlLink(true,true,67,22,0,true,channelOpen=false),
            ManualControlLink(true,true,67,22,0,true,activeIdentityMatches=false),
            ManualControlLink(true,true,67,24,0,true), ManualControlLink(true,true,67,22,0,true,radioAvailable=false))) {
            val s=Sim();s.arm();s.c.request(1.0);s.link=link;s.time=60000
            s.c.request(0.5);assertFalse(s.c.stop("disconnected",true));s.c.completeStop(true)
            assertEquals(1,s.frames.size);assertEquals("error",s.c.snapshot()["state"])
            assertTrue((s.c.snapshot()["stopResult"] as String).startsWith("zero_not_requested"))
        }
    }
    @Test fun failedZeroIsAnErrorAndDoesNotEraseLastAcceptedManualOrder() {
        val s=Sim();s.arm();s.c.request(1.0);s.failZero=true
        assertFalse(s.c.stop("manual_stop",true));s.c.completeStop(true)
        assertEquals("zero_api_error",s.c.snapshot()["stopResult"])
        assertEquals("error",s.c.snapshot()["state"])
        assertEquals(1.0,(s.c.snapshot()["lastManualApiSuccess"] as Map<*,*>)["requestedPercent"])
        assertEquals("api_error",(s.c.snapshot()["lastStopCommand"] as Map<*,*>)["event"])
    }
    @Test fun backgroundStopsContinuousAndReconnectionRequiresNewExplicitActivation() {
        val s=Sim();s.arm();s.time=60000;s.c.request(0.5)
        s.c.stop("app_background",true);s.c.completeStop(true)
        s.time=90000;s.arm();s.c.request(1.0);assertEquals(2,s.frames.size)
        val fresh=Sim();fresh.c.request(1.0);assertTrue(fresh.frames.isEmpty())
        assertEquals("activation_rejected",fresh.c.enable(false,"continuous_experimental")["event"])
        fresh.arm();assertTrue(fresh.frames.isEmpty());fresh.c.request(0.5);assertEquals(1,fresh.frames.size)
    }
    @Test fun queuedCommandsAreCancelledWithoutWaitingForInFlightTransport() {
        val queue=ManualCommandFence()
        val worker=Executors.newSingleThreadExecutor()
        val entered=CountDownLatch(1);val release=CountDownLatch(1)
        val s=Sim();s.arm()
        try {
            worker.submit { entered.countDown();release.await(2,TimeUnit.SECONDS) }
            assertTrue(entered.await(2,TimeUnit.SECONDS))
            val tasks=(1..3).map {
                queue.enqueue()
                worker.submit { if(queue.dequeue()==null)s.c.request(1.0) }
            }
            queue.cancel("manual_stop") // Must return while worker is blocked.
            assertEquals(3,queue.snapshot()["pendingApplicationCommands"])
            release.countDown();tasks.forEach{it.get(2,TimeUnit.SECONDS)}
            assertTrue(s.frames.isEmpty());assertEquals(0,queue.snapshot()["pendingApplicationCommands"])
            queue.cancel("app_background");assertEquals("manual_stop",queue.snapshot()["cancelReason"])
            queue.enqueue();assertEquals("manual_stop",queue.dequeue())
            assertEquals("unknown",queue.snapshot()["radioBufferPending"])
        } finally { release.countDown();worker.shutdownNow() }
    }
}
