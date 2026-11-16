package com.photobooth.kiosk

import android.app.ActivityManager
import android.app.admin.DevicePolicyManager
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothSocket
import android.content.ComponentName
import android.content.ContentValues
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.PorterDuff
import android.graphics.PorterDuffXfermode
import android.graphics.RectF
import android.media.MediaActionSound
import android.media.MediaMetadataRetriever
import android.print.PageRange
import android.print.PrintAttributes
import android.print.PrintDocumentAdapter
import android.print.PrintDocumentInfo
import android.print.PrintManager
import android.print.pdf.PrintedPdfDocument
import android.speech.tts.TextToSpeech
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.CancellationSignal
import android.os.BatteryManager
import android.os.Handler
import android.os.Looper
import android.os.Environment
import android.os.StatFs
import android.provider.MediaStore
import android.provider.Settings
import android.util.Log
import android.view.View
import android.os.ParcelFileDescriptor
import androidx.core.content.FileProvider
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.util.UnstableApi
import androidx.media3.effect.BitmapOverlay
import androidx.media3.effect.OverlayEffect
import androidx.media3.effect.Presentation
import androidx.media3.transformer.Composition
import androidx.media3.transformer.DefaultEncoderFactory
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.EditedMediaItemSequence
import androidx.media3.transformer.Effects
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.Transformer
import androidx.media3.transformer.VideoEncoderSettings
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.util.UUID
import java.util.Locale

private const val MAX_UPDATE_APK_BYTES = 150L * 1024L * 1024L
private const val MAX_SESSION_VIDEO_DIMENSION = 1280
private const val SESSION_VIDEO_BITRATE = 800_000

private class UpdateInstallPermissionRequired(message: String) : Exception(message)

class MainActivity : FlutterActivity() {
    private val kioskChannelName = "photobooth/kiosk"
    private var shutterSound: MediaActionSound? = null
    private var sessionVideoTransformer: Transformer? = null
    private var textToSpeech: TextToSpeech? = null
    private var speechReady = false
    private val kioskPreferences by lazy {
        getSharedPreferences("photobooth_kiosk", MODE_PRIVATE)
    }
    private val immersiveFlags =
        View.SYSTEM_UI_FLAG_FULLSCREEN or
            View.SYSTEM_UI_FLAG_HIDE_NAVIGATION or
            View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY or
            View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN or
            View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION or
            View.SYSTEM_UI_FLAG_LAYOUT_STABLE

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        shutterSound = MediaActionSound().also {
            it.load(MediaActionSound.SHUTTER_CLICK)
        }
        textToSpeech = TextToSpeech(this) { status ->
            speechReady = status == TextToSpeech.SUCCESS
        }
        updateSystemUi()
        if (!kioskModeDisabled() && isDeviceOwner()) enforceKioskMode()
    }

    override fun onDestroy() {
        sessionVideoTransformer?.cancel()
        sessionVideoTransformer = null
        shutterSound?.release()
        shutterSound = null
        textToSpeech?.stop()
        textToSpeech?.shutdown()
        textToSpeech = null
        super.onDestroy()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            kioskChannelName
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "setScreenAwake" -> {
                    val awake = call.arguments as? Boolean ?: false
                    if (awake) {
                        window.addFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    } else {
                        window.clearFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    }
                    result.success(null)
                }
                "restartBoothApp" -> {
                    Handler(Looper.getMainLooper()).postDelayed({
                        recreate()
                    }, 500)
                    result.success(null)
                }
                "rebootDevice" -> {
                    try {
                        val policy = getSystemService(DEVICE_POLICY_SERVICE) as DevicePolicyManager
                        if (!policy.isDeviceOwnerApp(packageName)) {
                            result.error(
                                "DEVICE_OWNER_REQUIRED",
                                "Android device-owner mode is required to reboot remotely.",
                                null
                            )
                        } else {
                            policy.reboot(
                                ComponentName(this, KioskDeviceAdminReceiver::class.java)
                            )
                            result.success(null)
                        }
                    } catch (error: SecurityException) {
                        result.error("REBOOT_FAILED", error.message, null)
                    } catch (error: IllegalStateException) {
                        result.error("REBOOT_FAILED", error.message, null)
                    }
                }
                "getKioskDiagnostics" -> {
                    val battery = registerReceiver(
                        null,
                        IntentFilter(Intent.ACTION_BATTERY_CHANGED)
                    )
                    val level = battery?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
                    val scale = battery?.getIntExtra(BatteryManager.EXTRA_SCALE, -1) ?: -1
                    val percent = if (level >= 0 && scale > 0) level * 100 / scale else null
                    val status = battery?.getIntExtra(BatteryManager.EXTRA_STATUS, -1) ?: -1
                    val charging = status == BatteryManager.BATTERY_STATUS_CHARGING ||
                        status == BatteryManager.BATTERY_STATUS_FULL
                    val stat = StatFs(filesDir.absolutePath)
                    result.success(
                        mapOf(
                            "batteryPercent" to percent,
                            "charging" to charging,
                            "storageFreeBytes" to stat.availableBytes,
                            "uptimeMillis" to android.os.SystemClock.elapsedRealtime()
                        )
                    )
                }
                "playShutterSound" -> {
                    shutterSound?.play(MediaActionSound.SHUTTER_CLICK)
                    result.success(null)
                }
                "composeSessionVideo" -> composeSessionVideo(call, result)
                "speakGuidance" -> {
                    val text = call.argument<String>("text")?.trim()
                    val engine = textToSpeech
                    if (text.isNullOrEmpty()) {
                        result.error("INVALID_GUIDANCE", "Guidance text is required.", null)
                    } else if (engine == null || !speechReady) {
                        result.error("TTS_NOT_READY", "Android speech is not ready.", null)
                    } else {
                        val languageStatus = engine.setLanguage(Locale.getDefault())
                        if (languageStatus == TextToSpeech.LANG_MISSING_DATA ||
                            languageStatus == TextToSpeech.LANG_NOT_SUPPORTED
                        ) {
                            result.error(
                                "TTS_LANGUAGE_UNAVAILABLE",
                                "The device does not support the current speech language.",
                                null
                            )
                        } else if (engine.speak(
                                text,
                                TextToSpeech.QUEUE_FLUSH,
                                null,
                                "photobooth-guidance"
                            ) == TextToSpeech.ERROR
                        ) {
                            result.error("TTS_SPEAK_FAILED", "Android could not speak the prompt.", null)
                        } else {
                            result.success(null)
                        }
                    }
                }
                "stopVoiceGuidance" -> {
                    textToSpeech?.stop()
                    result.success(null)
                }
                "getPairedBluetoothPrinters" -> {
                    try {
                        result.success(getPairedBluetoothPrinters())
                    } catch (error: IllegalStateException) {
                        result.error("PRINTER_UNAVAILABLE", error.message, null)
                    } catch (error: SecurityException) {
                        result.error("BLUETOOTH_PERMISSION_DENIED", error.message, null)
                    }
                }
                "printEscPos" -> {
                    val address = call.argument<String>("address")
                    val data = call.argument<ByteArray>("data")
                    val copies = call.argument<Int>("copies") ?: 1
                    if (address.isNullOrBlank() || data == null || data.isEmpty()) {
                        result.error(
                            "INVALID_PRINT_REQUEST",
                            "A paired printer and print data are required.",
                            null
                        )
                    } else if (copies !in 1..3) {
                        result.error(
                            "INVALID_PRINT_COPIES",
                            "Print copies must be between 1 and 3.",
                            null
                        )
                    } else {
                        printEscPos(address, data, copies, result)
                    }
                }
                "printColorPhoto" -> {
                    val path = call.argument<String>("path")
                    val copies = call.argument<Int>("copies") ?: 1
                    if (path.isNullOrBlank() || !File(path).isFile) {
                        result.error(
                            "INVALID_PRINT_REQUEST",
                            "A valid photo file is required.",
                            null
                        )
                    } else if (copies !in 1..3) {
                        result.error(
                            "INVALID_PRINT_COPIES",
                            "Print copies must be between 1 and 3.",
                            null
                        )
                    } else {
                        printColorPhoto(path, copies, result)
                    }
                }
                "isKioskActive" -> result.success(isLockTaskActive())
                "exitKioskMode" -> {
                    try {
                        exitKioskMode()
                        result.success(false)
                    } catch (error: IOException) {
                        result.error("KIOSK_EXIT_FAILED", error.message, null)
                    } catch (error: SecurityException) {
                        result.error("KIOSK_EXIT_FAILED", error.message, null)
                    }
                }
                "prepareFilePicker" -> {
                    try {
                        result.success(prepareFilePicker())
                    } catch (error: IOException) {
                        result.error("FILE_PICKER_KIOSK_FAILED", error.message, null)
                    } catch (error: SecurityException) {
                        result.error("FILE_PICKER_KIOSK_FAILED", error.message, null)
                    }
                }
                "finishFilePicker" -> {
                    try {
                        finishFilePicker()
                        result.success(null)
                    } catch (error: SecurityException) {
                        result.error("FILE_PICKER_KIOSK_FAILED", error.message, null)
                    }
                }
                "enableKioskMode" -> beginEnableKioskMode(result)
                "savePhoto" -> {
                    val path = call.argument<String>("path")
                    if (path.isNullOrBlank()) {
                        result.error("INVALID_PATH", "Photo path is missing.", null)
                    } else {
                        try {
                            savePhoto(path)
                            result.success(null)
                        } catch (error: IOException) {
                            result.error("PHOTO_SAVE_FAILED", error.message, null)
                        } catch (error: SecurityException) {
                            result.error("PHOTO_PERMISSION_DENIED", error.message, null)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "photobooth/device"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "androidSdkInt" -> result.success(Build.VERSION.SDK_INT)
                "appVersion" -> {
                    val packageInfo = packageManager.getPackageInfo(packageName, 0)
                    val versionCode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                        packageInfo.longVersionCode
                    } else {
                        packageInfo.versionCode.toLong()
                    }
                    result.success(
                        mapOf(
                            "versionName" to (packageInfo.versionName ?: ""),
                            "versionCode" to versionCode
                        )
                    )
                }
                "downloadAndInstallApk" -> {
                    val arguments = call.arguments as? Map<*, *>
                    val url = arguments?.get("url") as? String
                    val versionCode = (arguments?.get("versionCode") as? Number)?.toLong()
                    if (url.isNullOrBlank() || versionCode == null || versionCode < 1) {
                        result.error(
                            "INVALID_UPDATE",
                            "The update link or version is invalid.",
                            null
                        )
                    } else {
                        Thread {
                            try {
                                val apk = downloadUpdateApk(url, versionCode)
                                runOnUiThread {
                                    try {
                                        launchApkInstaller(apk)
                                        result.success(null)
                                    } catch (error: Exception) {
                                        val code = if (
                                            error is UpdateInstallPermissionRequired
                                        ) {
                                            "INSTALL_PERMISSION_REQUIRED"
                                        } else {
                                            "UPDATE_INSTALLER_FAILED"
                                        }
                                        result.error(
                                            code,
                                            error.message ?: "Android could not open the installer.",
                                            null
                                        )
                                    }
                                }
                            } catch (error: Exception) {
                                runOnUiThread {
                                    val code = if (
                                        error is UpdateInstallPermissionRequired
                                    ) {
                                        "INSTALL_PERMISSION_REQUIRED"
                                    } else {
                                        "UPDATE_DOWNLOAD_FAILED"
                                    }
                                    result.error(code, error.message, null)
                                }
                            }
                        }.start()
                    }
                }
                "androidId" -> {
                    val androidId = Settings.Secure.getString(
                        contentResolver,
                        Settings.Secure.ANDROID_ID
                    )
                    if (androidId.isNullOrBlank()) {
                        result.error(
                            "DEVICE_ID_UNAVAILABLE",
                            "Android did not provide a device activation ID.",
                            null
                        )
                    } else {
                        result.success(androidId)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onResume() {
        super.onResume()
        if (!kioskModeDisabled() && isDeviceOwner()) enforceKioskMode()
        updateSystemUi()
    }

    @Deprecated("Android handles back navigation through system gestures.")
    override fun onBackPressed() {
        if (kioskModeDisabled()) super.onBackPressed()
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) updateSystemUi()
    }

    private fun updateSystemUi() {
        if (kioskModeDisabled()) {
            window.decorView.systemUiVisibility = 0
            window.clearFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        } else {
            window.addFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            hideSystemUi()
        }
    }

    private fun downloadUpdateApk(url: String, expectedVersionCode: Long): File {
            var currentUri = Uri.parse(url)
            if (currentUri.scheme != "https" || currentUri.host.isNullOrBlank()) {
                throw IllegalArgumentException("Only HTTPS update links are allowed.")
            }

            val updateDirectory = File(cacheDir, "updates")
            if (!updateDirectory.exists() && !updateDirectory.mkdirs()) {
                throw IOException("Could not prepare secure update storage.")
            }
            val apkFile = File(updateDirectory, "snaplab-update.apk")
            if (apkFile.exists() && !apkFile.delete()) {
                throw IOException("Could not replace the previous downloaded update.")
            }

            var downloaded = 0L
            var completed = false
            var redirectCount = 0
            try {
                while (!completed) {
                    if (currentUri.scheme != "https" || currentUri.host.isNullOrBlank()) {
                        throw IOException("The update server redirected to an insecure link.")
                    }
                    if (redirectCount > 8) {
                        throw IOException("The update server redirected too many times.")
                    }
                    val connection = URL(currentUri.toString()).openConnection() as HttpURLConnection
                    connection.instanceFollowRedirects = false
                    connection.connectTimeout = 20_000
                    connection.readTimeout = 60_000
                    try {
                        when (val status = connection.responseCode) {
                            in 300..399 -> {
                                val location = connection.getHeaderField("Location")
                                    ?: throw IOException("The update server returned an invalid redirect.")
                                currentUri = Uri.parse(URL(URL(currentUri.toString()), location).toString())
                                redirectCount++
                            }
                            HttpURLConnection.HTTP_OK -> {
                                val contentType = connection.contentType.orEmpty()
                                if (
                                    contentType.contains("text/html", ignoreCase = true) ||
                                    contentType.contains("text/plain", ignoreCase = true)
                                ) {
                                    throw IOException(
                                        "The update link returned a web page instead of an APK. Replace the APK file in the public update link."
                                    )
                                }
                                val contentLength = connection.contentLengthLong
                                if (contentLength > MAX_UPDATE_APK_BYTES) {
                                    throw IOException("The update APK is larger than the allowed 150 MB.")
                                }
                                connection.inputStream.buffered().use { input ->
                                    FileOutputStream(apkFile).buffered().use { output ->
                                        val buffer = ByteArray(64 * 1024)
                                        while (true) {
                                            val count = input.read(buffer)
                                            if (count < 0) break
                                            downloaded += count
                                            if (downloaded > MAX_UPDATE_APK_BYTES) {
                                                throw IOException(
                                                    "The update APK is larger than the allowed 150 MB."
                                                )
                                            }
                                            output.write(buffer, 0, count)
                                        }
                                        output.flush()
                                    }
                                }
                                completed = true
                            }
                            else -> throw IOException("The update server returned HTTP $status.")
                        }
                    } finally {
                        connection.disconnect()
                    }
                }
                if (!completed || !apkFile.isFile || apkFile.length() == 0L) {
                    throw IOException("The APK download did not complete.")
                }
            } catch (error: Exception) {
                apkFile.delete()
                throw error
            }

            val archiveInfo = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                packageManager.getPackageArchiveInfo(
                    apkFile.absolutePath,
                    PackageManager.PackageInfoFlags.of(0)
                )
            } else {
                @Suppress("DEPRECATION")
                packageManager.getPackageArchiveInfo(apkFile.absolutePath, 0)
            } ?: run {
                apkFile.delete()
                throw IOException("The downloaded file is not a valid Android APK.")
            }
            val downloadedPackageName = archiveInfo.packageName
            val downloadedVersionCode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                archiveInfo.longVersionCode
            } else {
                @Suppress("DEPRECATION")
                archiveInfo.versionCode.toLong()
            }
            if (downloadedPackageName != packageName) {
                apkFile.delete()
                throw IOException("The downloaded APK is for a different app.")
            }
            if (downloadedVersionCode != expectedVersionCode) {
                apkFile.delete()
                throw IOException(
                    "The update link advertises build $expectedVersionCode but serves build $downloadedVersionCode. Replace the APK at the existing public link."
                )
            }
            val installedVersionCode = packageManager.getPackageInfo(packageName, 0).let {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                    it.longVersionCode
                } else {
                    @Suppress("DEPRECATION")
                    it.versionCode.toLong()
                }
            }
            if (downloadedVersionCode <= installedVersionCode) {
                apkFile.delete()
                throw IOException(
                    "Build $downloadedVersionCode is not newer than the installed build $installedVersionCode."
                )
            }
            return apkFile
        }

    private fun launchApkInstaller(apkFile: File) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                !packageManager.canRequestPackageInstalls()
            ) {
                val permissionIntent = Intent(
                    Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                    Uri.parse("package:$packageName")
                )
                allowKioskActivity(permissionIntent)
                startActivity(permissionIntent)
                throw UpdateInstallPermissionRequired(
                    "Allow Snap Lab to install updates, then tap Install update again."
                )
            }

            val apkUri = FileProvider.getUriForFile(
                this,
                "$packageName.updateprovider",
                apkFile
            )
            val installIntent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(apkUri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            val installerPackage = packageManager
                .resolveActivity(installIntent, PackageManager.MATCH_DEFAULT_ONLY)
                ?.activityInfo
                ?.packageName
                ?: throw IOException("Android could not find a package installer.")

            allowKioskPackage(installerPackage)
            startActivity(installIntent)
        }

        private fun allowKioskActivity(intent: Intent) {
            val activityPackage = intent.resolveActivity(packageManager)?.packageName ?: return
            allowKioskPackage(activityPackage)
        }

        private fun allowKioskPackage(allowedPackage: String) {
            if (!isDeviceOwner() || !isLockTaskActive() || kioskModeDisabled()) return
            val admin = ComponentName(this, KioskDeviceAdminReceiver::class.java)
            val policy = getSystemService(DEVICE_POLICY_SERVICE) as DevicePolicyManager
            policy.setLockTaskPackages(admin, arrayOf(packageName, allowedPackage))
        }

    private fun kioskModeDisabled(): Boolean =
        kioskPreferences.getBoolean("kiosk_disabled", true)

    private fun isDeviceOwner(): Boolean {
        val policy = getSystemService(DEVICE_POLICY_SERVICE) as DevicePolicyManager
        return policy.isDeviceOwnerApp(packageName)
    }

    private fun isLockTaskActive(): Boolean {
        val activityManager = getSystemService(ACTIVITY_SERVICE) as ActivityManager
        return activityManager.lockTaskModeState == ActivityManager.LOCK_TASK_MODE_LOCKED ||
            activityManager.lockTaskModeState == ActivityManager.LOCK_TASK_MODE_PINNED
    }

    private fun hideSystemUi() {
        window.decorView.systemUiVisibility = immersiveFlags
    }

    private fun getPairedBluetoothPrinters(): List<Map<String, String>> {
        val adapter = getSystemService(BluetoothManager::class.java)?.adapter
            ?: throw IllegalStateException("This tablet does not have Bluetooth.")
        return adapter.bondedDevices
            .sortedBy { it.name ?: it.address }
            .map { device ->
                mapOf(
                    "name" to (device.name ?: "Bluetooth printer"),
                    "address" to device.address
                )
            }
    }

    private fun printEscPos(
        address: String,
        data: ByteArray,
        copies: Int,
        result: MethodChannel.Result
    ) {
        Thread {
            var socket: BluetoothSocket? = null
            try {
                val adapter = getSystemService(BluetoothManager::class.java)?.adapter
                    ?: throw IllegalStateException("This tablet does not have Bluetooth.")
                adapter.cancelDiscovery()
                val device = adapter.getRemoteDevice(address)
                if (adapter.bondedDevices.none { it.address == device.address }) {
                    throw IllegalArgumentException(
                        "Pair the selected printer in Android Bluetooth settings first."
                    )
                }

                socket = device.createRfcommSocketToServiceRecord(
                    UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")
                )
                socket.connect()
                socket.outputStream.use { output ->
                    repeat(copies) {
                        var offset = 0
                        while (offset < data.size) {
                            val count = minOf(4096, data.size - offset)
                            output.write(data, offset, count)
                            offset += count
                        }
                        output.flush()
                        val printDrainMillis =
                            (data.size.toLong() * 1000 / 40_000 + 1500)
                                .coerceIn(2000, 20_000)
                        Thread.sleep(printDrainMillis)
                    }
                }
                socket.close()
                runOnUiThread { result.success(null) }
            } catch (error: InterruptedException) {
                Thread.currentThread().interrupt()
                closePrinterSocket(socket)
                runOnUiThread {
                    result.error("PRINT_INTERRUPTED", "Bluetooth photo printing was interrupted.", null)
                }
            } catch (error: IOException) {
                closePrinterSocket(socket)
                runOnUiThread {
                    result.error(
                        "PRINTER_CONNECTION_FAILED",
                        "Could not print over Bluetooth: ${error.message}",
                        null
                    )
                }
            } catch (error: SecurityException) {
                closePrinterSocket(socket)
                runOnUiThread {
                    result.error(
                        "BLUETOOTH_PERMISSION_DENIED",
                        error.message,
                        null
                    )
                }
            } catch (error: IllegalArgumentException) {
                closePrinterSocket(socket)
                runOnUiThread {
                    result.error("INVALID_PRINTER", error.message, null)
                }
            } catch (error: IllegalStateException) {
                closePrinterSocket(socket)
                runOnUiThread {
                    result.error("PRINTER_UNAVAILABLE", error.message, null)
                }
            }
        }.start()
    }

    private fun printColorPhoto(
        path: String,
        copies: Int,
        result: MethodChannel.Result
    ) {
        val bitmap = BitmapFactory.decodeFile(path)
        if (bitmap == null) {
            result.error("INVALID_PHOTO", "The photo could not be opened for printing.", null)
            return
        }
        try {
            val printManager = getSystemService(PRINT_SERVICE) as? PrintManager
                ?: throw IllegalStateException("Android printing is unavailable.")
            val adapter = object : PrintDocumentAdapter() {
                private var currentAttributes = PrintAttributes.Builder().build()

                override fun onLayout(
                    oldAttributes: PrintAttributes?,
                    newAttributes: PrintAttributes,
                    cancellationSignal: CancellationSignal,
                    callback: LayoutResultCallback,
                    extras: Bundle?
                ) {
                    if (cancellationSignal.isCanceled) {
                        callback.onLayoutCancelled()
                        return
                    }
                    currentAttributes = newAttributes
                    val info = PrintDocumentInfo.Builder("SnapLab-photo.pdf")
                        .setContentType(PrintDocumentInfo.CONTENT_TYPE_PHOTO)
                        .setPageCount(copies)
                        .build()
                    callback.onLayoutFinished(info, oldAttributes != newAttributes)
                }

                override fun onWrite(
                    pages: Array<out PageRange>,
                    destination: ParcelFileDescriptor,
                    cancellationSignal: CancellationSignal,
                    callback: WriteResultCallback
                ) {
                    val document = PrintedPdfDocument(
                        applicationContext,
                        currentAttributes
                    )
                    try {
                        val writtenPages = mutableListOf<PageRange>()
                        for (pageNumber in 0 until copies) {
                            if (cancellationSignal.isCanceled) {
                                callback.onWriteCancelled()
                                return
                            }
                            val pageRequested =
                                pages.any { pageNumber in it.start..it.end }

                            val page = document.startPage(pageNumber)
                            page.canvas.drawColor(android.graphics.Color.WHITE)
                            if (pageRequested) {
                                val pageWidth = page.canvas.width.toFloat()
                                val pageHeight = page.canvas.height.toFloat()
                                val scale = minOf(
                                    pageWidth / bitmap.width,
                                    pageHeight / bitmap.height
                                )
                                val drawWidth = bitmap.width * scale
                                val drawHeight = bitmap.height * scale
                                val destinationRect = RectF(
                                    (pageWidth - drawWidth) / 2f,
                                    (pageHeight - drawHeight) / 2f,
                                    (pageWidth + drawWidth) / 2f,
                                    (pageHeight + drawHeight) / 2f
                                )
                                page.canvas.drawBitmap(
                                    bitmap,
                                    null,
                                    destinationRect,
                                    Paint(Paint.FILTER_BITMAP_FLAG)
                                )
                            }
                            document.finishPage(page)
                            if (pageRequested) {
                                writtenPages.add(PageRange(pageNumber, pageNumber))
                            }
                        }
                        FileOutputStream(destination.fileDescriptor).use { output ->
                            document.writeTo(output)
                        }
                        callback.onWriteFinished(writtenPages.toTypedArray())
                    } catch (error: IOException) {
                        callback.onWriteFailed(error.message)
                    } finally {
                        document.close()
                    }
                }

                override fun onFinish() {
                    bitmap.recycle()
                }
            }
            printManager.print(
                "SnapLab photo",
                adapter,
                PrintAttributes.Builder().build()
            )
            result.success(null)
        } catch (error: IllegalStateException) {
            bitmap.recycle()
            result.error("PRINTER_UNAVAILABLE", error.message, null)
        } catch (error: IllegalArgumentException) {
            bitmap.recycle()
            result.error("PRINTER_UNAVAILABLE", error.message, null)
        } catch (error: SecurityException) {
            bitmap.recycle()
            result.error("PRINT_PERMISSION_DENIED", error.message, null)
        }
    }

    private fun closePrinterSocket(socket: BluetoothSocket?) {
        try {
            socket?.close()
        } catch (error: IOException) {
            Log.w("PhotoboothPrinter", "Could not close the printer socket.", error)
        }
    }

    private fun enforceKioskMode(): Boolean {
        if (kioskModeDisabled()) return false
        val policy = getSystemService(DEVICE_POLICY_SERVICE) as DevicePolicyManager
        val isDeviceOwner = policy.isDeviceOwnerApp(packageName)
        return try {
            if (isDeviceOwner) {
                val admin = ComponentName(this, KioskDeviceAdminReceiver::class.java)
                policy.setLockTaskPackages(admin, arrayOf(packageName))
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                    policy.setLockTaskFeatures(
                        admin,
                        DevicePolicyManager.LOCK_TASK_FEATURE_NONE
                    )
                }
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    policy.setStatusBarDisabled(admin, true)
                }
                val homeFilter = IntentFilter(Intent.ACTION_MAIN).apply {
                    addCategory(Intent.CATEGORY_HOME)
                    addCategory(Intent.CATEGORY_DEFAULT)
                }
                policy.addPersistentPreferredActivity(
                    admin,
                    homeFilter,
                    ComponentName(this, MainActivity::class.java)
                )
            }
            val activityManager = getSystemService(ACTIVITY_SERVICE) as ActivityManager
            if (activityManager.lockTaskModeState == ActivityManager.LOCK_TASK_MODE_NONE &&
                (isDeviceOwner && policy.isLockTaskPermitted(packageName) ||
                    !isDeviceOwner)
            ) {
                startLockTask()
            }
            val state = activityManager.lockTaskModeState
            state == ActivityManager.LOCK_TASK_MODE_LOCKED ||
                (!isDeviceOwner && state == ActivityManager.LOCK_TASK_MODE_PINNED)
        } catch (error: SecurityException) {
            Log.e("PhotoboothKiosk", "Could not enforce Android Lock Task Mode.", error)
            false
        }
    }

    private fun exitKioskMode() {
        val policy = getSystemService(DEVICE_POLICY_SERVICE) as DevicePolicyManager
        val isDeviceOwner = policy.isDeviceOwnerApp(packageName)
        if (!kioskPreferences.edit().putBoolean("kiosk_disabled", true).commit()) {
            throw IOException("Could not record the requested kiosk exit.")
        }

        try {
            val activityManager = getSystemService(ACTIVITY_SERVICE) as ActivityManager
            if (activityManager.lockTaskModeState != ActivityManager.LOCK_TASK_MODE_NONE) {
                stopLockTask()
            }
            if (isDeviceOwner) {
                val admin = ComponentName(this, KioskDeviceAdminReceiver::class.java)
                policy.setLockTaskPackages(admin, emptyArray())
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    policy.setStatusBarDisabled(admin, false)
                }
                policy.clearPackagePersistentPreferredActivities(admin, packageName)
            }
            updateSystemUi()
        } catch (error: SecurityException) {
            kioskPreferences.edit().putBoolean("kiosk_disabled", false).commit()
            updateSystemUi()
            throw error
        }
    }

    private fun prepareFilePicker(): Boolean {
        if (!isDeviceOwner() || !isLockTaskActive()) return false

        val pickerIntents = listOf(
            Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = "*/*"
            },
            Intent(Intent.ACTION_GET_CONTENT).apply {
                type = "image/*"
            }
        )
        val pickerPackages = pickerIntents.mapNotNull { intent ->
            intent.resolveActivity(packageManager)?.packageName
        }.filter { it != packageName }.toSet()
        if (pickerPackages.isEmpty()) {
            throw IOException("Android could not find a supported file picker.")
        }

        val policy = getSystemService(DEVICE_POLICY_SERVICE) as DevicePolicyManager
        val admin = ComponentName(this, KioskDeviceAdminReceiver::class.java)
        policy.setLockTaskPackages(
            admin,
            (pickerPackages + packageName).toTypedArray()
        )
        return true
    }

    private fun finishFilePicker() {
        if (!isDeviceOwner() || kioskModeDisabled()) return

        val policy = getSystemService(DEVICE_POLICY_SERVICE) as DevicePolicyManager
        val admin = ComponentName(this, KioskDeviceAdminReceiver::class.java)
        policy.setLockTaskPackages(admin, arrayOf(packageName))
    }

    private fun enableKioskMode(): Boolean {
        if (!kioskPreferences.edit().putBoolean("kiosk_disabled", false).commit()) {
            throw IOException("Could not record the kiosk mode setting.")
        }

        return try {
            val active = enforceKioskMode()
            if (!active) {
                kioskPreferences.edit().putBoolean("kiosk_disabled", true).commit()
            }
            updateSystemUi()
            active
        } catch (error: SecurityException) {
            kioskPreferences.edit().putBoolean("kiosk_disabled", true).commit()
            updateSystemUi()
            throw error
        }
    }

    private fun beginEnableKioskMode(result: MethodChannel.Result) {
        try {
            if (!kioskPreferences.edit().putBoolean("kiosk_disabled", false).commit()) {
                throw IOException("Could not record the kiosk mode setting.")
            }
            if (isDeviceOwner()) {
                result.success(enableKioskMode())
                return
            }

            // Consumer Android displays its screen-pinning confirmation here,
            // reached only from the authenticated operator setup flow.
            startLockTask()
            updateSystemUi()
            val deadline = android.os.SystemClock.elapsedRealtime() + 45_000L
            val handler = Handler(Looper.getMainLooper())
            val confirmPinning = object : Runnable {
                override fun run() {
                    if (isLockTaskActive()) {
                        result.success(true)
                    } else if (android.os.SystemClock.elapsedRealtime() >= deadline) {
                        kioskPreferences.edit()
                            .putBoolean("kiosk_disabled", true)
                            .commit()
                        updateSystemUi()
                        result.error(
                            "KIOSK_ENABLE_CANCELLED",
                            "Screen pinning was not confirmed by the operator.",
                            null
                        )
                    } else {
                        handler.postDelayed(this, 250)
                    }
                }
            }
            handler.postDelayed(confirmPinning, 250)
        } catch (error: IOException) {
            kioskPreferences.edit().putBoolean("kiosk_disabled", true).commit()
            result.error("KIOSK_ENABLE_FAILED", error.message, null)
        } catch (error: SecurityException) {
            kioskPreferences.edit().putBoolean("kiosk_disabled", true).commit()
            updateSystemUi()
            result.error("KIOSK_ENABLE_FAILED", error.message, null)
        }
    }

    @OptIn(UnstableApi::class)
    private fun composeSessionVideo(
        call: io.flutter.plugin.common.MethodCall,
        result: MethodChannel.Result
    ) {
        if (sessionVideoTransformer != null) {
            result.error(
                "SESSION_VIDEO_BUSY",
                "A moving photo video is already being prepared.",
                null
            )
            return
        }
        val videoPaths = call.argument<List<String>>("videoPaths")
        val posePhotoPath = call.argument<String>("posePhotoPath")
        val outputPath = call.argument<String>("outputPath")
        val countdownSeconds = call.argument<Int>("countdownSeconds")
        val rawPhotoSlots = call.argument<List<*>>("photoSlots")
        if (videoPaths.isNullOrEmpty() ||
            videoPaths.size > 5 ||
            posePhotoPath.isNullOrBlank() ||
            outputPath.isNullOrBlank() ||
            countdownSeconds == null ||
            countdownSeconds !in 1..5 ||
            rawPhotoSlots.isNullOrEmpty() ||
            rawPhotoSlots.size != videoPaths.size
        ) {
            result.error(
                "INVALID_SESSION_VIDEO",
                "The moving photo video request is incomplete.",
                null
            )
            return
        }

        val videoFiles = videoPaths.map { File(it) }
        val posePhoto = File(posePhotoPath)
        val outputFile = File(outputPath)
        if (videoFiles.any { !it.isFile || !it.canRead() } ||
            !posePhoto.isFile ||
            !posePhoto.canRead()
        ) {
            result.error(
                "SESSION_VIDEO_INPUT_MISSING",
                "A captured video or the selected photo is unavailable.",
                null
            )
            return
        }
        val photoSlots = rawPhotoSlots.map { rawSlot ->
            val coordinates = (rawSlot as? List<*>)?.map { value ->
                (value as? Number)?.toFloat()
            }
            if (coordinates == null ||
                coordinates.size != 4 ||
                coordinates.any { it == null }
            ) {
                null
            } else {
                coordinates.filterNotNull()
            }
        }
        if (photoSlots.isEmpty() || photoSlots.any { it == null }) {
            result.error(
                "INVALID_SESSION_VIDEO_SLOTS",
                "The selected photo frame has invalid photo openings.",
                null
            )
            return
        }

        val photoBounds = BitmapFactory.Options().apply {
            inJustDecodeBounds = true
        }
        BitmapFactory.decodeFile(posePhoto.absolutePath, photoBounds)
        if (photoBounds.outWidth <= 0 || photoBounds.outHeight <= 0) {
            result.error(
                "SESSION_VIDEO_PHOTO_INVALID",
                "The selected photo could not be opened for video composition.",
                null
            )
            return
        }
        var sampleSize = 1
        while (
            maxOf(photoBounds.outWidth, photoBounds.outHeight) / (sampleSize * 2) >=
                MAX_SESSION_VIDEO_DIMENSION
        ) {
            sampleSize *= 2
        }
        val decodeOptions = BitmapFactory.Options().apply {
            inSampleSize = sampleSize
            inPreferredConfig = Bitmap.Config.ARGB_8888
        }
        val decodedPhoto = BitmapFactory.decodeFile(
            posePhoto.absolutePath,
            decodeOptions
        )
        if (decodedPhoto == null) {
            result.error(
                "SESSION_VIDEO_PHOTO_INVALID",
                "The selected photo could not be opened for video composition.",
                null
            )
            return
        }
        var frameOverlay = decodedPhoto.copy(Bitmap.Config.ARGB_8888, true)
        decodedPhoto.recycle()
        val outputScale = minOf(
            1f,
            MAX_SESSION_VIDEO_DIMENSION.toFloat() /
                maxOf(frameOverlay.width, frameOverlay.height)
        )
        val outputWidth = ((frameOverlay.width * outputScale).toInt() / 2 * 2)
            .coerceAtLeast(2)
        val outputHeight = ((frameOverlay.height * outputScale).toInt() / 2 * 2)
            .coerceAtLeast(2)
        if (outputWidth != frameOverlay.width || outputHeight != frameOverlay.height) {
            val scaledOverlay = Bitmap.createScaledBitmap(
                frameOverlay,
                outputWidth,
                outputHeight,
                true
            )
            frameOverlay.recycle()
            val mutableOverlay = scaledOverlay.copy(Bitmap.Config.ARGB_8888, true)
            scaledOverlay.recycle()
            if (mutableOverlay == null) {
                result.error(
                    "SESSION_VIDEO_PHOTO_INVALID",
                    "The selected photo could not be resized for video composition.",
                    null
                )
                return
            }
            frameOverlay = mutableOverlay
        }
        val canvas = Canvas(frameOverlay)
        val clearPaint = Paint().apply {
            xfermode = PorterDuffXfermode(PorterDuff.Mode.CLEAR)
        }
        photoSlots.filterNotNull().forEach { slot ->
            val left = slot[0].coerceIn(0f, 1f) * frameOverlay.width
            val top = slot[1].coerceIn(0f, 1f) * frameOverlay.height
            val right = slot[2].coerceIn(0f, 1f) * frameOverlay.width
            val bottom = slot[3].coerceIn(0f, 1f) * frameOverlay.height
            if (right <= left || bottom <= top) {
                frameOverlay.recycle()
                result.error(
                    "INVALID_SESSION_VIDEO_SLOTS",
                    "The selected photo frame has an empty photo opening.",
                    null
                )
                return
            }
            canvas.drawRect(RectF(left, top, right, bottom), clearPaint)
        }
        clearPaint.xfermode = null

        val poseDurationMs = 500L
        val targetVideoDurationMs = countdownSeconds * 1000L - poseDurationMs
        val videoItems = mutableListOf<EditedMediaItem>()
        videoFiles.forEach { clip ->
            val retriever = MediaMetadataRetriever()
            val clipDurationMs = try {
                retriever.setDataSource(clip.absolutePath)
                retriever.extractMetadata(
                    MediaMetadataRetriever.METADATA_KEY_DURATION
                )?.toLongOrNull()
                    ?: throw IOException("Could not read the recorded clip duration.")
            } catch (error: Exception) {
                frameOverlay.recycle()
                result.error(
                    "SESSION_VIDEO_INPUT_INVALID",
                    "Could not read a recorded video clip: ${error.message}",
                    null
                )
                return
            } finally {
                retriever.release()
            }
            if (clipDurationMs <= 0) {
                frameOverlay.recycle()
                result.error(
                    "SESSION_VIDEO_INPUT_INVALID",
                    "A recorded video clip has no playable duration.",
                    null
                )
                return
            }
            val videoBuilder = MediaItem.Builder()
                .setUri(Uri.fromFile(clip))
            if (clipDurationMs > targetVideoDurationMs) {
                videoBuilder.setClippingConfiguration(
                    MediaItem.ClippingConfiguration.Builder()
                        .setEndPositionMs(targetVideoDurationMs)
                        .build()
                )
            }
            val video = videoBuilder.build()
            videoItems.add(
                EditedMediaItem.Builder(video)
                    .setRemoveAudio(true)
                    .setEffects(
                        Effects(
                            emptyList(),
                            listOf(
                                Presentation.createForWidthAndHeight(
                                    frameOverlay.width,
                                    frameOverlay.height,
                                    Presentation.LAYOUT_SCALE_TO_FIT_WITH_CROP
                                ),
                                OverlayEffect(
                                    listOf(
                                        BitmapOverlay.createStaticBitmapOverlay(frameOverlay)
                                    )
                                )
                            )
                        )
                    )
                    .build()
            )
            val pose = MediaItem.Builder()
                .setUri(Uri.fromFile(posePhoto))
                .setImageDurationMs(poseDurationMs)
                .build()
            videoItems.add(
                EditedMediaItem.Builder(pose)
                    .setFrameRate(30)
                    .setRemoveAudio(true)
                    .setEffects(
                        Effects(
                            emptyList(),
                            listOf(
                                Presentation.createForWidthAndHeight(
                                    frameOverlay.width,
                                    frameOverlay.height,
                                    Presentation.LAYOUT_SCALE_TO_FIT_WITH_CROP
                                )
                            )
                        )
                    )
                    .build()
            )
        }

        if (outputFile.exists() && !outputFile.delete()) {
            frameOverlay.recycle()
            result.error(
                "SESSION_VIDEO_OUTPUT_UNAVAILABLE",
                "The moving photo output file could not be replaced.",
                null
            )
            return
        }
        outputFile.parentFile?.let { parent ->
            if (!parent.exists() && !parent.mkdirs()) {
                frameOverlay.recycle()
                result.error(
                    "SESSION_VIDEO_OUTPUT_UNAVAILABLE",
                    "The moving photo output folder could not be created.",
                    null
                )
                return
            }
        }

        try {
            val sequence = EditedMediaItemSequence.Builder(videoItems).build()
            val composition = Composition.Builder(sequence).build()
            val encoderFactory = DefaultEncoderFactory.Builder(this)
                .setRequestedVideoEncoderSettings(
                    VideoEncoderSettings.Builder()
                        .setBitrate(SESSION_VIDEO_BITRATE)
                        .build()
                )
                .build()
            val transformer = Transformer.Builder(this)
                .setVideoMimeType(MimeTypes.VIDEO_H264)
                .setEncoderFactory(encoderFactory)
                .addListener(
                    object : Transformer.Listener {
                        override fun onCompleted(
                            composition: Composition,
                            exportResult: ExportResult
                        ) {
                            sessionVideoTransformer = null
                            frameOverlay.recycle()
                            if (!outputFile.isFile || outputFile.length() == 0L) {
                                result.error(
                                    "SESSION_VIDEO_EMPTY",
                                    "The moving photo video was not created.",
                                    null
                                )
                            } else {
                                result.success(outputFile.absolutePath)
                            }
                        }

                        override fun onError(
                            composition: Composition,
                            exportResult: ExportResult,
                            exportException: ExportException
                        ) {
                            Log.e(
                                "PhotoboothVideo",
                                "Moving photo export failed " +
                                    "(code=${exportException.errorCode}, " +
                                    "name=${exportException.errorCodeName})",
                                exportException
                            )
                            sessionVideoTransformer = null
                            frameOverlay.recycle()
                            outputFile.delete()
                            result.error(
                                "SESSION_VIDEO_EXPORT_FAILED",
                                "Could not compose the moving photo video " +
                                    "(code ${exportException.errorCodeName}): " +
                                    (exportException.cause?.message
                                        ?: exportException.message
                                        ?: "See Android log for details."),
                                null
                            )
                        }
                    }
                )
                .build()
            sessionVideoTransformer = transformer
            transformer.start(composition, outputFile.absolutePath)
        } catch (error: Exception) {
            sessionVideoTransformer = null
            frameOverlay.recycle()
            outputFile.delete()
            result.error(
                "SESSION_VIDEO_EXPORT_FAILED",
                "Could not start moving photo video composition: ${error.message}",
                null
            )
        }
    }

    private fun savePhoto(path: String) {
        val photo = File(path)
        if (!photo.isFile || !photo.canRead()) {
            throw IOException("The captured photo is unavailable.")
        }
        val extension = photo.extension.lowercase()
        val mimeType = when (extension) {
            "png" -> "image/png"
            "gif" -> "image/gif"
            else -> "image/jpeg"
        }
        val safeExtension = if (extension in setOf("png", "gif")) extension else "jpg"
        val name = "Photobooth_${System.currentTimeMillis()}.$safeExtension"

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val values = ContentValues().apply {
                put(MediaStore.Images.Media.DISPLAY_NAME, name)
                put(MediaStore.Images.Media.MIME_TYPE, mimeType)
                put(MediaStore.Images.Media.RELATIVE_PATH, "Pictures/Photobooth")
                put(MediaStore.Images.Media.IS_PENDING, 1)
            }
            val uri = contentResolver.insert(
                MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
                values
            ) ?: throw IOException("Could not create a photo in Pictures/Photobooth.")

            try {
                contentResolver.openOutputStream(uri)?.use { output ->
                    photo.inputStream().use { input -> input.copyTo(output) }
                } ?: throw IOException("Could not open the destination photo.")
                values.clear()
                values.put(MediaStore.Images.Media.IS_PENDING, 0)
                contentResolver.update(uri, values, null, null)
            } catch (error: Exception) {
                contentResolver.delete(uri, null, null)
                if (error is IOException) throw error
                throw IOException("Could not save the photo.", error)
            }
            return
        }

        val folder = File(
            Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES),
            "Photobooth"
        )
        if (!folder.exists() && !folder.mkdirs()) {
            throw IOException("Could not create the Photobooth pictures folder.")
        }
        if (!folder.isDirectory) throw IOException("The Photobooth pictures path is not a folder.")
        val destination = File(folder, name)
        photo.inputStream().use { input ->
            destination.outputStream().use { output -> input.copyTo(output) }
        }
        android.media.MediaScannerConnection.scanFile(
            this,
            arrayOf(destination.absolutePath),
            arrayOf(mimeType),
            null
        )
    }
}
