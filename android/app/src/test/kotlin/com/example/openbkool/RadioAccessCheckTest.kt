package com.example.openbkool

import org.junit.Assert.*
import org.junit.Test

class RadioAccessCheckTest {
    @Test fun noFreeChannelsDoesNotTakeRadioFromOtherApps() {
        val result = checkRadioAccess(0) { error("No debe reservar") }
        assertFalse(result.accessible)
        assertFalse(result.reservationAcquired)
        assertNull(result.released)
    }

    @Test fun unassignedReservationIsReleasedImmediately() {
        var released = false
        val result = checkRadioAccess(1) { { released = true } }
        assertTrue(result.accessible)
        assertTrue(released)
        assertEquals(true, result.released)
    }

    @Test fun acquisitionFailureDoesNotClaimHardwareIsAccessible() {
        val error = IllegalStateException("radio desconectada")
        val result = checkRadioAccess(1) { throw error }
        assertFalse(result.accessible)
        assertSame(error, result.error)
        assertEquals("acquisition_failed", result.status)
    }

    @Test fun releaseFailureRemainsVisibleInsteadOfReportingSuccess() {
        val result = checkRadioAccess(1) { { throw IllegalStateException("release falló") } }
        assertTrue(result.reservationAcquired)
        assertEquals(false, result.released)
        assertEquals("release_failed", result.status)
        assertNotNull(result.error)
    }
}
