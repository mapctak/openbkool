package com.example.openbkool

import org.junit.Assert.*
import org.junit.Test

class ConnectionCheckTest {
    private val ready = ManualControlLink(
        dedicated = true, identityVerified = true, manufacturer = 67, model = 22,
        signalAgeMs = 100, telemetryFresh = false,
    )

    @Test fun checkWaitsForExactIdentityAndFreshSignal() {
        for (link in listOf(
            ready.copy(identityVerified = false), ready.copy(activeIdentityMatches = false),
            ready.copy(manufacturer = null), ready.copy(model = null),
            ready.copy(signalAgeMs = 3000), ready.copy(channelOpen = false),
            ready.copy(radioAvailable = false), ready.copy(sessionActive = false),
        )) {
            assertNull(connectionCheckOutcome(link))
        }
        assertEquals("check_verified", connectionCheckOutcome(ready))
        assertEquals("check_wrong_model", connectionCheckOutcome(ready.copy(model = 24)))
        assertEquals("check_wrong_model", connectionCheckOutcome(ready.copy(manufacturer = 68)))
    }
    @Test fun recentMatchingFramesEstablishPresenceBeforeManufacturerIdentification() {
        val target = AntTrainerIdentity(30064, 112, 5)
        val telemetry = BkoolTelemetry(0, target)
        val frame = AntReceivedFrame(30064, 112, 5, byteArrayOf(0x10, 0, 0, 0, 0, 10, 0, 0))
        fun state(at: Long, usable: Boolean = true, previous: Boolean = true,
            interrupted: Boolean = false, finished: Boolean = false) =
            antPresenceState(usable, telemetry.lastReceivedMs?.let { at - it }, previous, interrupted, finished)

        telemetry.receive(frame.copy(deviceNumber = 42), 100)
        assertEquals("connecting", state(150, previous = false))
        telemetry.receive(frame, 150)
        assertEquals("present", state(200))
        val pending = ready.copy(manufacturer = null, model = null, telemetryFresh = true)
        assertNull(connectionCheckOutcome(pending))
        assertEquals("manufacturer_model_not_verified", pending.reason(target))
        assertEquals("check_verified", connectionCheckOutcome(ready))
        assertNull(ready.copy(telemetryFresh = true).reason(target))
        assertEquals("present", state(200))
        assertEquals("error", state(3150))
        assertEquals("error", state(200, interrupted = true))
        assertEquals("disconnected", state(200, usable = false, finished = true))
    }

    @Test fun sessionsOnAReusableChannelHaveSeparateControllersAndNoInheritedOrders() {
        var now = 0L
        var link = ready.copy(telemetryFresh = true)
        val target = AntTrainerIdentity(30064, 112, 5)
        var newerInputWaiting = true
        val transmissions = mutableListOf<Boolean>()
        fun control() = ManualAntControl(target, { now }, { link },
            { _, stopping -> transmissions.add(stopping) }, {},
            manualPriorityWaiting = { newerInputWaiting })

        val first = control()
        assertEquals("enabled", first.enable()["event"])
        first.request(1.0, rapidAdjustment = true)
        assertNotNull(first.snapshot()["pendingManualChange"])
        assertFalse(first.stop("user_finish", allowZero = true))
        assertTrue(first.canRetainChannel())
        assertNull(first.snapshot()["pendingManualChange"])
        newerInputWaiting = false
        now += ManualControlPolicy.REFRESH_MS
        first.flushPending()
        first.refreshTarget()
        assertTrue(transmissions.isEmpty())

        val second = control()
        assertEquals("enabled", second.enable()["event"])
        assertNull(second.snapshot()["lastRequestedPercent"])
        assertNull(second.snapshot()["pendingManualChange"])
        second.request(2.0)
        assertTrue(second.stop("user_finish", allowZero = true))
        assertEquals(listOf(false, true), transmissions)
        assertFalse(second.canRetainChannel())

        val interrupted = control()
        assertEquals("enabled", interrupted.enable()["event"])
        link = link.copy(signalAgeMs = 5_000)
        assertEquals("link_lost:signal_not_fresh", interrupted.abortReason())
        interrupted.stop("link_lost:signal_not_fresh", allowZero = false)
        link = ready.copy(telemetryFresh = true)
        assertEquals("activation_rejected", interrupted.enable()["event"])
        assertFalse(interrupted.canRetainChannel())
    }
}
