package com.example.openbkool
import org.junit.Assert.*
import org.junit.Test
class SavedTrainerRecordTest {
    private val valid=mapOf("protocol" to "BKOOL_V1_PUBLIC","deviceNumber" to 30064,"deviceType" to 112,"transmissionType" to 5,"modelNumber" to 22,"manufacturerId" to 67)
    @Test fun persistSelectionNeverConnectionOrActivation(){
        val record=SavedTrainerRecord.fromMap(valid+mapOf("connected" to true,"enabled" to true,"sessionId" to "old"))
        assertEquals(30064,record.number);assertEquals(5,record.transmission);assertEquals(22,record.model)
        assertFalse(record.toMap().containsKey("connected"));assertFalse(record.toMap().containsKey("enabled"));assertFalse(record.toMap().containsKey("sessionId"))
        assertEquals(record,SavedTrainerRecord.fromMap(record.toMap()))
    }
    @Test fun invalidSavedIdentityNeverBecomesASelection(){
        for(map in listOf(valid+mapOf("deviceNumber" to 0),valid+mapOf("transmissionType" to 0),valid+mapOf("protocol" to "FEC"),valid+mapOf("deviceType" to 17))){
            try{SavedTrainerRecord.fromMap(map);fail("Identidad inválida")}catch(_:IllegalArgumentException){}
        }
    }
}
