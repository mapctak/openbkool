package com.example.openbkool

internal data class AntTrainerIdentity(val number: Int, val type: Int, val transmission: Int) {
    init { require(number in 1..65535 && type == 112 && transmission in 1..255) { "Identidad V1 específica inválida (sin comodines)" } }
    fun matches(f: AntReceivedFrame) = number == f.deviceNumber && type == f.deviceType && transmission == f.transmissionType
    fun toMap() = mapOf("deviceNumber" to number, "deviceType" to type, "transmissionType" to transmission, "protocol" to "BKOOL_V1_PUBLIC")
}

internal interface V1DedicatedChannel {
    fun assignBidirectionalSlave()
    fun setId(number: Int, type: Int, transmission: Int)
    fun setPeriod(period: Int)
    fun setRfFrequency(rf: Int)
    fun setLowPrioritySearchOnly()
    fun enableExtendedIdentity()
    fun open()
}

/** No data-send operation exists in this configuration interface. */
internal fun configureV1Dedicated(c: V1DedicatedChannel, target: AntTrainerIdentity,
    rfMin: Int, rfMax: Int, trace: AntOperationTrace) {
    trace.run("connection.validateRf", mapOf("rfMin" to rfMin, "rfMax" to rfMax)) {
        require(40 in rfMin..rfMax) { "RF=40 no disponible" }
    }
    trace.run("connection.assign", mapOf("type" to "BIDIRECTIONAL_SLAVE", "backgroundScanning" to false)) { c.assignBidirectionalSlave() }
    trace.run("connection.setChannelId", target.toMap()) { c.setId(target.number, target.type, target.transmission) }
    trace.run("connection.setPeriod", mapOf("period" to 32768)) { c.setPeriod(32768) }
    trace.run("connection.setRfFrequency", mapOf("rf" to 40)) { c.setRfFrequency(40) }
    trace.run("connection.setSearchTimeout", mapOf("lowPrioritySeconds" to 25, "highPriority" to "DISABLED")) { c.setLowPrioritySearchOnly() }
    c.enableExtendedIdentity()
    trace.run("connection.open") { c.open() }
}

/** Every identity must be exact, including transmission type; wildcards are not proof. */
internal fun channelIdentitiesMatch(target: AntTrainerIdentity, configured: Map<String, Any?>?,
    adapter: Map<String, Any?>?, received: Map<String, Any?>?): Boolean =
    listOf(configured, adapter, received).all {
        it != null && it["deviceNumber"] == target.number && it["deviceType"] == target.type && it["transmissionType"] == target.transmission
    }
