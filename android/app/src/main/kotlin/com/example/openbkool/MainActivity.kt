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
    private data class TrainingStart(val mode: String, val device: Map<String, Any?>?, val result: MethodChannel.Result)
    private var notificationStart: TrainingStart? = null
    private var askedForBackgroundPermissions = false
    private var permissionResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val preferences = TrainerPreferences(this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "openbkool/preferences")
            .setMethodCallHandler(preferences::handle)
        antDiagnostics = AntDiagnostics(this)
        antTrainerSearch = AntTrainerSearch(this)
        training = TrainingService.controller(applicationContext)
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "openbkool/training/events").setStreamHandler(training)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "openbkool/training").setMethodCallHandler { call, result ->
            val session = training
            if (session == null) result.error("not_ready", "Entrenamiento no inicializado", null)
            else when (call.method) {
                "start" -> startTraining(call.argument<String>("mode") ?: "training",
                    call.argument<Map<String, Any?>>("device"), result)
                "prepareSlope" -> {
                    val percent = call.argument<Number>("percent")
                    if (percent == null) result.error("invalid_grade", "Pendiente numérica requerida", null)
                    else session.prepareSlope(percent.toDouble(), result)
                }
                "enableManualTest", "setManualSlope", "stopManualTest" -> session.manualAction(call.method,
                    call.argument<String>("sessionId"), call.argument<Boolean>("confirmed") == true,
                    call.argument<Number>("percent")?.toDouble(), result, call.argument<String>("controlMode") ?: "trial_30s", call.argument<Boolean>("experimentalConfirmed") == true, call.argument<String>("rangeProfile"), call.argument<String>("requestedAtUtc"),
                    call.argument<Boolean>("rapidAdjustment") == true, call.argument<Number>("uiQueueMs")?.toLong())
                "stop" -> {
                    val requested = call.argument<String>("reason")
                    val reason = requested?.takeIf { it in setOf("screen_closed", "app_background", "controller_disposed", "user_finish") } ?: "stopped"
                    if (reason == "app_background") {
                        TrainingService.recordLegacyPause()
                        result.success(session.snapshot())
                    } else {
                        cancelNotificationStart(reason)
                        TrainingService.cancelPending(reason)
                        session.stop(result, reason)
                    }
                }
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
        cancelNotificationStart("engine_disposed")
        training?.detachEvents()
        training = null
        antTrainerSearch?.dispose()
        antTrainerSearch = null
        antDiagnostics?.dispose()
        antDiagnostics = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onStart() {
        super.onStart()
        TrainingService.setVisible(applicationContext, true)
    }

    override fun onStop() {
        cancelNotificationStart("app_background")
        TrainingService.setVisible(applicationContext, false)
        antTrainerSearch?.stop(reason = "app_background")
        super.onStop()
    }

    private fun startTraining(mode: String, device: Map<String, Any?>?, result: MethodChannel.Result) {
        if (notificationStart != null) {
            result.error("permission_request_pending", "Ya hay una solicitud de permisos", null)
            return
        }
        val missing = buildList {
            if (Build.VERSION.SDK_INT >= 34 &&
                checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) != PackageManager.PERMISSION_GRANTED &&
                checkSelfPermission(Manifest.permission.BLUETOOTH_SCAN) != PackageManager.PERMISSION_GRANTED) {
                add(Manifest.permission.BLUETOOTH_CONNECT)
            }
            if (Build.VERSION.SDK_INT >= 33 &&
                checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                add(Manifest.permission.POST_NOTIFICATIONS)
            }
        }
        if (missing.isNotEmpty() && !askedForBackgroundPermissions) {
            askedForBackgroundPermissions = true
            notificationStart = TrainingStart(mode, device, result)
            try {
                requestPermissions(missing.toTypedArray(), permissionRequestCode + 1)
            } catch (error: RuntimeException) {
                cancelNotificationStart(error.message ?: "permission_request_failed")
            }
        } else TrainingService.start(this, mode, device, result)
    }

    private fun cancelNotificationStart(reason: String) {
        val request = notificationStart ?: return
        notificationStart = null
        request.result.error("training_start_cancelled", reason, null)
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
            val request = notificationStart ?: return
            notificationStart = null
            TrainingService.start(this, request.mode, request.device, request.result)
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
