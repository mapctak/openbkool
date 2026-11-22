package com.example.openbkool

/** Passive profile on the ANT session's serial worker. Distance is the horizontal proxy. */
internal class VirtualElevation {
    private data class Point(val distance: Long, val elevation: Double, val segment: Long)
    private val points = ArrayList<Point>().apply { add(Point(0, 0.0, 0)) }
    private var distance = 0L
    private var elevation = 0.0
    private var grade: Double? = 0.0
    private var segment = 0L
    private var gap = false
    private var cached: List<List<Number>>? = null

    fun accepted(percent: Double) { grade = percent }

    fun unavailable() { grade = null; gap = true }

    fun observe(totalMeters: Long, valid: Boolean) {
        val previous = distance
        distance = totalMeters
        val baseline = maxOf(previous, points.last().distance)
        val currentGrade = grade
        if (!valid || totalMeters < baseline || currentGrade == null) {
            if (points.size == 1 && totalMeters == 0L && currentGrade != null) return
            gap = true
            return
        }
        if (totalMeters == baseline) return
        if (gap) {
            if (baseline > points.last().distance) {
                segment++
                points.add(Point(baseline, elevation, segment))
            }
            gap = false
        }
        elevation += (totalMeters - baseline) * currentGrade / 100.0
        points.add(Point(totalMeters, elevation, segment))
        cached = null
        if (points.size > 512) compact()
    }

    private fun compact() {
        val reduced = points.chunked(8).flatMap { bucket ->
            val indices = listOf(0, bucket.lastIndex,
                bucket.indices.minBy { bucket[it].elevation },
                bucket.indices.maxBy { bucket[it].elevation })
            indices.distinct().sorted().map { bucket[it] }
        }
        points.clear()
        points.addAll(reduced)
    }

    fun snapshot(): List<List<Number>> = cached ?: points
        .map { listOf(it.distance, it.elevation, it.segment) }
        .also { cached = it }
}
