package com.example.openbkool

import org.junit.Assert.*
import org.junit.Test

class SpinningProgramTest {
    @Test fun catalogCoversAllCombinationsWithContiguousSafeIntervals() {
        val programs = SpinningCatalog.programs
        assertEquals(30, programs.size)
        assertEquals(30, programs.map { it.id }.toSet().size)
        assertEquals(setOf(10, 15, 20, 30, 45), programs.map { it.minutes }.toSet())
        for ((_, variants) in programs.groupBy { it.minutes }) {
            assertEquals((1..6).toList(), variants.map { it.level })
            assertEquals(6, variants.map { it.intervals }.distinct().size)
            assertEquals(listOf(2.0, 3.0, 4.0, 5.5, 7.0, 8.0),
                variants.map { program -> program.intervals.maxOf { it.grade } })
        }
        for (program in programs) {
            val intervals = program.intervals
            assertEquals(0L, intervals.first().startMs)
            assertEquals("warmup", intervals.first().phase)
            assertEquals(program.durationMs, intervals.last().endMs)
            assertEquals("cooldown", intervals.last().phase)
            assertTrue(intervals.any { it.phase == "effort" })
            assertTrue(intervals.any { it.phase == "recovery" })
            assertTrue(intervals.all { it.endMs > it.startMs &&
                it.grade in 0.0..8.0 && it.grade * 2 == (it.grade * 2).toInt().toDouble() })
            assertTrue(intervals.zipWithNext().all { (a, b) -> a.endMs == b.startMs })
        }
    }

    @Test fun delayedWorkerAppliesOnlyTheCurrentIntervalAndRecordsItOnce() {
        val program = SpinningCatalog.programs.first()
        val progress = SpinningProgress(program)
        assertEquals(0.5, progress.advance(0))
        assertNull(progress.advance(5))
        assertEquals(program.intervals.first().endMs, progress.nextBoundary())
        val picked = program.intervals[4]
        assertEquals(picked.grade, progress.advance(picked.startMs))
        assertEquals(4, progress.index)
        assertNull(progress.advance(picked.endMs - 1))
        assertNull(progress.advance(program.durationMs))
        val executed = progress.report(program.durationMs, "program_completed")["executedIntervals"] as List<*>
        assertEquals(listOf(0, 4), executed.map { (it as Map<*, *>)["index"] })
    }

    @Test fun adjacentIntervalsWithEquivalentGradesDoNotRequestAgain() {
        val program = SpinningCatalog.programs.first()
        val progress = SpinningProgress(program)
        val cool = program.intervals.size - 2
        val recovery = program.intervals[cool - 1]
        assertEquals(0.5, progress.advance(recovery.startMs))
        assertNull(progress.advance(recovery.endMs))
        assertEquals(cool, progress.index)
    }

    @Test fun programRequestsShareActivationLossAndStopFencesWithManualControl() {
        var now = 0L
        val target = AntTrainerIdentity(30064, 112, 5)
        var link = ManualControlLink(true, true, 67, 22, 0, telemetryFresh = false)
        val sent = mutableListOf<Boolean>()
        val control = ManualAntControl(target, { now }, { link }, { _, zero -> sent.add(zero) }, {})
        val progress = SpinningProgress(SpinningCatalog.programs.first())
        assertEquals("activation_rejected", control.enable()["event"])
        assertEquals(-1, progress.index)
        assertTrue(sent.isEmpty())
        link = link.copy(telemetryFresh = true)
        assertEquals("enabled", control.enable()["event"])
        control.request(progress.advance(0)!!)
        assertEquals(listOf(false), sent)
        now = 45_000L
        link = link.copy(telemetryFresh = false)
        assertEquals("link_lost:telemetry_not_fresh", control.abortReason())
        assertTrue(control.stop("link_lost:telemetry_not_fresh", allowZero = true))
        link = link.copy(telemetryFresh = true)
        assertEquals("activation_rejected", control.enable()["event"])
        assertNull(control.refreshTarget())
        assertEquals(listOf(false, true), sent)
    }
}
