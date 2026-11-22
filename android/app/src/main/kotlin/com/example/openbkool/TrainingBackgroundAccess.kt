package com.example.openbkool

internal data class TrainingBackgroundAccess(
    val sdk: Int,
    val notificationPermission: Boolean,
    val notificationsEnabled: Boolean,
    val channelEnabled: Boolean,
    val bluetoothConnect: Boolean,
    val bluetoothScan: Boolean,
    val notificationPosted: Boolean,
) {
    val blockReason: String? get() = when {
        !notificationPermission -> "notification_permission_denied"
        !notificationsEnabled -> "notifications_disabled"
        !channelEnabled -> "notification_channel_disabled"
        sdk >= 34 && !bluetoothConnect && !bluetoothScan -> "connected_device_permission_denied"
        else -> null
    }

    fun allowsContinuation(serviceStarted: Boolean, servicePromoted: Boolean, hasOwner: Boolean) =
        serviceStarted && servicePromoted && hasOwner && blockReason == null

    fun toMap() = mapOf(
        "androidSdk" to sdk,
        "notificationPermission" to notificationPermission,
        "notificationsEnabled" to notificationsEnabled,
        "notificationChannelEnabled" to channelEnabled,
        "notificationPosted" to notificationPosted,
        "bluetoothConnect" to bluetoothConnect,
        "bluetoothScan" to bluetoothScan,
        "connectedDeviceRuntimeEligible" to (sdk < 34 || bluetoothConnect || bluetoothScan),
    )
}
