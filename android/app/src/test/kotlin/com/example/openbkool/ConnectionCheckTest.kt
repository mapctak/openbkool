package com.example.openbkool

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
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
}
