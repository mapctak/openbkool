package com.example.openbkool

internal data class TrainingPermissions(
    val sdk: Int,
    val notificationsGranted: Boolean,
    val nearbyGranted: Boolean,
    val notificationVisible: Boolean,
) {
    fun toMap() = mapOf(
        "androidSdk" to sdk, "notificationsGranted" to notificationsGranted,
        "nearbyGranted" to nearbyGranted, "notificationVisible" to notificationVisible,
    )
}

internal enum class Promotion { WAIT, FAILED, READY }

internal object TrainingServicePolicy {
    fun acceptsStop(current: String?, requested: String?) = requested != null && requested == current

    fun canStart(pending: Boolean, hasOwner: Boolean, draining: Boolean) = !pending && !hasOwner && !draining

    fun permissionBlock(permissions: TrainingPermissions): String? = when {
        permissions.sdk >= 33 && !permissions.notificationsGranted -> "Permite las notificaciones para usar DETENER en Android."
        permissions.sdk >= 34 && !permissions.nearbyGranted -> "Permite Dispositivos cercanos para iniciar el servicio en Android 14 o posterior."
        !permissions.notificationVisible -> "Activa las notificaciones de OpenBkool y el canal Entrenamiento libre en Ajustes."
        else -> null
    }

    fun promotion(foreground: Boolean, posted: Boolean, expired: Boolean): Promotion = when {
        foreground && posted -> Promotion.READY
        expired -> Promotion.FAILED
        else -> Promotion.WAIT
    }
}
