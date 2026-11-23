package com.example.openbkool

/** Selection only: never persist connection state, session UUID or control permission. */
internal data class SavedTrainerRecord(val number: Int, val transmission: Int, val model: Int?, val manufacturer: Int?) {
    fun toMap(): Map<String, Any?> = mapOf("protocol" to "BKOOL_V1_PUBLIC", "deviceNumber" to number,
        "deviceType" to 112, "transmissionType" to transmission, "modelNumber" to model, "manufacturerId" to manufacturer)
    companion object {
        fun fromMap(value: Map<*, *>): SavedTrainerRecord {
            val number=value["deviceNumber"]; val transmission=value["transmissionType"]
            require(value["protocol"]=="BKOOL_V1_PUBLIC" && value["deviceType"]==112 && number is Int && number in 1..65535 && transmission is Int && transmission in 1..255) { "Identidad ANT inválida" }
            return SavedTrainerRecord(number, transmission, value["modelNumber"] as? Int, value["manufacturerId"] as? Int)
        }
    }
}
