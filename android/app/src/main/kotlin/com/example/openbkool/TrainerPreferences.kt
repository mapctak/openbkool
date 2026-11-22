package com.example.openbkool

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.AtomicFile
import java.io.File
import java.io.FileNotFoundException
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

internal class TrainerPreferences(context: Context) {
    private val prefs = context.applicationContext.getSharedPreferences("openbkool_selection", Context.MODE_PRIVATE)
    private val consent = AtomicFile(File(context.noBackupFilesDir, "control-consent.json"))
    private val main = Handler(Looper.getMainLooper())

    @Synchronized
    private fun readConsent(): String? = try {
        consent.readFully().toString(Charsets.UTF_8)
    } catch (_: FileNotFoundException) {
        null
    }

    @Synchronized
    private fun writeConsent(record: String?) {
        if (record == null) {
            consent.delete()
            check(!consent.baseFile.exists()) { "No se pudo revocar la autorización" }
            return
        }
        val stream = consent.startWrite()
        try {
            stream.write(record.toByteArray(Charsets.UTF_8))
            consent.finishWrite(stream)
        } catch (error: Exception) {
            consent.failWrite(stream)
            throw error
        }
    }

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        if (call.method !in listOf("loadTrainer", "saveTrainer", "loadControlConsent", "saveControlConsent")) {
            result.notImplemented()
            return
        }
        Thread {
            try {
                val value = when (call.method) {
                    "loadControlConsent" -> readConsent()
                    "saveControlConsent" -> {
                        writeConsent(call.arguments as String?)
                        null
                    }
                    "loadTrainer" -> {
                        if (!prefs.getBoolean("saved", false)) null else SavedTrainerRecord.fromMap(mapOf(
                            "protocol" to prefs.getString("protocol", null),
                            "deviceType" to prefs.getInt("type", 0),
                            "deviceNumber" to prefs.getInt("number", 0),
                            "transmissionType" to prefs.getInt("transmission", 0),
                            "modelNumber" to if (prefs.contains("model")) prefs.getInt("model", 0) else null,
                            "manufacturerId" to if (prefs.contains("manufacturer")) prefs.getInt("manufacturer", 0) else null,
                        )).toMap()
                    }
                    else -> {
                        val record = SavedTrainerRecord.fromMap(call.arguments as Map<*, *>)
                        val editor = prefs.edit().clear().putBoolean("saved", true)
                            .putString("protocol", "BKOOL_V1_PUBLIC").putInt("type", 112)
                            .putInt("number", record.number).putInt("transmission", record.transmission)
                        record.model?.let { editor.putInt("model", it) }
                        record.manufacturer?.let { editor.putInt("manufacturer", it) }
                        check(editor.commit()) { "No se pudo persistir la selección" }
                        null
                    }
                }
                main.post { result.success(value) }
            } catch (error: Exception) {
                main.post { result.error("preferences_error", error.message, null) }
            }
        }.start()
    }
}
