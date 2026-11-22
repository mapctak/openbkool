package com.example.openbkool

import org.junit.Assert.*
import org.junit.Test

class TrainingServicePolicyTest {
    @Test fun aSecondOwnerCannotStartWhileLaunchingRunningOrDraining() {
        assertTrue(TrainingServicePolicy.canStart(false, false, false))
        assertFalse(TrainingServicePolicy.canStart(true, false, false))
        assertFalse(TrainingServicePolicy.canStart(false, true, false))
        assertFalse(TrainingServicePolicy.canStart(false, false, true))
    }

    @Test fun promotionNeedsAnActiveNotificationAndTheSystemForegroundFlag() {
        assertEquals(Promotion.WAIT, TrainingServicePolicy.promotion(true, false, false))
        assertEquals(Promotion.WAIT, TrainingServicePolicy.promotion(false, true, false))
        assertEquals(Promotion.FAILED, TrainingServicePolicy.promotion(true, false, true))
        assertEquals(Promotion.FAILED, TrainingServicePolicy.promotion(false, true, true))
        assertEquals(Promotion.READY, TrainingServicePolicy.promotion(true, true, false))
    }

    @Test fun permissionsRespectTheOsVersionAndTheStopActionMustBeVisible() {
        val base = TrainingPermissions(32, false, false, true)
        assertNull(TrainingServicePolicy.permissionBlock(base))
        assertNotNull(TrainingServicePolicy.permissionBlock(base.copy(sdk = 33)))
        assertNull(TrainingServicePolicy.permissionBlock(base.copy(sdk = 33, notificationsGranted = true)))
        assertNotNull(TrainingServicePolicy.permissionBlock(base.copy(sdk = 34, notificationsGranted = true)))
        assertNull(TrainingServicePolicy.permissionBlock(base.copy(sdk = 34, notificationsGranted = true, nearbyGranted = true)))
        assertNotNull(TrainingServicePolicy.permissionBlock(base.copy(notificationVisible = false)))
    }

    @Test fun notificationStopCannotAffectAnotherSession() {
        assertTrue(TrainingServicePolicy.acceptsStop("current", "current"))
        assertFalse(TrainingServicePolicy.acceptsStop("current", "old"))
        assertFalse(TrainingServicePolicy.acceptsStop("current", null))
        assertFalse(TrainingServicePolicy.acceptsStop(null, "old"))
    }
}
