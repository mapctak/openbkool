package com.example.openbkool

import org.junit.Assert.*
import org.junit.Test
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

class AntTransmissionAuditTest {
    @Test fun txEventDoesNotAcknowledgeSlopeOrFlushAndCloseReturnIsNotClosed() {
        var time=0L;val audit=AntTransmissionAudit{time}
        audit.opened();time=100;audit.observe(3);audit.observe(5)
        val before=audit.snapshot()
        assertEquals(1,before["txEventCount"]);assertEquals("unknown",before["physicalResistance"])
        assertEquals("unavailable",(before["channelEvents"] as List<*>).map{it as Map<*,*>}.first()["commandCorrelation"])
        time=150;audit.closeRequested();time=151;audit.closeApiReturned()
        assertFalse(audit.channelUsable);assertNull(audit.snapshot()["channelClosedEventAtMs"])
        time=152;audit.observe(3) // Delayed TX during close must not revive channel.
        assertFalse(audit.channelUsable)
        time=200;audit.observe(7);assertEquals(200L,audit.snapshot()["channelClosedEventAtMs"])
    }
    @Test fun closedCallbackBlocksAlreadyQueuedSlopeBeforeWorkerProcessesClose() {
        val audit=AntTransmissionAudit{0L};audit.opened()
        val queue=ManualCommandFence();val worker=Executors.newSingleThreadExecutor()
        val entered=CountDownLatch(1);val release=CountDownLatch(1)
        val frames=mutableListOf<String>()
        try {
            worker.submit{entered.countDown();release.await(2,TimeUnit.SECONDS)}
            assertTrue(entered.await(2,TimeUnit.SECONDS))
            queue.enqueue()
            val increment=worker.submit{if(queue.dequeue()==null && audit.channelUsable)frames.add("increment")}
            audit.observe(7);queue.cancel("channel_closed")
            release.countDown();increment.get(2,TimeUnit.SECONDS)
            assertTrue(frames.isEmpty())
            assertFalse(audit.channelUsable)
        }finally{release.countDown();worker.shutdownNow()}
    }
    @Test fun earlyDeathOrCloseCannotBeUndoneByDelayedOpenReturn() {
        val audit=AntTransmissionAudit{0L};audit.died();audit.opened()
        assertFalse(audit.channelUsable);assertNull(audit.snapshot()["channelClosedEventAtMs"])
        val closed=AntTransmissionAudit{1L};closed.observe(7);closed.opened();assertFalse(closed.channelUsable)
        val timeout=AntTransmissionAudit{2L};timeout.observe(1);timeout.opened();assertFalse(timeout.channelUsable)
    }
    @Test fun eventHistoryIsBoundedAndCounterDoesNotClaimPerCommandDelivery() {
        val audit=AntTransmissionAudit{0L};audit.opened()
        repeat(100){audit.observe(3)}
        assertEquals(64,(audit.snapshot()["channelEvents"] as List<*>).size)
        assertEquals(36,audit.snapshot()["droppedChannelEvents"])
        assertEquals(100,audit.snapshot()["txEventCount"])
        assertEquals("unacknowledged",audit.snapshot()["broadcastDelivery"])
    }
    @Test fun delayedIncreaseAndFlatAfterStopAreCancelledButInFlightRemainsUnknown() {
        val audit=AntTransmissionAudit{0L};audit.opened()
        val queue=ManualCommandFence();val tasks=ArrayDeque<()->Unit>();val frames=mutableListOf<String>()
        for(value in listOf(1.0,0.0)){
            queue.enqueue();tasks.add {if(queue.dequeue()==null && audit.channelUsable)frames.add(hex(encodeManualSlope(value)))}
        }
        queue.cancel("manual_stop")
        while(tasks.isNotEmpty())tasks.removeFirst().invoke()
        // The dedicated stop path may submit one zero before close, not the cancelled manual flat.
        frames.add(hex(encodeManualSlope(0.0)));audit.closeRequested();audit.closeApiReturned()
        assertEquals(listOf("33 FF FF FF FF 20 4E FF"),frames)
        assertEquals("unknown",queue.snapshot()["radioBufferPending"])
    }
}
