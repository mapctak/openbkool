package com.example.openbkool

import org.junit.Assert.*
import org.junit.Test
import java.util.Collections
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicLong

/** Every API, clock and channel here is simulated; no Android/ANT service is opened. */
class RefreshTrialTest {
    private class Sim {
        val time = AtomicLong(0)
        @Volatile var link = ManualControlLink(true,true,67,22,0,true)
        var failZero = false
        var beforeEntry: ((ByteArray,Boolean)->Unit)? = null
        var inApi: ((ByteArray,Boolean)->Unit)? = null
        var onEvent: ((Map<String,Any?>)->Unit)? = null
        val calls = Collections.synchronizedList(mutableListOf<String>())
        val events = mutableListOf<Map<String,Any?>>()
        val audit = AntTransmissionAudit(time::get)
        val c: ManualAntControl by lazy { ManualAntControl(AntTrainerIdentity(30064,112,5),time::get,{link},{b,stop ->
            beforeEntry?.invoke(b,stop)
            c.recordApiEntry()
            calls.add(hex(b))
            inApi?.invoke(b,stop)
            if(stop && failZero) throw IllegalStateException("simulated zero failed")
        },{ events.add(it);onEvent?.invoke(it) }) }
        fun arm(mode:String="refresh_trial_30s")=c.enable(true,mode,true)
        fun tick(t:Long){time.set(t);c.supervise();c.refreshTarget()}
        fun finish(reason:String="manual_stop") {
            c.stop(reason,link.channelOpen)
            audit.closeRequested();time.incrementAndGet();audit.closeApiReturned()
            time.incrementAndGet();audit.observe(7);c.completeStop(true)
        }
    }
    @Test fun lowLoadNeedsSeparateConsentAndKeepsFullRangeBlocked() {
        val s=Sim()
        assertEquals("explicit_activation_required",s.c.enable(false,"manual_low_load",true)["reason"])
        assertEquals("low_load_risk_consent_required",s.c.enable(true,"manual_low_load")["reason"])
        assertEquals("enabled",s.arm("manual_low_load")["event"])
        assertTrue(s.calls.isEmpty());assertNull(s.c.snapshot()["maxDurationMs"])
        for(p in listOf(-5.0,-0.5,0.25,1.0,2.0,3.0,4.0,15.0,Double.NaN))s.c.request(p)
        assertTrue(s.calls.isEmpty());assertTrue(ManualControlPolicy.MANUAL_SESSION_PHYSICAL_ENABLED)
        assertFalse(ManualControlPolicy.CONTINUOUS_PHYSICAL_ENABLED)
        val blocked=Sim()
        assertEquals("activation_rejected",blocked.arm("manual_session")["event"])
    }
    @Test fun lowLoadTwoHoursRefreshesCurrentGoalAndStopsWithoutAnyLaterOrder() {
        val s=Sim();s.arm("manual_low_load");s.c.request(0.5)
        for(t in 5000L..7200000L step 5000L)s.tick(t)
        assertEquals(1441,s.calls.size);assertNull(s.c.abortReason())
        s.time.set(7201000);s.c.request(0.0);s.tick(7205999)
        assertEquals(1442,s.calls.size);s.tick(7206000)
        assertEquals(hex(encodeManualSlope(0.0)),s.calls.last())
        s.c.invalidateTargets("manual_stop");s.finish();val count=s.calls.size
        s.tick(14400000);assertEquals(count,s.calls.size)
        assertEquals("activation_rejected",s.arm("manual_low_load")["event"])
    }
    @Test fun lowLoadLossAndBackgroundRemainTerminalAndZeroFailureVisible() {
        for(reason in listOf("app_background","screen_closed","manual_stop")) {
            val s=Sim();s.arm("manual_low_load");s.c.request(0.5)
            s.c.invalidateTargets(reason);s.failZero=true;s.finish(reason);s.tick(60000)
            assertEquals("zero_api_error",s.c.snapshot()["stopResult"])
            assertEquals("error",s.c.snapshot()["state"]);assertEquals(2,s.calls.size)
        }
        for(bad in listOf(ManualControlLink(true,true,67,22,3000,false),
            ManualControlLink(true,true,67,22,0,true,channelOpen=false),
            ManualControlLink(true,true,67,24,0,true))) {
            val s=Sim();s.arm("manual_low_load");s.c.request(0.5);s.link=bad;s.tick(5000)
            assertNotNull(s.c.abortReason());assertEquals(1,s.calls.size)
            s.link=ManualControlLink(true,true,67,22,0,true);s.tick(60000)
            assertEquals(1,s.calls.size)
        }
    }
    @Test fun trialRequiresConsentAndOnlyZeroOrHalfAndNeverUnlocksUnlimited() {
        val s=Sim()
        assertEquals("explicit_activation_required",s.c.enable(false,"refresh_trial_30s",true)["reason"])
        assertEquals("refresh_trial_confirmation_required",s.c.enable(true,"refresh_trial_30s")["reason"])
        assertEquals("enabled",s.arm()["event"]);assertTrue(s.calls.isEmpty())
        for(p in listOf(-0.5,0.25,1.0,2.0,3.0,15.0,Double.NaN)){s.c.request(p)}
        assertTrue(s.calls.isEmpty());assertEquals(30000L,s.c.snapshot()["maxDurationMs"])
        assertEquals(0.5,s.c.snapshot()["operationalMaxPercent"])
        assertEquals("manual_range_risk_consent_required",s.c.enable(true,"manual_session")["reason"])
        assertTrue(ManualControlPolicy.MANUAL_SESSION_PHYSICAL_ENABLED)
    }
    @Test fun refreshesAreFiveSecondsApartAndDeadlineBlocksEvenDueRefresh() {
        val s=Sim();s.arm();s.tick(4000);assertTrue(s.calls.isEmpty())
        s.time.set(4000);s.c.request(0.5)
        s.tick(8999);assertEquals(1,s.calls.size)
        s.tick(9000);s.tick(14000);assertEquals(3,s.calls.size)
        s.tick(30000);assertEquals("test_timeout",s.c.abortReason());assertEquals(3,s.calls.size)
        s.finish("test_timeout");assertEquals(hex(encodeManualSlope(0.0)),s.calls.last())
        s.tick(60000);assertEquals(4,s.calls.size)
    }
    @Test fun targetChangeInvalidatesOldRevisionAndDelayedRefreshNeverCatchesUp() {
        val s=Sim();s.arm();s.c.request(0.5)
        s.time.set(4999);s.c.request(0.0);s.tick(5000);assertEquals(2,s.calls.size)
        s.tick(9999);s.tick(25000);s.tick(25000)
        assertEquals(listOf(hex(encodeManualSlope(0.5)),hex(encodeManualSlope(0.0)),
            hex(encodeManualSlope(0.0)),hex(encodeManualSlope(0.0))),s.calls)
        val refreshes=s.events.filter{it["event"]=="api_attempt" && it["periodicRefresh"]==true}
        assertTrue(refreshes.all{it["targetRevision"]==2L && it["requestedPercent"]==0.0})
    }
    @Test fun stopWinsRaceBeforeApiEntryAndStillRequestsOneZero() {
        val s=Sim();s.arm();s.c.request(0.5);s.time.set(5000)
        val ready=CountDownLatch(1);val release=CountDownLatch(1)
        val worker=Executors.newSingleThreadExecutor()
        s.onEvent={if(it["event"]=="api_attempt" && it["periodicRefresh"]==true){ready.countDown();check(release.await(2,TimeUnit.SECONDS))}}
        try {
            val refresh=worker.submit{s.c.refreshTarget()}
            assertTrue(ready.await(2,TimeUnit.SECONDS))
            s.time.set(5001);s.c.invalidateTargets("manual_stop") // UI thread: must not wait for worker/IPC.
            release.countDown();refresh.get(2,TimeUnit.SECONDS)
            worker.submit{s.finish()}.get(2,TimeUnit.SECONDS)
            assertEquals(listOf(hex(encodeManualSlope(0.5)),hex(encodeManualSlope(0.0))),s.calls)
            assertTrue(s.events.any{it["event"]=="command_cancelled" && it["apiCalled"]==false})
            assertNull(s.c.snapshot()["lastApiError"])
            assertEquals(5001L,s.c.snapshot()["stopRequestedAtMs"])
            assertNull(s.c.snapshot()["refreshTargetPercent"])
            s.tick(10000);assertEquals(2,s.calls.size)
        } finally {release.countDown();worker.shutdownNow()}
    }
    @Test fun ipcAlreadyEnteredCannotBeRecalledAndStopWaitsOnSerialWorker() {
        val s=Sim();s.arm();s.c.request(0.5);s.time.set(5000)
        val entered=CountDownLatch(1);val release=CountDownLatch(1)
        val worker=Executors.newSingleThreadExecutor()
        s.inApi={_,stop -> if(!stop){entered.countDown();check(release.await(2,TimeUnit.SECONDS))}}
        try {
            val refresh=worker.submit{s.c.refreshTarget()}
            assertTrue(entered.await(2,TimeUnit.SECONDS))
            s.time.set(5001);s.c.invalidateTargets("manual_stop")
            val stop=worker.submit{s.finish()}
            assertFalse(stop.isDone);release.countDown()
            refresh.get(2,TimeUnit.SECONDS);stop.get(2,TimeUnit.SECONDS)
            assertEquals(3,s.calls.size);assertEquals(hex(encodeManualSlope(0.0)),s.calls.last())
            val stopEvent=s.events.single{it["event"]=="stop_requested"}
            assertEquals(5001L,stopEvent["stopRequestedAtMs"])
            s.tick(15000);assertEquals(3,s.calls.size)
        } finally {release.countDown();worker.shutdownNow()}
    }
    @Test fun preSdkCancellationIsNotAnApiErrorAndDoesNotSuppressStopZero() {
        val s=Sim();s.arm();s.c.request(0.5);s.time.set(5000)
        s.beforeEntry={_,stop -> if(!stop){s.c.invalidateTargets("manual_stop");throw ManualCommandCancelledException()}}
        s.c.refreshTarget();s.finish()
        assertNull(s.c.snapshot()["lastApiError"])
        assertEquals(2,s.calls.size);assertEquals("zero_api_returned_unconfirmed",s.c.snapshot()["stopResult"])
    }
    @Test fun channelClosureDuringApiHasNoPayloadAckAndCannotRestartRefresh() {
        for(throwsError in listOf(true,false)) {
            val s=Sim();s.arm();s.c.request(0.5);s.time.set(5000)
            s.inApi={_,stop -> if(!stop){
                s.time.incrementAndGet();s.audit.observe(7);s.link=s.link.copy(channelOpen=false)
                s.c.invalidateTargets("channel_closed")
                if(throwsError)throw IllegalStateException("simulated channel closed during IPC")
            }}
            s.c.refreshTarget();s.finish("disconnected")
            assertEquals(2,s.calls.size);assertEquals("error",s.c.snapshot()["state"])
            assertEquals("unknown",s.c.snapshot()["resistanceAfterClose"])
            s.link=s.link.copy(channelOpen=true);s.tick(15000);assertEquals(2,s.calls.size)
            assertEquals("activation_rejected",s.arm()["event"])
        }
    }
    @Test fun failedLastZeroIsVisibleAndTimesCanBeComparedWithoutClaimingRfDelivery() {
        val s=Sim();s.arm();s.c.request(0.5);s.tick(5000);s.time.set(5500)
        s.failZero=true;s.c.invalidateTargets("manual_stop");s.finish()
        assertEquals("zero_api_error",s.c.snapshot()["stopResult"])
        assertEquals(0.5,(s.c.snapshot()["lastManualApiSuccess"] as Map<*,*>)["requestedPercent"])
        val stopAttempt=s.events.single{it["event"]=="api_attempt" && it["stopRequest"]==true}
        val entry=s.events.single{it["event"]=="ant_api_entered" && it["commandId"]==stopAttempt["commandId"]}
        val error=s.events.single{it["event"]=="api_error"}
        assertEquals(entry["commandId"],error["commandId"])
        assertEquals(5500L,error["apiErrorAtMs"])
        assertEquals(5500L,s.audit.snapshot()["closeRequestedAtMs"])
        assertEquals(5502L,s.audit.snapshot()["channelClosedEventAtMs"])
        s.audit.observe(3)
        assertEquals("unavailable",(s.audit.snapshot()["channelEvents"] as List<*>).last().let{(it as Map<*,*>)["commandCorrelation"]})
        s.tick(10000);assertEquals(3,s.calls.size)
    }
    @Test fun linkLossAndBackgroundCancelQueuedChangesWithoutAutomaticRecovery() {
        for(reason in listOf("manual_stop","app_background","screen_closed")) {
            val s=Sim();s.arm();s.c.request(0.5);val fence=ManualCommandFence()
            fence.enqueue();fence.cancel(reason);s.c.invalidateTargets(reason)
            if(fence.dequeue()==null)s.c.request(0.5)
            s.finish(reason);s.tick(10000)
            assertEquals(2,s.calls.size);assertEquals("activation_rejected",s.arm()["event"])
        }
        val s=Sim();s.arm();s.c.request(0.5);s.link=s.link.copy(signalAgeMs=3000,telemetryFresh=false)
        s.tick(5000);assertEquals(1,s.calls.size)
        s.link=s.link.copy(signalAgeMs=0,telemetryFresh=true);s.tick(10000);assertEquals(1,s.calls.size)
    }
    @Test fun trialStillRequiresCurrentIdentityAndManufacturerAndLimitsRapidChanges() {
        for(link in listOf(ManualControlLink(true,false,67,22,0,true),
            ManualControlLink(true,true,67,24,0,true),
            ManualControlLink(true,true,67,22,0,true,activeIdentityMatches=false))) {
            val s=Sim();s.link=link;assertEquals("activation_rejected",s.arm()["event"])
            s.c.request(0.5);assertTrue(s.calls.isEmpty())
        }
        val s=Sim();s.arm();s.c.request(0.5);s.time.set(999)
        assertEquals("manual_pending",s.c.request(0.0)["event"])
        s.tick(5000);assertEquals(hex(encodeManualSlope(0.0)),s.calls.last())
    }
}
