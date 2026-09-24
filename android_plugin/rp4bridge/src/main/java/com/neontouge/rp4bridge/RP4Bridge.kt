package com.neontouge.rp4bridge

import android.content.ContentValues
import android.content.Context
import android.os.BatteryManager
import android.os.Build
import android.os.PerformanceHintManager
import android.os.PowerManager
import android.os.Process
import android.provider.MediaStore
import android.util.Log
import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.UsedByGodot
import java.io.File

/**
 * Retroid Pocket 4 Pro bridge: scheduler hints (ADPF), sustained performance mode, thermal
 * headroom / battery for the quality governor, and gallery export for photo mode.
 */
class RP4Bridge(godot: Godot) : GodotPlugin(godot) {
    private var hintSession: PerformanceHintManager.Session? = null
    private var targetNanos: Long = 16_666_666L
    private var lastThermal = -1f
    private var lastThermalMs = 0L

    override fun getPluginName() = "RP4Bridge"

    @UsedByGodot
    fun setSustainedPerformance(enabled: Boolean) {
        val act = activity ?: return
        act.runOnUiThread {
            try {
                act.window.setSustainedPerformanceMode(enabled)
            } catch (e: Exception) {
                Log.w(TAG, "sustained performance mode unavailable: $e")
            }
        }
    }

    /**
     * Starts (or retargets) an ADPF hint session covering the calling (game) thread and the rest of
     * the process' busy threads, so the scheduler keeps them on big cores at the right clocks.
     */
    @UsedByGodot
    fun startHintSession(target: Long) {
        targetNanos = target
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return
        val existing = hintSession
        if (existing != null) {
            existing.updateTargetWorkDuration(target)
            return
        }
        val mgr = activity?.getSystemService(Context.PERFORMANCE_HINT_SERVICE) as? PerformanceHintManager ?: return
        val tids = gameThreadIds()
        try {
            hintSession = mgr.createHintSession(tids, target)
            Log.i(TAG, "ADPF hint session: ${tids.size} threads, target ${target / 1000} us")
        } catch (e: Exception) {
            Log.w(TAG, "ADPF session failed: $e")
        }
    }

    @UsedByGodot
    fun reportFrameTime(actualNanos: Long) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return
        try {
            hintSession?.reportActualWorkDuration(actualNanos)
        } catch (e: Exception) {
            Log.w(TAG, "reportActualWorkDuration failed: $e")
            hintSession = null
        }
    }

    /** 0 = cool, 1 = severe throttling imminent, -1 = unknown. Cached for the API's 1 s limit. */
    @UsedByGodot
    fun thermalHeadroom(): Float {
        val now = System.currentTimeMillis()
        if (now - lastThermalMs < 1000) return lastThermal
        lastThermalMs = now
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return -1f
        val pm = activity?.getSystemService(Context.POWER_SERVICE) as? PowerManager ?: return -1f
        val h = pm.getThermalHeadroom(1)
        lastThermal = if (h.isNaN()) lastThermal else h
        return lastThermal
    }

    @UsedByGodot
    fun thermalStatus(): Int {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return -1
        val pm = activity?.getSystemService(Context.POWER_SERVICE) as? PowerManager ?: return -1
        return pm.currentThermalStatus
    }

    @UsedByGodot
    fun batteryLevel(): Float {
        val bm = activity?.getSystemService(Context.BATTERY_SERVICE) as? BatteryManager ?: return -1f
        val pct = bm.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)
        return if (pct < 0) -1f else pct / 100f
    }

    /** Copies a PNG written by the game (absolute path) into Pictures/NeonTouge. */
    @UsedByGodot
    fun savePhotoToGallery(path: String, displayName: String): Boolean {
        val act = activity ?: return false
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return false
        val src = File(path)
        if (!src.exists()) return false
        val values = ContentValues().apply {
            put(MediaStore.Images.Media.DISPLAY_NAME, displayName)
            put(MediaStore.Images.Media.MIME_TYPE, "image/png")
            put(MediaStore.Images.Media.RELATIVE_PATH, "Pictures/NeonTouge")
            put(MediaStore.Images.Media.IS_PENDING, 1)
        }
        val resolver = act.contentResolver
        val uri = resolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values) ?: return false
        return try {
            resolver.openOutputStream(uri)?.use { out -> src.inputStream().use { it.copyTo(out) } }
            values.clear()
            values.put(MediaStore.Images.Media.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
            true
        } catch (e: Exception) {
            Log.w(TAG, "photo export failed: $e")
            resolver.delete(uri, null, null)
            false
        }
    }

    @UsedByGodot
    fun deviceInfo(): String =
        "${Build.MANUFACTURER} ${Build.MODEL} (${Build.HARDWARE}) SDK ${Build.VERSION.SDK_INT} SoC ${
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) Build.SOC_MODEL else "?"
        }"

    private fun gameThreadIds(): IntArray {
        val ids = LinkedHashSet<Int>()
        ids.add(Process.myTid())
        // Godot's worker pool, audio mixer and render threads live in this process; include the
        // named engine threads (bounded) so physics/AI jobs get the same scheduling boost.
        File("/proc/self/task").listFiles()?.forEach { task ->
            if (ids.size >= 32) return@forEach
            val name = try { File(task, "comm").readText().trim() } catch (e: Exception) { "" }
            if (name.contains("Worker", true) || name.contains("Godot", true) || name.contains("Audio", true) ||
                name.contains("WorkerThreadPool", true) || name.startsWith("Thread-")) {
                task.name.toIntOrNull()?.let { ids.add(it) }
            }
        }
        return ids.toIntArray()
    }

    companion object {
        private const val TAG = "RP4Bridge"
    }
}
