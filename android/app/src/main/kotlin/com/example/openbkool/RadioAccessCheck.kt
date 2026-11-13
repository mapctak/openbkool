package com.example.openbkool

/** Reserva sin asignar/abrir y libera; no configura ninguna red ni búsqueda. */
internal data class RadioAccessResult(
    val accessible: Boolean,
    val reservationAcquired: Boolean,
    val released: Boolean?,
    val status: String,
    val error: Exception? = null,
)

internal fun checkRadioAccess(
    availableChannels: Int,
    acquire: () -> (() -> Unit),
): RadioAccessResult {
    // No forzar la recuperación de canales ocupados por otras aplicaciones.
    if (availableChannels <= 0) {
        return RadioAccessResult(false, false, null, "no_free_channels")
    }
    val release = try {
        acquire()
    } catch (error: Exception) {
        return RadioAccessResult(false, false, null, "acquisition_failed", error)
    }
    return try {
        release()
        RadioAccessResult(true, true, true, "accessible")
    } catch (error: Exception) {
        RadioAccessResult(true, true, false, "release_failed", error)
    }
}
