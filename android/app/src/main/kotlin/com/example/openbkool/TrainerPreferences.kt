package com.example.openbkool

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

internal class TrainerPreferences(context: Context) {
    private val prefs=context.applicationContext.getSharedPreferences("openbkool_selection", Context.MODE_PRIVATE)
    private val main=Handler(Looper.getMainLooper())
    fun handle(call: MethodCall, result: MethodChannel.Result) {
        if(call.method !in listOf("loadTrainer","saveTrainer")) {result.notImplemented();return}
        Thread {
            try {
                val value = if(call.method=="loadTrainer") {
                    if(!prefs.getBoolean("saved",false)) null else SavedTrainerRecord.fromMap(mapOf(
                        "protocol" to prefs.getString("protocol",null), "deviceType" to prefs.getInt("type",0),
                        "deviceNumber" to prefs.getInt("number",0), "transmissionType" to prefs.getInt("transmission",0),
                        "modelNumber" to if(prefs.contains("model")) prefs.getInt("model",0) else null,
                        "manufacturerId" to if(prefs.contains("manufacturer")) prefs.getInt("manufacturer",0) else null)).toMap()
                } else {
                    val record=SavedTrainerRecord.fromMap(call.arguments as Map<*,*>)
                    val editor=prefs.edit().clear().putBoolean("saved",true).putString("protocol","BKOOL_V1_PUBLIC")
                        .putInt("type",112).putInt("number",record.number).putInt("transmission",record.transmission)
                    record.model?.let {editor.putInt("model",it)};record.manufacturer?.let {editor.putInt("manufacturer",it)}
                    check(editor.commit()) {"No se pudo persistir la selección"}
                    null
                }
                main.post {result.success(value)}
            } catch(error: Exception) {main.post {result.error("preferences_error",error.message,null)}}
        }.start()
    }
}
