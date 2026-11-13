package com.example.openbkool

/** ANTLib + PluginLib comparten radio: solo una operación ANT de OpenBkool. */
internal object AntRadioCoordinator {
    private var owner: Any? = null
    @Synchronized fun acquire(token: Any): Boolean {
        if (owner != null) return false
        owner = token
        return true
    }
    @Synchronized fun release(token: Any) {
        if (owner === token) owner = null
    }
}

internal data class AntReceivedFrame(
    val deviceNumber: Int, val deviceType: Int, val transmissionType: Int,
    val payload: ByteArray,
)

/** 0x4E/0x4F: channel + 8 bytes + extended flags + channel ID opcional.
 * Nunca atribuye una página a un ID supuesto si falta la extensión de identidad.
 */
internal fun decodeAntFrame(messageId: Int, content: ByteArray): AntReceivedFrame? {
    if (messageId != 0x4e && messageId != 0x4f) return null
    if (content.size < 14 || content[9].toInt() and 0x80 == 0) return null
    val number = (content[10].toInt() and 255) or ((content[11].toInt() and 255) shl 8)
    if (number == 0) return null
    return AntReceivedFrame(number, content[12].toInt() and 0x7f,
        content[13].toInt() and 255, content.copyOfRange(1, 9))
}

internal fun hex(bytes: ByteArray): String = bytes.joinToString(" ") { "%02X".format(it.toInt() and 255) }

internal fun modelIdentification(manufacturer: Int?, model: Int?): Map<String, Any?> {
    // ID BKOOL=67 contrastado con Manufacturer.BKOOL del FIT SDK oficial.
    val name = when (model) { 22 -> "Smart Pro v1"; 24 -> "Smart Pro v2"; else -> null }
    return mapOf(
        "manufacturerId" to manufacturer,
        "modelNumber" to model,
        "bkoolModel" to if (manufacturer == 67 || manufacturer == null) name else null,
        "bkoolConfirmed" to (manufacturer == 67 && name != null),
    )
}

internal fun manufacturerPage(payload: ByteArray): Map<String, Any?>? {
    if (payload.size != 8) return null
    fun u(i: Int) = payload[i].toInt() and 255
    fun le(i: Int) = u(i) or (u(i + 1) shl 8)
    return when (u(0)) {
        0x50 -> modelIdentification(le(4).takeUnless { it == 65535 }, le(6).takeUnless { it == 65535 }) + mapOf(
            "informationPage" to 80, "hardwareRevision" to u(3).takeUnless { it == 255 },
        )
        0x51 -> mapOf(
            "productPage" to 81, "mainSoftwareRevision" to u(3),
            "supplementalSoftwareRevision" to u(2).takeUnless { it == 255 },
            "serialNumber" to (u(4).toLong() or (u(5).toLong() shl 8) or
                (u(6).toLong() shl 16) or (u(7).toLong() shl 24)).takeUnless { it == 0xffffffffL },
        )
        else -> null
    }
}

/** Cada acción se intenta aunque una anterior falle. El llamador no debe iniciar
 * el siguiente protocolo si hay errores de cierre. */
internal fun releaseAntResources(actions: List<() -> Unit>): List<Exception> {
    val errors = mutableListOf<Exception>()
    actions.forEach { action -> try { action() } catch (error: Exception) { errors.add(error) } }
    return errors
}
