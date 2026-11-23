package com.example.openbkool

/** Passive profile on the ANT worker. A new segment marks an uncertain interval. */
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
        if (totalMeters < distance) {
            gap = true
            return
        }
        val previous = distance
        distance = totalMeters
        if (!valid) {
            if (points.size > 1 || totalMeters > 0) gap = true
            return
        }
        if (distance == points.last().distance) return
        val currentGrade = grade
        if (gap || currentGrade == null) {
            if (gap) segment++
            if (previous > points.last().distance) append(previous)
            gap = false
        }
        elevation += (distance - previous) * (currentGrade ?: 0.0) / 100.0
        if (distance > points.last().distance) append(distance)
        if (points.size > 512) compact()
    }

    private fun append(meters: Long) {
        points.add(Point(meters, elevation, segment))
        cached = null
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
