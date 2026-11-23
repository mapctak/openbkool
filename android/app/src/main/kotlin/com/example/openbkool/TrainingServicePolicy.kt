package com.example.openbkool

internal data class TrainingPermissions(
    val sdk: Int,
    val notificationsGranted: Boolean,
    val notificationVisible: Boolean,
) {
    fun toMap() = mapOf(
        "androidSdk" to sdk, "notificationsGranted" to notificationsGranted,
        "notificationVisible" to notificationVisible,
    )
}

internal enum class Promotion { WAIT, FAILED, READY }

internal object TrainingServicePolicy {
    fun acceptsStop(current: String?, requested: String?) = requested != null && requested == current

    const val IDLE_BACKGROUND_LIMIT_MS = 15 * 60_000L

    fun acceptsConnectionAction(currentReadOnly: Boolean, requestedReadOnly: Boolean,
        currentId: String, requestedId: String?) =
        currentReadOnly == requestedReadOnly && (requestedId == null || acceptsStop(currentId, requestedId))

    fun idleExpired(now: Long, readySince: Long?, backgroundSince: Long?) =
        readySince != null && backgroundSince != null &&
            now - maxOf(readySince, backgroundSince) >= IDLE_BACKGROUND_LIMIT_MS

    fun replaceConnection(sameTarget: Boolean, presence: String) =
        !sameTarget || presence == "error" || presence == "disconnected"

    fun canStart(pending: Boolean, hasOwner: Boolean, draining: Boolean) = !pending && !hasOwner && !draining

    fun permissionBlock(permissions: TrainingPermissions): String? = when {
        permissions.sdk >= 33 && !permissions.notificationsGranted -> "Permite las notificaciones para usar DETENER en Android."
        !permissions.notificationVisible -> "Activa las notificaciones de OpenBkool y el canal Entrenamiento libre en Ajustes."
        else -> null
    }

    fun promotion(foreground: Boolean, posted: Boolean, expired: Boolean): Promotion = when {
        foreground && posted -> Promotion.READY
        expired -> Promotion.FAILED
        else -> Promotion.WAIT
    }
}
