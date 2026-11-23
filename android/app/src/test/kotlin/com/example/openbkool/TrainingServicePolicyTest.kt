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
        val base = TrainingPermissions(32, false, true)
        assertNull(TrainingServicePolicy.permissionBlock(base))
        assertNotNull(TrainingServicePolicy.permissionBlock(base.copy(sdk = 33)))
        assertNull(TrainingServicePolicy.permissionBlock(base.copy(sdk = 33, notificationsGranted = true)))
        assertNull(TrainingServicePolicy.permissionBlock(base.copy(sdk = 34, notificationsGranted = true)))
        assertNotNull(TrainingServicePolicy.permissionBlock(base.copy(notificationVisible = false)))
    }

    @Test fun notificationStopCannotAffectAnotherSession() {
        assertTrue(TrainingServicePolicy.acceptsStop("current", "current"))
        assertFalse(TrainingServicePolicy.acceptsStop("current", "old"))
        assertFalse(TrainingServicePolicy.acceptsStop("current", null))
        assertFalse(TrainingServicePolicy.acceptsStop(null, "old"))
    }
    @Test fun preparationReusesOnlyTheRequestedConnection() {
        val policy = TrainingServicePolicy
        assertFalse(policy.replaceConnection(true, "present"))
        assertFalse(policy.replaceConnection(true, "connecting"))
        assertTrue(policy.replaceConnection(true, "error"))
        assertTrue(policy.replaceConnection(true, "disconnected"))
        assertTrue(policy.replaceConnection(false, "present"))
    }

    @Test fun oldCheckAndNotificationCannotStopANewWorkout() {
        val policy = TrainingServicePolicy
        assertTrue(policy.acceptsConnectionAction(true, true, "link", "link"))
        assertFalse(policy.acceptsConnectionAction(false, true, "workout-1", null))
        assertFalse(policy.acceptsConnectionAction(false, true, "workout-1", "link"))
        assertTrue(policy.acceptsConnectionAction(false, false, "workout-1", "workout-1"))
        assertFalse(policy.acceptsConnectionAction(false, false, "workout-2", "workout-1"))
        assertFalse(policy.acceptsConnectionAction(true, false, "link", "workout-1"))
    }

    @Test fun idleLinkSurvivesTemporaryBackgroundAndExpiresOnlyAfterItsFullWindow() {
        val policy = TrainingServicePolicy
        val limit = policy.IDLE_BACKGROUND_LIMIT_MS
        assertFalse(policy.idleExpired(2 * limit, 10, null))
        assertFalse(policy.idleExpired(100, 10, 20))
        assertFalse(policy.idleExpired(limit + 19, 10, 20))
        assertTrue(policy.idleExpired(limit + 20, 10, 20))
        assertTrue(policy.idleExpired(limit + 30, 30, 20))
    }
}
