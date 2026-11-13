package com.example.openbkool

import android.os.Handler
import android.os.HandlerThread
import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.atomic.AtomicBoolean

/** PluginLib crea Handler() al pedir acceso; necesita un Looper real.
 * Mantiene todas las operaciones de una búsqueda en un único hilo, fuera de UI.
 */
internal class AntSerialWorker {
    private val thread = HandlerThread("OpenBkoolAntSearch").apply { start() }
    private val handler = Handler(thread.looper)
    private val closed = AtomicBoolean(false)

    fun execute(action: () -> Unit) {
        if (closed.get() || !handler.post(action)) {
            throw RejectedExecutionException("Búsqueda ANT finalizada")
        }
    }

    fun shutdown() {
        if (closed.compareAndSet(false, true)) thread.quitSafely()
    }
}
