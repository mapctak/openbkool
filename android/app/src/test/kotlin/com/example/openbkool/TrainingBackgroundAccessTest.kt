package com.example.openbkool

import org.junit.Assert.*
import org.junit.Test

class TrainingBackgroundAccessTest {
    private val android13 = TrainingBackgroundAccess(33, notificationPermission = true,
        notificationsEnabled = true, channelEnabled = true, bluetoothConnect = false,
        bluetoothScan = false, notificationPosted = false)

    @Test fun antOnAndroid13DoesNotRequireNearbyDevicesForForegroundService() {
        assertNull(android13.blockReason)
        assertEquals("connected_device_permission_denied", android13.copy(sdk = 34).blockReason)
        assertNull(android13.copy(sdk = 34, bluetoothConnect = true).blockReason)
    }

    @Test fun continuationRequiresPromotionOwnershipAndNotificationAccess() {
        assertFalse(android13.allowsContinuation(false, false, false))
        assertFalse(android13.allowsContinuation(true, false, true))
        assertFalse(android13.allowsContinuation(true, true, false))
        assertTrue(android13.allowsContinuation(true, true, true))
        assertEquals("notification_permission_denied", android13.copy(notificationPermission = false).blockReason)
        assertEquals("notifications_disabled", android13.copy(notificationsEnabled = false).blockReason)
        val disabled = android13.copy(channelEnabled = false)
        assertEquals("notification_channel_disabled", disabled.blockReason)
        assertFalse(disabled.allowsContinuation(true, true, true))
    }
}
