package com.example.openbkool

import android.content.ComponentName
import android.content.Context
import android.content.ServiceConnection
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import com.dsi.ant.AntLibVersionInfo
import com.dsi.ant.AntService
import com.dsi.ant.AntSupportChecker
import com.dsi.ant.channel.ChannelNotAvailableException
import com.dsi.ant.channel.ChannelNotAvailableReason
import com.dsi.ant.channel.PredefinedNetwork
import io.flutter.plugin.common.MethodChannel
import java.time.Instant
import java.util.concurrent.Executors

/** Consulta local ANT. Nunca asigna ni abre canales de radio. */
class AntDiagnostics(context: Context) {
    private val context = context.applicationContext
    private val main = Handler(Looper.getMainLooper())
    private var active: Request? = null

    fun inspect(result: MethodChannel.Result) {
        if (active != null) {
            result.error("ant_busy", "Ya hay una consulta ANT en curso", null)
            return
        }
        val request = Request(result)
        if (!AntRadioCoordinator.acquire(request)) {
            request.abandon()
            result.error("ant_busy", "Una búsqueda ANT está usando la radio", null)
            return
        }
        active = request
        request.start()
    }

    fun dispose() {
        active?.finish("cancelled", "Consulta cancelada al cerrar la actividad")
    }

    private inner class Request(private val result: MethodChannel.Result) : ServiceConnection {
        private val executor = Executors.newSingleThreadExecutor()
        private var bound = false
        @Volatile private var finished = false
        private val startedAt = timestamp()
        private val errors = mutableListOf<Map<String, Any?>>()
        private val report = mutableMapOf<String, Any?>(
            "status" to "checking",
            "checkedAt" to startedAt,
            "antLibVersion" to AntLibVersionInfo.ANTLIB_VERSION_STRING,
            "android" to mapOf(
                "sdkInt" to Build.VERSION.SDK_INT,
                "release" to Build.VERSION.RELEASE,
                "manufacturer" to Build.MANUFACTURER,
                "model" to Build.MODEL,
                "targetSdk" to context.applicationInfo.targetSdkVersion,
                "sdkDocumentedThroughApi" to 33,
                "newerThanSdkDocumented" to (Build.VERSION.SDK_INT > 33),
            ),
            "builtInHardware" to mapOf("declared" to null, "observed" to null),
            "channelProvider" to mapOf("responsive" to null, "availableChannels" to null),
            "radio" to mapOf("accessible" to null, "status" to "not_checked"),
            "adapters" to emptyList<Map<String, Any?>>(),
        )
        private val timeout = Runnable { finish("timeout", "El servicio ANT no respondió en 8 segundos") }
        private val retry = Runnable { service?.let { query(it) } }
        private var service: AntService? = null
        private var querying = false

        fun abandon() { executor.shutdownNow() }

        fun start() {
            try {
                report["radioService"] = packageStatus("com.dsi.ant.service.socket")
                report["pluginsService"] = packageStatus("com.dsi.ant.plugins.antplus")
                report["usbService"] = packageStatus("com.dsi.ant.usbservice")
                try {
                    report["builtInHardware"] = mapOf(
                        "declared" to AntSupportChecker.hasAntFeature(context),
                        "observed" to null,
                    )
                    report["addOnServiceDeclared"] = AntSupportChecker.hasAntAddOn(context)
                } catch (error: Exception) {
                    addError("hardware_declaration", error)
                }
                val radio = report["radioService"] as Map<*, *>
                if (radio["installed"] != true || radio["enabled"] != true) {
                    finish("radio_service_unavailable", "ANT Radio Service no está instalado o está deshabilitado")
                    return
                }
                main.postDelayed(timeout, 8000)
                bound = AntService.bindService(context, this)
                report["radioServiceBindRequested"] = bound
                if (!bound) finish("bind_failed", "No se pudo enlazar con ANT Radio Service")
            } catch (error: Exception) {
                addError("service_bind", error)
                finish("error")
            }
        }

        override fun onServiceConnected(name: ComponentName, binder: IBinder) {
            if (finished) return
            report["radioServiceBound"] = true
            try {
                service = AntService(binder)
                query(service!!)
            } catch (error: Exception) {
                addError("service_connected", error)
                finish("error")
            }
        }

        override fun onServiceDisconnected(name: ComponentName) {
            if (!finished) finish("service_disconnected", "ANT Radio Service se desconectó durante la consulta")
        }

        override fun onBindingDied(name: ComponentName) {
            if (!finished) finish("binding_died", "El enlace con ANT Radio Service dejó de ser válido")
        }

        override fun onNullBinding(name: ComponentName) {
            if (!finished) finish("null_binding", "ANT Radio Service devolvió un enlace vacío")
        }

        private fun query(ant: AntService) {
            if (finished || querying) return
            querying = true
            // Las llamadas Binder pueden bloquear: nunca se ejecutan en el hilo UI.
            executor.execute {
                val values = mutableMapOf<String, Any?>()
                val queryErrors = mutableListOf<Pair<String, Exception>>()
                var initializing = false
                try {
                    val provider = ant.channelProvider
                    val count = provider.numChannelsAvailable
                    val legacy = provider.isLegacyInterfaceInUse
                    values["channelProvider"] = mapOf(
                        "responsive" to true,
                        "operational" to (count > 0),
                        "availableChannels" to count,
                        "legacyInterfaceInUse" to legacy,
                    )
                    try {
                        if (AntService.hasAdapterProviderSupport()) {
                            val adapters = ant.adapterProvider.getAdaptersInfo(context)
                            values["adapterEnumerationSupported"] = true
                            values["adapters"] = adapters.map { adapter ->
                                mapOf(
                                    "id" to adapter.adapterId.toString(),
                                    "builtIn" to adapter.isBuiltIn,
                                    "version" to adapter.versionString,
                                )
                            }
                            values["builtInObserved"] = adapters.any { it.isBuiltIn }
                        } else {
                            values["adapterEnumerationSupported"] = false
                        }
                    } catch (error: ChannelNotAvailableException) {
                        if (error.reasonCode == ChannelNotAvailableReason.SERVICE_INITIALIZING) {
                            initializing = true
                        } else {
                            queryErrors.add("adapters" to error)
                        }
                    } catch (error: Exception) {
                        queryErrors.add("adapters" to error)
                    }
                    if (!initializing && !finished) {
                        val access = checkRadioAccess(count) {
                            val channel = provider.acquireChannel(context, PredefinedNetwork.PUBLIC)
                            // El SDK devuelve el canal SIN ASIGNAR. No se llama a open/assign.
                            val release: () -> Unit = { channel.release() }
                            release
                        }
                        values["radio"] = mapOf(
                            "accessible" to access.accessible,
                            "status" to access.status,
                            "reservationAcquired" to access.reservationAcquired,
                            "released" to access.released,
                            "channelOpened" to false,
                            "network" to "PUBLIC",
                        )
                        access.error?.let {
                            if (it is ChannelNotAvailableException && it.reasonCode == ChannelNotAvailableReason.SERVICE_INITIALIZING) {
                                initializing = true
                                values["radio"] = mapOf("accessible" to null, "status" to "service_initializing")
                            } else {
                                queryErrors.add("radio_access" to it)
                            }
                        }
                    }
                } catch (error: Exception) {
                    queryErrors.add("channel_provider" to error)
                }
                main.post {
                    if (!finished) {
                        querying = false
                        report.putAll(values)
                        val hardware = report["builtInHardware"] as Map<*, *>
                        report["builtInHardware"] = mapOf(
                            "declared" to hardware["declared"],
                            "observed" to values["builtInObserved"],
                        )
                        report.remove("builtInObserved")
                        for ((stage, error) in queryErrors) addError(stage, error)
                        if (initializing) {
                            report["status"] = "service_initializing"
                            main.postDelayed(retry, 500)
                        } else {
                            finish(if (queryErrors.isEmpty()) "completed" else "partial")
                        }
                    }
                }
            }
        }

        private fun addError(stage: String, error: Exception) {
            errors.add(mapOf(
                "stage" to stage,
                "type" to error.javaClass.simpleName,
                "message" to (error.message ?: error.toString()),
                "reason" to (error as? ChannelNotAvailableException)?.reasonCode?.name,
            ))
        }

        fun finish(status: String, message: String? = null) {
            if (finished) return
            finished = true
            main.removeCallbacks(timeout)
            main.removeCallbacks(retry)
            if (message != null) {
                errors.add(mapOf("stage" to status, "message" to message))
            }
            var bindingReleased = !bound
            if (bound) {
                try {
                    context.unbindService(this)
                    bindingReleased = true
                } catch (error: Exception) {
                    addError("unbind", error)
                }
                bound = false
            }
            executor.shutdownNow()
            // La reserva tardía de una llamada Binder debe liberarse antes de
            // permitir que empiece una búsqueda en la misma radio.
            Thread {
                executor.awaitTermination(Long.MAX_VALUE, java.util.concurrent.TimeUnit.NANOSECONDS)
                AntRadioCoordinator.release(this)
            }.start()
            report["status"] = status
            report["finishedAt"] = timestamp()
            report["errors"] = errors.toList()
            report["serviceBindingReleased"] = bindingReleased
            active = null
            result.success(report)
        }
    }

    @Suppress("DEPRECATION")
    private fun packageStatus(name: String): Map<String, Any?> = try {
        val info = context.packageManager.getPackageInfo(name, PackageManager.MATCH_DISABLED_COMPONENTS)
        mapOf(
            "packageName" to name,
            "installed" to true,
            "enabled" to info.applicationInfo?.enabled,
            "versionName" to info.versionName,
            "versionCode" to if (Build.VERSION.SDK_INT >= 28) info.longVersionCode else info.versionCode.toLong(),
        )
    } catch (_: PackageManager.NameNotFoundException) {
        mapOf("packageName" to name, "installed" to false, "enabled" to null)
    }

    private fun timestamp(): String = if (Build.VERSION.SDK_INT >= 26) {
        Instant.now().toString()
    } else {
        java.text.SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", java.util.Locale.US).apply {
            timeZone = java.util.TimeZone.getTimeZone("UTC")
        }.format(java.util.Date())
    }
}
