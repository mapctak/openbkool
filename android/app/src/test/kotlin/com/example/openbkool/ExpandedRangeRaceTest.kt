package com.example.openbkool

import org.junit.Assert.*
import org.junit.Test
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicLong

/** Pure simulated worker/IPC. Never binds ANT or emits radio traffic. */
class ExpandedRangeRaceTest {
    @Test fun stopBeforeOrDuringExpandedRefreshPreventsAllSubsequentGoals() {
        for(duringApi in listOf(false,true)) {
            val time=AtomicLong(0)
            val entered=CountDownLatch(1);val release=CountDownLatch(1)
            val frames=mutableListOf<String>()
            val worker=Executors.newSingleThreadExecutor()
            lateinit var c:ManualAntControl
            c=ManualAntControl(AntTrainerIdentity(30064,112,5),time::get,
                {ManualControlLink(true,true,67,22,0,true)}, {bytes,stop ->
                    c.recordApiEntry();frames.add(hex(bytes))
                    if(duringApi && !stop && time.get()>=5000){entered.countDown();check(release.await(2,TimeUnit.SECONDS))}
                }, {e -> if(!duringApi && e["event"]=="api_attempt" && e["periodicRefresh"]==true) {
                    entered.countDown();check(release.await(2,TimeUnit.SECONDS))
                }})
            try {
                c.enable();c.request(15.0);time.set(5000)
                val refresh=worker.submit{c.refreshTarget()}
                assertTrue(entered.await(2,TimeUnit.SECONDS))
                c.invalidateTargets("manual_stop")
                val stop=worker.submit{c.stop("manual_stop",true);c.completeStop(true)}
                release.countDown();refresh.get(2,TimeUnit.SECONDS);stop.get(2,TimeUnit.SECONDS)
                assertEquals(if(duringApi)3 else 2,frames.size)
                assertEquals(hex(encodePro1Slope(0.0)),frames.last())
                val count=frames.size;time.set(7200000);c.refreshTarget();c.request(-5.0)
                assertEquals(count,frames.size)
                assertEquals("activation_rejected",c.enable()["event"])
            } finally {release.countDown();worker.shutdownNow()}
        }
    }
    @Test fun nativeAdmissionBoundsPendingQueueAndStopCancelsItsSingleSlot() {
        val fence=ManualCommandFence()
        assertTrue(fence.tryEnqueue())
        repeat(100){assertFalse(fence.tryEnqueue())}
        assertEquals(1,fence.snapshot()["pendingApplicationCommands"])
        assertEquals(100,fence.snapshot()["rejectedBusyCommands"])
        fence.cancel("manual_stop")
        assertEquals("manual_stop",fence.dequeue())
        assertEquals(0,fence.snapshot()["pendingApplicationCommands"])
    }
}
