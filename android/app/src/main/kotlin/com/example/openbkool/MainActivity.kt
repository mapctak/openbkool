package com.example.openbkool

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel

class MainActivity : FlutterActivity() {
    private var training: AntTrainerSearch? = null
    private var antTrainerSearch: AntTrainerSearch? = null
    private var antDiagnostics: AntDiagnostics? = null
    private val permissionRequestCode = 4818
    private var permissionResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        antDiagnostics = AntDiagnostics(this)
        antTrainerSearch = AntTrainerSearch(this)
        training = AntTrainerSearch(this, training = true) { running ->
            if (running) window.addFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            else window.clearFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        }
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "openbkool/training/events").setStreamHandler(training)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "openbkool/training").setMethodCallHandler { call, result ->
            val session = training
            if (session == null) result.error("not_ready", "Entrenamiento no inicializado", null)
            else when (call.method) {
                "start" -> session.start(call.argument<String>("mode") ?: "training", result, call.argument<Map<String, Any?>>("device"))
                "prepareSlope" -> {
                    val percent = call.argument<Number>("percent")
                    if (percent == null) result.error("invalid_grade", "Pendiente numérica requerida", null)
                    else session.prepareSlope(percent.toDouble(), result)
                }
                "enableManualTest", "setManualSlope", "stopManualTest" -> session.manualAction(call.method,
                    call.argument<String>("sessionId"), call.argument<Boolean>("confirmed") == true,
                    call.argument<Number>("percent")?.toDouble(), result)
                "stop" -> session.stop(result)
                "snapshot" -> result.success(session.snapshot())
                "exportCsv" -> session.exportCsv(result)
                else -> result.notImplemented()
            }
        }
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "openbkool/ant_search/events")
            .setStreamHandler(antTrainerSearch)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "openbkool/ant_search")
            .setMethodCallHandler { call, result ->
                val search = antTrainerSearch
                if (search == null) {
                    result.error("ant_not_ready", "Búsqueda ANT no inicializada", null)
                } else when (call.method) {
                    "start" -> search.start(call.argument<String>("mode") ?: "sequential", result)
                    "stop" -> search.stop(result)
                    "snapshot" -> result.success(search.snapshot())
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "openbkool/ant")
            .setMethodCallHandler { call, result ->
                if (call.method == "inspectCapabilities") {
                    val diagnostics = antDiagnostics
                    if (diagnostics == null) {
                        result.error("ant_not_ready", "Diagnóstico ANT no inicializado", null)
                    } else {
                        diagnostics.inspect(result)
                    }
                } else {
                    result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "openbkool/permissions")
            .setMethodCallHandler { call, result ->
                if (call.method != "requestScanPermissions") {
                    result.notImplemented()
                } else if (permissionResult != null) {
                    result.error("permission_request_pending", "Ya hay una solicitud de permisos", null)
                } else {
                    val missing = scanPermissions().filter {
                        checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED
                    }
                    if (missing.isEmpty()) {
                        result.success(true)
                    } else {
                        // Android 12+ exige solicitar ubicación aproximada y precisa
                        // conjuntamente. FBP 2.3.14 solo solicita FINE por sí mismo.
                        permissionResult = result
                        try {
                            requestPermissions(scanPermissions().toTypedArray(), permissionRequestCode)
                        } catch (error: Exception) {
                            permissionResult = null
                            result.error("permission_request_failed", error.message, null)
                        }
                    }
                }
            }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        training?.dispose()
        training = null
        antTrainerSearch?.dispose()
        antTrainerSearch = null
        antDiagnostics?.dispose()
        antDiagnostics = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onStop() {
        training?.stop()
        antTrainerSearch?.stop()
        super.onStop()
    }

    private fun scanPermissions(): List<String> = buildList {
        add(Manifest.permission.ACCESS_COARSE_LOCATION)
        add(Manifest.permission.ACCESS_FINE_LOCATION)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            add(Manifest.permission.BLUETOOTH_SCAN)
            add(Manifest.permission.BLUETOOTH_CONNECT)
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != permissionRequestCode) return
        val result = permissionResult ?: return
        permissionResult = null
        val denied = scanPermissions().filter {
            checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED
        }
        if (denied.isEmpty()) {
            result.success(true)
        } else {
            result.error("permission_denied", "Permisos denegados: ${denied.joinToString()}", denied)
        }
    }
}
