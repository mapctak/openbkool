package com.example.openbkool

import org.junit.Assert.*
import org.junit.Test

class AntSearchDataTest {
    private fun frame(payload: ByteArray, type: Int = 112, number: Int = 0x1234, rssi: Boolean = false) =
        byteArrayOf(0) + payload + byteArrayOf(if (rssi) 0xc0.toByte() else 0x80.toByte(),
            number.toByte(), (number shr 8).toByte(), type.toByte(), 7) +
            (if (rssi) byteArrayOf(0x20, 0xb0.toByte(), 0) else byteArrayOf())

    @Test fun extendedFrameAcceptsRssiAndSeparatesIdentityFromPage() {
        val page = byteArrayOf(0x50, -1, -1, 2, 67, 0, 22, 0)
        val decoded = decodeAntFrame(0x4e, frame(page, rssi = true))!!
        assertEquals(0x1234, decoded.deviceNumber)
        assertEquals(112, decoded.deviceType)
        assertEquals(7, decoded.transmissionType)
        assertArrayEquals(page, decoded.payload)
        val info = manufacturerPage(decoded.payload)!!
        assertEquals("Smart Pro v1", info["bkoolModel"])
        assertEquals(true, info["bkoolConfirmed"])
        assertEquals(2, info["hardwareRevision"])
    }

    @Test fun missingOrTruncatedIdentityIsNeverGuessed() {
        val content = frame(byteArrayOf(0x50, -1, -1, 2, 67, 0, 24, 0))
        assertNull(decodeAntFrame(0x4e, content.copyOf(13)))
        content[9] = 0
        assertNull(decodeAntFrame(0x4e, content))
        assertNull(decodeAntFrame(0x40, frame(ByteArray(8))))
        assertNull(decodeAntFrame(0x4e, frame(ByteArray(8), number = 0)))
    }

    @Test fun bkoolModelsRequireManufacturerAndLittleEndianModel() {
        assertEquals("Smart Pro v2", manufacturerPage(byteArrayOf(0x50, -1, -1, 3, 67, 0, 24, 0))!!["bkoolModel"])
        assertNull(manufacturerPage(byteArrayOf(0x50, -1, -1, 3, 1, 0, 24, 0))!!["bkoolModel"])
        assertEquals(false, modelIdentification(null, 22)["bkoolConfirmed"])
        assertNull(manufacturerPage(ByteArray(7)))
        assertNull(manufacturerPage(ByteArray(8)))
        assertEquals(0x1234, manufacturerPage(byteArrayOf(0x50, -1, -1, 3, 67, 0, 0x34, 0x12))!!["modelNumber"])
    }

    @Test fun productPageUsesUnsignedLittleEndianSerialAndKeepsHexExact() {
        val p = byteArrayOf(0x51, -1, 1, 3, 0x78, 0x56, 0x34, 0x12)
        assertEquals(0x12345678L, manufacturerPage(p)!!["serialNumber"])
        assertEquals("51 FF 01 03 78 56 34 12", hex(p))
        assertNull(manufacturerPage(byteArrayOf(0x51, -1, -1, 3, -1, -1, -1, -1))!!["serialNumber"])
    }

    @Test fun cleanupTriesEveryResourceEvenAfterAnError() {
        val actions = mutableListOf<String>()
        val errors = releaseAntResources(listOf(
            { actions.add("close"); throw IllegalStateException("close") },
            { actions.add("unassign") }, { actions.add("release") }, { actions.add("unbind") },
        ))
        assertEquals(listOf("close", "unassign", "release", "unbind"), actions)
        assertEquals(1, errors.size)
    }

    @Test fun coordinatorExcludesDiagnosticAndProtocolsUntilOwnerReleases() {
        val scan = Any(); val other = Any()
        try {
            assertTrue(AntRadioCoordinator.acquire(scan))
            assertFalse(AntRadioCoordinator.acquire(other))
            AntRadioCoordinator.release(other)
            assertFalse(AntRadioCoordinator.acquire(other))
            AntRadioCoordinator.release(scan)
            assertTrue(AntRadioCoordinator.acquire(other))
        } finally { AntRadioCoordinator.release(scan); AntRadioCoordinator.release(other) }
    }
}
