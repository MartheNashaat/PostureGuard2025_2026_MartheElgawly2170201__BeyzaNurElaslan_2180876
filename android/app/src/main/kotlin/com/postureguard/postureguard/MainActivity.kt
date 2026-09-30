// android/app/src/main/kotlin/com/postureguard/postureguard/MainActivity.kt
package com.postureguard.postureguard

import android.app.PictureInPictureParams
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.res.Configuration
import android.net.Uri
import android.os.BatteryManager
import android.os.Build
import android.os.PowerManager
import android.os.SystemClock
import android.provider.Settings
import android.util.Rational
import android.util.Log
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.postureguard/overlay"
    private val TAG = "MainActivity"

    // Previous /proc/self/stat sample, used to turn cumulative CPU ticks into
    // a percentage over the interval between two getDeviceMetrics calls.
    private var lastCpuTimeMs: Long? = null
    private var lastWallTimeMs: Long? = null

    // Where the session is currently visible: "foreground" (full screen),
    // "pip", or "background" (PiP closed — camera stopped, accelerometer-only
    // mode). Pushed to Dart on every change and included in device metrics.
    private var windowState = "foreground"
    private var windowChannel: MethodChannel? = null

    private fun setWindowState(state: String) {
        if (state == windowState) return
        windowState = state
        windowChannel?.invokeMethod("windowState", state)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        windowChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.postureguard/window").also { ch ->
            ch.setMethodCallHandler { call, result ->
                if (call.method == "getWindowState") result.success(windowState) else result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "requestOverlayPermission" -> {
                    if (Settings.canDrawOverlays(this)) {
                        result.success(true)
                    } else {
                        val intent = Intent(
                            Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                            Uri.parse("package:$packageName")
                        )
                        startActivity(intent)
                        result.success(false)
                    }
                }
                "showOverlay" -> {
                    val show = call.argument<Boolean>("show") ?: false
                    if (show) {
                        startService(Intent(this, OverlayService::class.java))
                    } else {
                        stopService(Intent(this, OverlayService::class.java))
                    }
                    result.success(true)
                }
                "updatePosture" -> {
                    val score = call.argument<Int>("score") ?: 100
                    val status = call.argument<String>("status") ?: "good"
                    OverlayService.updatePosture(score, status)
                    result.success(true)
                }
                "updateBaseline" -> {
                    try {
                        // Get the landmarks as Map<String, Double> from Flutter
                        val landmarks = call.arguments as? Map<String, Double>
                        if (landmarks != null) {
                            Log.d(TAG, "Received baseline: $landmarks")
                            // Convert Double to Float
                            val floatLandmarks = landmarks.mapValues { it.value.toFloat() }
                            OverlayService.updateBaseline(floatLandmarks)
                            result.success(true)
                        } else {
                            Log.e(TAG, "Landmarks is null")
                            result.error("ERROR", "Landmarks is null", null)
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "Error updating baseline: ${e.message}")
                        result.error("ERROR", e.message, null)
                    }
                }
                "isOverlayEnabled" -> {
                    result.success(Settings.canDrawOverlays(this))
                }
                "getBrightness" -> {
                    val brightness = Settings.System.getInt(
                        contentResolver, Settings.System.SCREEN_BRIGHTNESS, 255
                    )
                    result.success(brightness)
                }
                "setBrightness" -> {
                    val brightness = (call.argument<Int>("brightness") ?: 255).coerceIn(0, 255)
                    if (Settings.System.canWrite(this)) {
                        Settings.System.putInt(
                            contentResolver, Settings.System.SCREEN_BRIGHTNESS, brightness
                        )
                        result.success(true)
                    } else {
                        result.error("PERMISSION", "Cannot write settings", null)
                    }
                }
                "isWriteSettingsEnabled" -> {
                    result.success(Settings.System.canWrite(this))
                }
                "requestWriteSettings" -> {
                    if (!Settings.System.canWrite(this)) {
                        val intent = Intent(
                            Settings.ACTION_MANAGE_WRITE_SETTINGS,
                            Uri.parse("package:$packageName")
                        )
                        startActivity(intent)
                        result.success(false)
                    } else {
                        result.success(true)
                    }
                }
                "getScreenTimeout" -> {
                    val timeout = Settings.System.getInt(
                        contentResolver, Settings.System.SCREEN_OFF_TIMEOUT, 30000
                    )
                    result.success(timeout)
                }
                "setScreenTimeout" -> {
                    val timeout = call.argument<Int>("timeout") ?: 30000
                    if (Settings.System.canWrite(this)) {
                        Settings.System.putInt(
                            contentResolver, Settings.System.SCREEN_OFF_TIMEOUT, timeout
                        )
                        result.success(true)
                    } else {
                        result.success(false)
                    }
                }
                "getDeviceInfo" -> {
                    // Sent with every uploaded session: battery/thermal numbers
                    // aren't comparable across phone models.
                    val pkg = packageManager.getPackageInfo(packageName, 0)
                    val versionCode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P)
                        pkg.longVersionCode else @Suppress("DEPRECATION") pkg.versionCode.toLong()
                    result.success(mapOf(
                        "manufacturer" to Build.MANUFACTURER,
                        "model" to Build.MODEL,
                        "androidVersion" to Build.VERSION.RELEASE,
                        "sdkInt" to Build.VERSION.SDK_INT,
                        "appVersion" to "${pkg.versionName}+$versionCode",
                        "cpuCores" to Runtime.getRuntime().availableProcessors()
                    ))
                }
                "getDeviceMetrics" -> {
                    try {
                        result.success(getDeviceMetricsMap())
                    } catch (e: Exception) {
                        result.error("ERROR", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onStart() {
        super.onStart()
        setWindowState(
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N && isInPictureInPictureMode) "pip" else "foreground"
        )
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }

    override fun onResume() {
        super.onResume()
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }

    // PiP keeps the activity started (paused but visible); it only stops once
    // the PiP window is closed or the app is otherwise fully hidden.
    override fun onStop() {
        super.onStop()
        setWindowState("background")
    }

    override fun onPause() {
        super.onPause()
        // onPause fires when entering PiP — re-assert the flag so the screen
        // stays on inside the PiP window (it can be cleared during the transition)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }

    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        // Closing PiP also reports false here, just before onStop sets "background".
        setWindowState(if (isInPictureInPictureMode) "pip" else "foreground")
        // Keep screen on in both PiP and normal mode
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }

    override fun onUserLeaveHint() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val params = PictureInPictureParams.Builder()
                .setAspectRatio(Rational(9, 16))
                .build()
            enterPictureInPictureMode(params)
        }
    }

    // ─── Device benchmarking (Section 1: CPU / battery / thermal profiling) ───

    /// Snapshot of battery level/temperature, thermal throttling status, and
    /// this process's own CPU usage. Used by the benchmark screen to compare
    /// resource cost across detection frame rates.
    private fun getDeviceMetricsMap(): Map<String, Any?> {
        val batteryIntent = registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        val level = batteryIntent?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
        val scale = batteryIntent?.getIntExtra(BatteryManager.EXTRA_SCALE, -1) ?: -1
        val batteryPercent = if (level >= 0 && scale > 0) (level * 100.0 / scale) else null

        val tempTenths = batteryIntent?.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, Int.MIN_VALUE)
            ?: Int.MIN_VALUE
        val batteryTemperatureC = if (tempTenths != Int.MIN_VALUE) tempTenths / 10.0 else null

        val status = batteryIntent?.getIntExtra(BatteryManager.EXTRA_STATUS, -1) ?: -1
        val isCharging = status == BatteryManager.BATTERY_STATUS_CHARGING ||
            status == BatteryManager.BATTERY_STATUS_FULL

        // Per-app skin/die temperature isn't exposed to normal apps on Android.
        // currentThermalStatus (API 29+) is the OS's own throttling verdict and
        // is the standard proxy for "is the device overheating" without root.
        val pm = getSystemService(Context.POWER_SERVICE) as? PowerManager
        val thermalStatus = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            thermalStatusName(pm?.currentThermalStatus)
        } else {
            "unsupported"
        }

        return mapOf(
            "batteryPercent" to batteryPercent,
            "batteryTemperatureC" to batteryTemperatureC,
            "isCharging" to isCharging,
            "thermalStatus" to thermalStatus,
            // Screen state and battery saver both change drain rate a lot, so
            // in-the-wild sessions need them to explain their battery numbers.
            "isScreenOn" to (pm?.isInteractive ?: true),
            "isPowerSaveMode" to (pm?.isPowerSaveMode ?: false),
            "windowState" to windowState,
            "cpuPercent" to getCpuPercent(),
            "cpuCores" to Runtime.getRuntime().availableProcessors()
        )
    }

    private fun thermalStatusName(status: Int?): String = when (status) {
        PowerManager.THERMAL_STATUS_NONE -> "none"
        PowerManager.THERMAL_STATUS_LIGHT -> "light"
        PowerManager.THERMAL_STATUS_MODERATE -> "moderate"
        PowerManager.THERMAL_STATUS_SEVERE -> "severe"
        PowerManager.THERMAL_STATUS_CRITICAL -> "critical"
        PowerManager.THERMAL_STATUS_EMERGENCY -> "emergency"
        PowerManager.THERMAL_STATUS_SHUTDOWN -> "shutdown"
        else -> "unknown"
    }

    /// This process's CPU usage (% of one core, divided by core count so the
    /// result is 0-100) since the previous call. Null on the first call, since
    /// there is no prior sample to diff against. System-wide /proc/stat is
    /// blocked for non-system apps on modern Android, but a process can always
    /// read its own /proc/self/stat.
    private fun getCpuPercent(): Double? {
        val cpuTimeMs = readProcSelfCpuTimeMs()
        val wallTimeMs = SystemClock.elapsedRealtime()
        val prevCpu = lastCpuTimeMs
        val prevWall = lastWallTimeMs
        lastCpuTimeMs = cpuTimeMs
        lastWallTimeMs = wallTimeMs

        if (cpuTimeMs == null || prevCpu == null || prevWall == null) return null
        val deltaCpu = cpuTimeMs - prevCpu
        val deltaWall = wallTimeMs - prevWall
        if (deltaWall <= 0) return null

        val cores = Runtime.getRuntime().availableProcessors().coerceAtLeast(1)
        return (deltaCpu.toDouble() / deltaWall.toDouble()) * 100.0 / cores
    }

    private fun readProcSelfCpuTimeMs(): Long? {
        return try {
            val stat = File("/proc/self/stat").readText()
            // Field 2 (comm) is parenthesised and may itself contain spaces or
            // parens, so split on the LAST ") " rather than counting fields
            // from the start.
            val afterComm = stat.substringAfterLast(") ")
            val fields = afterComm.split(" ")
            // fields[0] is field 3 (state) in the full stat line, so field 14
            // (utime) is fields[11] and field 15 (stime) is fields[12].
            val utimeTicks = fields[11].toLong()
            val stimeTicks = fields[12].toLong()
            val clockTicksPerSec = android.system.Os.sysconf(android.system.OsConstants._SC_CLK_TCK)
            ((utimeTicks + stimeTicks) * 1000L) / clockTicksPerSec
        } catch (e: Exception) {
            null
        }
    }
}
