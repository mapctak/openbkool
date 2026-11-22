package com.example.openbkool

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel

class MainActivity : FlutterActivity() {
    private var trainingEvents: EventChannel.StreamHandler? = null
    private data class RequestedTraining(val device: Map<String, Any?>?, val reply: MethodChannel.Result)
    private var trainingPermissionRequest: RequestedTraining? = null
    private var antTrainerSearch: AntTrainerSearch? = null
    private var antDiagnostics: AntDiagnostics? = null
    private val permissionRequestCode = 4818
    private var visible = false
    private var permissionResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val preferences = TrainerPreferences(this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "openbkool/preferences")
            .setMethodCallHandler(preferences::handle)
        antDiagnostics = AntDiagnostics(this)
        antTrainerSearch = AntTrainerSearch(this)
        trainingEvents = TrainingService.streamHandler()
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "openbkool/training/events").setStreamHandler(trainingEvents)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "openbkool/training").setMethodCallHandler { call, result ->
            val session = TrainingService.controller()
            when (call.method) {
                "start" -> startTraining(call.argument<Map<String, Any?>>("device"), result)
                "stop" -> {
                    trainingPermissionRequest?.reply?.error("training_start_cancelled", "Entrenamiento sin iniciar", null)
                    trainingPermissionRequest = null
                    TrainingService.stop(result, if (call.argument<String>("reason") == "screen_closed") "screen_closed" else "user_finish")
                }
                "snapshot" -> result.success(TrainingService.snapshot())
                else -> {
                    if (session == null) {
                        result.error("not_ready", "No hay un registro de entrenamiento", null)
                        return@setMethodCallHandler
                    }
                    when (call.method) {
                        "activateControl", "setManualSlope" -> session.manualAction(call.method,
                            call.argument<String>("sessionId"),
                            call.argument<Number>("percent")?.toDouble(), result, call.argument<String>("requestedAtUtc"),
                            call.argument<Boolean>("rapidAdjustment") == true, call.argument<Number>("uiQueueMs")?.toLong())
                        "exportCsv" -> session.exportCsv(call.argument<String>("sessionId"), result)
                        "exportJson" -> session.exportJson(call.argument<String>("sessionId"),
                            call.argument<Boolean>("final") == true, result)
                        else -> result.notImplemented()
                    }
                }
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
        trainingEvents?.onCancel(null)
        trainingEvents = null
        trainingPermissionRequest?.reply?.error("training_start_cancelled", "Actividad cerrada", null)
        trainingPermissionRequest = null
        antTrainerSearch?.dispose()
        antTrainerSearch = null
        antDiagnostics?.dispose()
        antDiagnostics = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onStart() {
        super.onStart()
        visible = true
    }

    override fun onResume() {
        super.onResume()
        TrainingService.activityChanged(true)
    }

    override fun onStop() {
        visible = false
        TrainingService.activityChanged(false)
        antTrainerSearch?.stop(reason = "app_background")
        super.onStop()
    }

    private fun startTraining(device: Map<String, Any?>?, result: MethodChannel.Result) {
        if (!visible) { result.error("training_not_visible", "Abre OpenBkool para iniciar el entrenamiento", null); return }
        if (trainingPermissionRequest != null) {
            result.error("permission_request_pending", "Ya hay una solicitud de permisos", null)
            return
        }
        val status = TrainingService.permissionStatus(this)
        val missing = buildList {
            if (Build.VERSION.SDK_INT >= 33 && !status.notificationsGranted) add(Manifest.permission.POST_NOTIFICATIONS)
            if (Build.VERSION.SDK_INT >= 34 && !status.nearbyGranted) add(Manifest.permission.BLUETOOTH_CONNECT)
        }
        if (missing.isEmpty()) {
            TrainingService.start(this, device, result)
        } else {
            trainingPermissionRequest = RequestedTraining(device, result)
            try {
                requestPermissions(missing.toTypedArray(), permissionRequestCode + 1)
            } catch (error: RuntimeException) {
                trainingPermissionRequest = null
                result.error("permission_request_failed", error.message, null)
            }
        }
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
        if (requestCode == permissionRequestCode + 1) {
            val request = trainingPermissionRequest ?: return
            trainingPermissionRequest = null
            if (visible) TrainingService.start(this, request.device, request.reply)
            else request.reply.error("training_not_visible", "Abre OpenBkool para iniciar el entrenamiento", null)
            return
        }
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
