package com.example.openbkool

import org.junit.Assert.*
import org.junit.Test

class VirtualElevationTest {
    @Test fun integratesOnlyFutureDistanceAtTheAcceptedGrade() {
        val profile = VirtualElevation()
        profile.observe(500, true)
        profile.accepted(5.0)
        profile.observe(700, true)
        profile.accepted(-2.0)
        profile.observe(800, true)
        profile.accepted(0.0)
        profile.observe(900, true)
        assertEquals(listOf(0.0, 0.0, 10.0, 8.0, 8.0), profile.snapshot().map { it[1] })
        assertEquals(listOf(0L, 500L, 700L, 800L, 900L), profile.snapshot().map { it[0] })
        assertEquals(listOf(listOf<Number>(0L, 0.0, 0L)), VirtualElevation().snapshot())
    }

    @Test fun duplicateResetAndInvalidDistanceDoNotInventElevation() {
        val profile = VirtualElevation()
        profile.accepted(5.0)
        profile.observe(100, true)
        profile.observe(100, true)
        profile.observe(10, true)
        profile.observe(20, true)
        profile.observe(125, false)
        profile.observe(150, true)
        assertEquals(listOf(0L, 100L, 125L, 150L), profile.snapshot().map { it[0] })
        assertEquals(listOf(0.0, 5.0, 5.0, 6.25), profile.snapshot().map { it[1] })
        assertEquals(listOf(0L, 0L, 1L, 1L), profile.snapshot().map { it[2] })
        profile.unavailable()
        profile.observe(200, true)
        assertEquals(150L, profile.snapshot().last()[0])
    }

    @Test fun longSessionsRetainOriginEndAndExtremaWithABoundedHistory() {
        val profile = VirtualElevation()
        var min = 0.0
        var max = 0.0
        var elevation = 0.0
        for (meter in 1L..25_000) {
            val grade = when {
                meter < 7_000 -> -8.0
                meter < 15_000 -> 15.0
                else -> -5.0
            }
            profile.accepted(grade)
            profile.observe(meter, true)
            elevation += grade / 100.0
            min = minOf(min, elevation)
            max = maxOf(max, elevation)
        }
        val points = profile.snapshot()
        assertTrue(points.size <= 512)
        assertEquals(0L, points.first()[0])
        assertEquals(25_000L, points.last()[0])
        assertEquals(min, points.minOf { it[1].toDouble() }, 1e-8)
        assertEquals(max, points.maxOf { it[1].toDouble() }, 1e-8)
    }
}
