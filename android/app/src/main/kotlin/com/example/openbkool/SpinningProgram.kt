package com.example.openbkool

internal data class SpinningInterval(val startMs: Long, val endMs: Long, val grade: Double, val phase: String) {
    fun report() = mapOf("startMs" to startMs, "endMs" to endMs, "grade" to grade, "phase" to phase)
}

internal data class SpinningProgram(val minutes: Int, val level: Int, val intervals: List<SpinningInterval>) {
    val id = "spinning-v1-$minutes-$level"
    val name = "${SpinningCatalog.levelNames[level - 1]} · $minutes min"
    val durationMs = minutes * 60_000L
    fun report() = mapOf("id" to id, "name" to name, "durationMs" to durationMs,
        "level" to level, "maxGrade" to intervals.maxOf { it.grade }, "intervals" to intervals.map { it.report() })
}

internal object SpinningCatalog {
    val levelNames = listOf("Muy suave", "Suave", "Moderado", "Intenso", "Exigente", "Muy exigente")
    val programs = listOf(10, 15, 20, 30, 45).flatMap { minutes ->
        (1..6).map { level -> build(minutes, level) }
    }
    private fun build(minutes: Int, level: Int): SpinningProgram {
        val intervals = mutableListOf<SpinningInterval>()
        var seconds = 0
        fun add(length: Int, grade: Double, phase: String) {
            intervals.add(SpinningInterval(seconds * 1000L, (seconds + length) * 1000L, grade, phase))
            seconds += length
        }
        val warm = maxOf(90, minutes * 6)
        val cool = maxOf(60, minutes * 4)
        add(warm / 2, 0.5, "warmup")
        add(warm - warm / 2, 1.0, "warmup")
        val main = minutes * 60 - warm - cool
        val rounds = (main / listOf(180, 150, 120, 100, 95, 85)[level - 1]).coerceAtLeast(2)
        val peak = listOf(2.0, 3.0, 4.0, 5.5, 7.0, 8.0)[level - 1]
        repeat(rounds) { index ->
            val round = main * (index + 1) / rounds - main * index / rounds
            val effort = round * listOf(40, 45, 50, 55, 60, 65)[level - 1] / 100
            val grade = peak - if (index == rounds - 1) 0.0 else (2 - index % 3) * 0.5
            add(effort, grade, "effort")
            add(round - effort, if (level >= 4) 1.5 else 0.5, "recovery")
        }
        add(cool / 2, 0.5, "cooldown")
        add(cool - cool / 2, 0.0, "cooldown")
        return SpinningProgram(minutes, level, intervals)
    }
}

/** One cursor per workout, advanced on the owner's serial worker. */
internal class SpinningProgress(val program: SpinningProgram) {
    private val visited = mutableListOf<Map<String, Any>>()
    var index = -1
        private set

    fun advance(elapsedMs: Long): Double? {
        val next = program.intervals.indexOfFirst { elapsedMs >= it.startMs && elapsedMs < it.endMs }
        if (next <= index) return null
        val previousGrade = program.intervals.getOrNull(index)?.grade
        index = next
        val interval = program.intervals[index]
        visited.add(interval.report() + mapOf("index" to index, "observedAtMs" to elapsedMs))
        return interval.grade.takeIf { it != previousGrade }
    }

    fun report(elapsedMs: Long, reason: String?): Map<String, Any?> {
        val interval = program.intervals.getOrNull(index)
        return program.report() + mapOf("intervalIndex" to index,
            "currentGrade" to interval?.grade, "phase" to interval?.phase,
            "remainingMs" to (program.durationMs - elapsedMs).coerceAtLeast(0),
            "intervalRemainingMs" to interval?.let { (it.endMs - elapsedMs).coerceAtLeast(0) },
            "effectiveMs" to elapsedMs, "executedIntervals" to visited.toList(), "finishReason" to reason)
    }

    fun nextBoundary() = program.intervals.getOrNull(index)?.endMs
}
