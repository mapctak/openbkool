package com.example.openbkool

import org.junit.Assert.*
import org.junit.Test

class ExperimentalSlopeEncodingTest {
    @Test fun candidatesMatchOriginalFloatFormulaWithoutOverflowOrRoundingForRequestedValues() {
        val expected=mapOf(0.0 to "20 4E",0.5 to "52 4E",1.0 to "84 4E",2.0 to "E8 4E",3.0 to "4C 4F",4.0 to "B0 4F")
        for((percent,gradeHex) in expected){
            val original=((percent.toFloat()+200.0f)*100.0f).toInt()
            assertTrue(original in 0..65535)
            val payload=encodeSlopeCandidate(percent)
            assertEquals("33 FF FF FF FF $gradeHex FF",hex(payload))
            assertEquals(original,(payload[5].toInt() and 255) or ((payload[6].toInt() and 255) shl 8))
            assertEquals(20000+(percent*100).toInt(),original)
        }
    }
    @Test fun offlineBoundAndOperationalAdmissionAreDifferent() {
        for(value in listOf(-0.5,0.25,4.5,455.36,Double.NaN,Double.POSITIVE_INFINITY)){
            try{encodeSlopeCandidate(value);fail("invalid candidate $value")}catch(_:IllegalArgumentException){}
        }
        for(value in listOf(1.5,2.0,2.5,3.0)){
            try{encodeManualSlope(value);fail("unapproved physical level $value")}catch(_:IllegalArgumentException){}
        }
        assertEquals(1.0,ManualControlPolicy.MAX_PERCENT,0.0)
        assertEquals(30000L,ManualControlPolicy.MAX_DURATION_MS)
        assertFalse(ManualControlPolicy.CONTINUOUS_PHYSICAL_ENABLED)
    }
    @Test fun explicitArmingStillCannotSubmitTwoOrThreeAndStopUsesConfirmedZeroFormat() {
        var now=0L;var link=ManualControlLink(true,true,67,22,0,true)
        val frames=mutableListOf<String>();val events=mutableListOf<Map<String,Any?>>()
        val c=ManualAntControl(AntTrainerIdentity(30064,112,5),{now},{link},{b,_->frames.add(hex(b))},events::add)
        c.enable(true)
        for(value in listOf(2.0,3.0)){assertEquals("experimental_level_not_authorized",c.request(value)["reason"])}
        assertTrue(frames.isEmpty())
        c.request(1.0);now=1000;link=link.copy(radioAvailable=false)
        c.request(2.0);assertFalse(c.stop("disconnected",true));c.completeStop(true)
        assertEquals(1,frames.size);assertEquals("error",c.snapshot()["state"])
        assertEquals(2,events.count{it["event"]=="request" && it["requestedPercent"]==2.0})
    }
}
