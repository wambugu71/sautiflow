package com.wambugu.sautiplay.sautiplay

import android.Manifest
import android.bluetooth.BluetoothA2dp
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothCodecConfig
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.app.Activity
import android.content.BroadcastReceiver
import android.content.ContentUris
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.hardware.usb.UsbConstants
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbManager
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.media.MediaScannerConnection
import android.net.Uri
import android.provider.MediaStore
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.core.content.ContextCompat
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {

    companion object {
        private const val TAG = "SautiHardware"
        private const val METHOD_CHANNEL = "com.wambugu.sautiflow/hardware"
        private const val EVENT_CHANNEL = "com.wambugu.sautiflow/hardware_stream"
        private const val REQUEST_BT_PERMISSION = 7749

        private const val ACTION_CODEC_CONFIG_CHANGED =
            "android.bluetooth.a2dp.profile.action.CODEC_CONFIG_CHANGED"
        private const val EXTRA_CODEC_STATUS =
            "android.bluetooth.extra.CODEC_STATUS"

        init {
            try {
                System.loadLibrary("sautiflow")
            } catch (e: Throwable) {
                try {
                    System.loadLibrary("audio_engine")
                } catch (e2: Throwable) {
                    // Ignore load error fallback
                }
            }
        }
    }

    // ── State ─────────────────────────────────────────────────────────────────
    private var eventSink: EventChannel.EventSink? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    private var bluetoothA2dp: BluetoothA2dp? = null
    private var bluetoothAdapter: BluetoothAdapter? = null
    private var cachedBtCodecConfig: BluetoothCodecConfig? = null
    private var cachedBtDeviceName: String? = null
    private var audioDeviceCallback: AudioDeviceCallback? = null
    private var multicastLock: WifiManager.MulticastLock? = null

    // Comprehensive BroadcastReceiver for Wired, Bluetooth, and USB audio events
    private val hardwareReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            Log.d(TAG, "Hardware event received: ${intent.action}")
            when (intent.action) {
                ACTION_CODEC_CONFIG_CHANGED -> {
                    captureCodecConfigFromIntent(intent)
                    pushCurrentSpecs()
                }
                BluetoothA2dp.ACTION_CONNECTION_STATE_CHANGED -> {
                    val state = intent.getIntExtra(
                        BluetoothProfile.EXTRA_STATE,
                        BluetoothProfile.STATE_DISCONNECTED
                    )
                    if (state == BluetoothProfile.STATE_DISCONNECTED) {
                        cachedBtCodecConfig = null
                        cachedBtDeviceName = null
                    }
                    pushCurrentSpecs()
                }
                BluetoothDevice.ACTION_ACL_DISCONNECTED -> {
                    cachedBtCodecConfig = null
                    cachedBtDeviceName = null
                    pushCurrentSpecs()
                }
                Intent.ACTION_HEADSET_PLUG,
                BluetoothDevice.ACTION_NAME_CHANGED,
                BluetoothDevice.ACTION_ACL_CONNECTED,
                BluetoothAdapter.ACTION_STATE_CHANGED,
                UsbManager.ACTION_USB_DEVICE_ATTACHED,
                UsbManager.ACTION_USB_DEVICE_DETACHED,
                AudioManager.ACTION_AUDIO_BECOMING_NOISY -> {
                    pushCurrentSpecs()
                }
            }
        }
    }

    private val btProfileListener = object : BluetoothProfile.ServiceListener {
        override fun onServiceConnected(profile: Int, proxy: BluetoothProfile) {
            if (profile == BluetoothProfile.A2DP) {
                bluetoothA2dp = proxy as BluetoothA2dp
                Log.d(TAG, "BluetoothA2dp profile connected")
                pushCurrentSpecs()
            }
        }

        override fun onServiceDisconnected(profile: Int) {
            if (profile == BluetoothProfile.A2DP) {
                bluetoothA2dp = null
                Log.d(TAG, "BluetoothA2dp profile disconnected")
                pushCurrentSpecs()
            }
        }
    }

    // ── Flutter Engine Setup ──────────────────────────────────────────────────
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            METHOD_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getHardwareAudioSpecs" -> {
                    try {
                        result.success(buildSpecsMap())
                    } catch (e: Exception) {
                        result.error("ERROR", e.message, null)
                    }
                }
                "acquireMulticastLock" -> {
                    acquireMulticastLock()
                    result.success(true)
                }
                "releaseMulticastLock" -> {
                    releaseMulticastLock()
                    result.success(true)
                }
                "installApk" -> {
                    val filePath = call.argument<String>("filePath")
                    if (filePath != null) {
                        try {
                            val file = java.io.File(filePath)
                            if (file.exists()) {
                                val uri = androidx.core.content.FileProvider.getUriForFile(
                                    this@MainActivity,
                                    "${applicationContext.packageName}.fileprovider",
                                    file
                                )
                                val intent = Intent(Intent.ACTION_VIEW).apply {
                                    setDataAndType(uri, "application/vnd.android.package-archive")
                                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                }
                                startActivity(intent)
                                result.success(true)
                            } else {
                                result.error("FILE_NOT_FOUND", "APK file does not exist", null)
                            }
                        } catch (e: Exception) {
                            result.error("INSTALL_ERROR", e.message, null)
                        }
                    } else {
                        result.error("INVALID_ARGS", "filePath is required", null)
                    }
                }
                "deleteMediaFile" -> {
                    val filePath = call.argument<String>("filePath")
                    if (!filePath.isNullOrBlank()) {
                        deleteMediaTracks(listOf(filePath), result)
                    } else {
                        result.error("INVALID_ARGS", "filePath is required", null)
                    }
                }
                "deleteMediaFiles" -> {
                    val filePaths = call.argument<List<String>>("filePaths")
                    if (!filePaths.isNullOrEmpty()) {
                        deleteMediaTracks(filePaths, result)
                    } else {
                        result.error("INVALID_ARGS", "filePaths is required and must not be empty", null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            EVENT_CHANNEL
        ).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, sink: EventChannel.EventSink) {
                Log.d(TAG, "EventChannel: Flutter subscribed")
                eventSink = sink
                pushCurrentSpecs()
            }

            override fun onCancel(arguments: Any?) {
                Log.d(TAG, "EventChannel: Flutter unsubscribed")
                eventSink = null
            }
        })
    }

    // ── Activity Lifecycle ────────────────────────────────────────────────────
    override fun onStart() {
        super.onStart()
        enableHighRefreshRateIfAvailable()
        setupAudioDeviceCallback()
        requestBluetoothPermissionIfNeeded()
        registerHardwareReceiver()
    }

    private fun enableHighRefreshRateIfAvailable() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            try {
                val display = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    display
                } else {
                    @Suppress("DEPRECATION")
                    window.windowManager.defaultDisplay
                }
                val modes = display?.supportedModes ?: return
                var maxRate = 60.0f
                var targetModeId = 0
                for (mode in modes) {
                    if (mode.refreshRate > maxRate) {
                        maxRate = mode.refreshRate
                        targetModeId = mode.modeId
                    }
                }
                if (targetModeId != 0) {
                    val params = window.attributes
                    params.preferredDisplayModeId = targetModeId
                    params.preferredRefreshRate = maxRate
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                        try {
                            params.javaClass.getField("preferredMinDisplayRefreshRate").setFloat(params, maxRate)
                            params.javaClass.getField("preferredMaxDisplayRefreshRate").setFloat(params, maxRate)
                        } catch (_: Throwable) {
                            // Ignored if not exposed on this Android API/OEM build
                        }
                    }
                    window.attributes = params
                    Log.d(TAG, "Configured high refresh rate: $maxRate Hz (mode $targetModeId)")
                }
            } catch (e: Exception) {
                Log.w(TAG, "Failed to configure high refresh rate: ${e.message}")
            }
        }
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) {
            enableHighRefreshRateIfAvailable()
        }
    }

    override fun onStop() {
        super.onStop()
        teardownAudioDeviceCallback()
        teardownBluetoothProfile()
        unregisterHardwareReceiver()
        releaseMulticastLock()
    }

    private fun requestBluetoothPermissionIfNeeded() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            if (ContextCompat.checkSelfPermission(
                    this, Manifest.permission.BLUETOOTH_CONNECT
                ) == PackageManager.PERMISSION_GRANTED
            ) {
                setupBluetoothProfile()
            } else {
                Log.d(TAG, "Requesting BLUETOOTH_CONNECT permission")
                requestPermissions(
                    arrayOf(Manifest.permission.BLUETOOTH_CONNECT),
                    REQUEST_BT_PERMISSION
                )
            }
        } else {
            setupBluetoothProfile()
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQUEST_BT_PERMISSION) {
            val granted = grantResults.isNotEmpty() &&
                    grantResults[0] == PackageManager.PERMISSION_GRANTED
            if (granted) {
                Log.d(TAG, "BLUETOOTH_CONNECT granted — connecting BT profile")
                setupBluetoothProfile()
            } else {
                Log.d(TAG, "BLUETOOTH_CONNECT denied — BT codec/name unavailable")
            }
            pushCurrentSpecs()
        }
    }

    // ── Setup / Teardown ──────────────────────────────────────────────────────
    private fun setupAudioDeviceCallback() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
            val cb = object : AudioDeviceCallback() {
                override fun onAudioDevicesAdded(addedDevices: Array<AudioDeviceInfo>) {
                    Log.d(TAG, "AudioDevicesAdded: ${addedDevices.map { it.type }}")
                    pushCurrentSpecs()
                }

                override fun onAudioDevicesRemoved(removedDevices: Array<AudioDeviceInfo>) {
                    Log.d(TAG, "AudioDevicesRemoved: ${removedDevices.map { it.type }}")
                    pushCurrentSpecs()
                }
            }
            audioDeviceCallback = cb
            audioManager.registerAudioDeviceCallback(cb, mainHandler)
            Log.d(TAG, "AudioDeviceCallback registered")
        }
    }

    private fun teardownAudioDeviceCallback() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
            audioDeviceCallback?.let { audioManager.unregisterAudioDeviceCallback(it) }
            audioDeviceCallback = null
        }
    }

    private fun setupBluetoothProfile() {
        if (!hasBtPermission()) return
        try {
            val bm = getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
            bluetoothAdapter = bm?.adapter
            bluetoothAdapter?.getProfileProxy(this, btProfileListener, BluetoothProfile.A2DP)
            Log.d(TAG, "BluetoothProfile proxy requested")
        } catch (e: Exception) {
            Log.w(TAG, "Failed to setup BT profile: ${e.message}")
        }
    }

    private fun teardownBluetoothProfile() {
        try {
            bluetoothA2dp?.let {
                bluetoothAdapter?.closeProfileProxy(BluetoothProfile.A2DP, it)
            }
            bluetoothA2dp = null
        } catch (e: Exception) {
            Log.w(TAG, "Failed to close BT profile: ${e.message}")
        }
    }

    private fun registerHardwareReceiver() {
        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_HEADSET_PLUG)
            addAction(BluetoothA2dp.ACTION_CONNECTION_STATE_CHANGED)
            addAction(ACTION_CODEC_CONFIG_CHANGED)
            addAction(BluetoothDevice.ACTION_NAME_CHANGED)
            addAction(BluetoothDevice.ACTION_ACL_CONNECTED)
            addAction(BluetoothDevice.ACTION_ACL_DISCONNECTED)
            addAction(BluetoothAdapter.ACTION_STATE_CHANGED)
            addAction(UsbManager.ACTION_USB_DEVICE_ATTACHED)
            addAction(UsbManager.ACTION_USB_DEVICE_DETACHED)
            addAction(AudioManager.ACTION_AUDIO_BECOMING_NOISY)
        }
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                registerReceiver(hardwareReceiver, filter, Context.RECEIVER_EXPORTED)
            } else {
                registerReceiver(hardwareReceiver, filter)
            }
            Log.d(TAG, "Hardware BroadcastReceiver registered")
        } catch (e: Exception) {
            Log.w(TAG, "Failed to register Hardware receiver: ${e.message}")
        }
    }

    private fun unregisterHardwareReceiver() {
        try {
            unregisterReceiver(hardwareReceiver)
        } catch (e: Exception) {
            // Ignore if not registered
        }
    }

    private fun acquireMulticastLock() {
        if (multicastLock == null) {
            val wifiManager = applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
            multicastLock = wifiManager?.createMulticastLock("SautiplayMulticastLock")?.apply {
                setReferenceCounted(true)
            }
        }
        try {
            if (multicastLock?.isHeld == false) {
                multicastLock?.acquire()
                Log.d(TAG, "Wifi MulticastLock acquired")
            }
        } catch (e: Exception) {
            Log.w(TAG, "Failed to acquire Wifi MulticastLock: ${e.message}")
        }
    }

    private fun releaseMulticastLock() {
        try {
            if (multicastLock?.isHeld == true) {
                multicastLock?.release()
                Log.d(TAG, "Wifi MulticastLock released")
            }
        } catch (e: Exception) {
            Log.w(TAG, "Failed to release Wifi MulticastLock: ${e.message}")
        }
    }

    // ── Core Logic ────────────────────────────────────────────────────────────
    private fun pushCurrentSpecs() {
        mainHandler.post {
            try {
                val map = buildSpecsMap()
                eventSink?.success(map)
            } catch (e: Exception) {
                Log.e(TAG, "pushCurrentSpecs error: ${e.message}")
            }
        }
    }

    private fun findAttachedUsbAudioDevice(): UsbDevice? {
        return try {
            val usbManager = getSystemService(Context.USB_SERVICE) as? UsbManager ?: return null
            for (device in usbManager.deviceList.values) {
                if (device.deviceClass == UsbConstants.USB_CLASS_AUDIO) {
                    return device
                }
                for (i in 0 until device.interfaceCount) {
                    val intf = device.getInterface(i)
                    if (intf.interfaceClass == UsbConstants.USB_CLASS_AUDIO &&
                        intf.interfaceSubclass == 2 /* USB_SUBCLASS_AUDIOSTREAMING */
                    ) {
                        return device
                    }
                }
            }
            null
        } catch (e: Exception) {
            Log.w(TAG, "findAttachedUsbAudioDevice error: ${e.message}")
            null
        }
    }

    private fun buildSpecsMap(): Map<String, Any?> {
        val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val defaultHalSampleRate = audioManager.getProperty(AudioManager.PROPERTY_OUTPUT_SAMPLE_RATE)?.toIntOrNull() ?: 48000
        val periodFrames = audioManager.getProperty(AudioManager.PROPERTY_OUTPUT_FRAMES_PER_BUFFER)?.toIntOrNull() ?: 192

        var deviceName = "Built-in Speaker"
        var sampleRate = defaultHalSampleRate
        var bitDepth = 32
        var isFloat = true
        var deviceType = "Built-in Speaker"
        var btCodec: String? = null
        var btDeviceName: String? = null
        var btSampleRate: Int? = null
        var btBitDepth: Int? = null
        var btChannelMode: String? = null
        var btQualityLabel: String? = null
        var selectedDeviceTypeCode = -1
        var supportedSampleRates: List<Int> = emptyList()
        var supportedBitDepths: List<Int> = emptyList()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val devices = audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS)

            var bestPriority = -1
            var bestDevice: AudioDeviceInfo? = null

            for (dev in devices) {
                val priority = devicePriority(dev.type)
                if (priority > bestPriority) {
                    bestPriority = priority
                    bestDevice = dev
                }
            }

            bestDevice?.let { dev ->
                selectedDeviceTypeCode = dev.type
                deviceType = mapDeviceType(dev.type)

                val rawName = dev.productName?.toString()
                deviceName = if (!rawName.isNullOrBlank()) {
                    rawName
                } else {
                    fallbackDeviceName(dev.type)
                }

                val (depth, float) = bestEncodingFromDevice(dev)
                bitDepth = depth
                isFloat = float
                supportedBitDepths = supportedBitDepthsFromDevice(dev)

                val devRates = dev.sampleRates
                if (devRates.isNotEmpty()) {
                    supportedSampleRates = devRates.toList().sorted()
                }
            }
        }

        val usbManager = getSystemService(Context.USB_SERVICE) as? UsbManager
        val usbAudioDev = findAttachedUsbAudioDevice()
        val isAudioMgrUsb = selectedDeviceTypeCode == AudioDeviceInfo.TYPE_USB_DEVICE ||
            selectedDeviceTypeCode == AudioDeviceInfo.TYPE_USB_HEADSET ||
            selectedDeviceTypeCode == AudioDeviceInfo.TYPE_USB_ACCESSORY

        if (usbAudioDev != null) {
            val usbProduct = usbAudioDev.productName?.trim()?.takeIf { it.isNotEmpty() }
            val usbManufacturer = usbAudioDev.manufacturerName?.trim()?.takeIf { it.isNotEmpty() }
            val resolvedUsbName = usbProduct ?: usbManufacturer ?: "USB Audio DAC"

            if (!isAudioMgrUsb) {
                // When libusb detaches snd-usb-audio kernel driver, AudioManager falls back
                // to built-in speaker; restore USB DAC metadata from UsbManager.
                deviceType = "USB DAC"
                deviceName = resolvedUsbName
                bitDepth = 32
                isFloat = false
                if (supportedSampleRates.isEmpty()) {
                    supportedSampleRates = listOf(
                        44100, 48000, 88200, 96000, 176400, 192000, 352800, 384000, 705600, 768000
                    )
                }
            } else if ((deviceName == "USB Audio DAC" || deviceName.isBlank()) && usbProduct != null) {
                deviceName = resolvedUsbName
            }
        }

        // Bluetooth codec details when BT route is active
        if (!isAudioMgrUsb && usbAudioDev == null && (selectedDeviceTypeCode == AudioDeviceInfo.TYPE_BLUETOOTH_A2DP ||
            selectedDeviceTypeCode == 26 /* TYPE_BLUETOOTH_LE */ ||
            selectedDeviceTypeCode == 23 /* TYPE_HEARING_AID */)
        ) {
            val btInfo = queryBluetoothCodec(
                isLeAudio = (selectedDeviceTypeCode == 26 /* TYPE_BLUETOOTH_LE */),
                fallbackName = deviceName
            )
            btCodec = btInfo?.codecName
            btDeviceName = btInfo?.deviceName
            btSampleRate = btInfo?.sampleRate
            btBitDepth = btInfo?.bitDepth
            btChannelMode = btInfo?.channelMode
            btQualityLabel = btInfo?.qualityLabel
            if (!btDeviceName.isNullOrBlank()) {
                deviceName = btDeviceName
            }
            if (btSampleRate != null && btSampleRate > 0) {
                sampleRate = btSampleRate
            }
            if (btBitDepth != null && btBitDepth > 0) {
                bitDepth = btBitDepth
                isFloat = false
            }
        }

        val latencyMs = (periodFrames.toDouble() * 2.0 / sampleRate.toDouble()) * 1000.0

        return mapOf(
            "deviceName" to deviceName,
            "sampleRate" to sampleRate,
            "bitDepth" to bitDepth,
            "isFloat" to isFloat,
            "channels" to 2,
            "periodSizeFrames" to periodFrames,
            "periodCount" to 2,
            "latencyMs" to latencyMs,
            "deviceType" to deviceType,
            "bluetoothCodec" to btCodec,
            "bluetoothDeviceName" to btDeviceName,
            "btSampleRate" to btSampleRate,
            "btBitDepth" to btBitDepth,
            "btChannelMode" to btChannelMode,
            "btQualityLabel" to btQualityLabel,
            "supportedSampleRates" to supportedSampleRates,
            "supportedBitDepths" to supportedBitDepths,
            "usbDacAttached" to (usbAudioDev != null),
            "usbHasPermission" to (if (usbAudioDev != null && usbManager != null) usbManager.hasPermission(usbAudioDev) else false),
            "androidVersion" to Build.VERSION.SDK_INT,
            "androidRelease" to Build.VERSION.RELEASE,
        )
    }

    private fun devicePriority(type: Int): Int = when (type) {
        AudioDeviceInfo.TYPE_USB_DEVICE,
        AudioDeviceInfo.TYPE_USB_HEADSET,
        AudioDeviceInfo.TYPE_USB_ACCESSORY -> 5

        AudioDeviceInfo.TYPE_BLUETOOTH_A2DP,
        26 /* TYPE_BLUETOOTH_LE */,
        23 /* TYPE_HEARING_AID */ -> 4

        AudioDeviceInfo.TYPE_WIRED_HEADSET,
        AudioDeviceInfo.TYPE_WIRED_HEADPHONES,
        AudioDeviceInfo.TYPE_LINE_ANALOG,
        19 /* TYPE_AUX_LINE */ -> 3

        AudioDeviceInfo.TYPE_HDMI,
        AudioDeviceInfo.TYPE_HDMI_ARC,
        29 /* TYPE_HDMI_EARC */ -> 2

        AudioDeviceInfo.TYPE_BUILTIN_SPEAKER,
        AudioDeviceInfo.TYPE_BUILTIN_EARPIECE -> 1

        else -> 0
    }

    private fun mapDeviceType(type: Int): String = when (type) {
        AudioDeviceInfo.TYPE_USB_DEVICE,
        AudioDeviceInfo.TYPE_USB_HEADSET,
        AudioDeviceInfo.TYPE_USB_ACCESSORY -> "USB DAC"

        AudioDeviceInfo.TYPE_BLUETOOTH_A2DP -> "Bluetooth Wireless"
        26 /* TYPE_BLUETOOTH_LE */ -> "Bluetooth LE Audio"
        23 /* TYPE_HEARING_AID */ -> "Bluetooth Hearing Aid"

        AudioDeviceInfo.TYPE_WIRED_HEADSET -> "3.5mm Headset"
        AudioDeviceInfo.TYPE_WIRED_HEADPHONES -> "3.5mm Headphones"
        AudioDeviceInfo.TYPE_LINE_ANALOG,
        19 /* TYPE_AUX_LINE */ -> "Line Out (Analog)"

        AudioDeviceInfo.TYPE_BUILTIN_SPEAKER -> "Built-in Speaker"
        AudioDeviceInfo.TYPE_BUILTIN_EARPIECE -> "Built-in Earpiece"

        AudioDeviceInfo.TYPE_HDMI,
        AudioDeviceInfo.TYPE_HDMI_ARC,
        29 /* TYPE_HDMI_EARC */ -> "HDMI Audio"

        AudioDeviceInfo.TYPE_DOCK -> "Dock / Accessory"
        else -> "Speakers / Output Device"
    }

    private fun fallbackDeviceName(type: Int): String = when (type) {
        AudioDeviceInfo.TYPE_USB_DEVICE,
        AudioDeviceInfo.TYPE_USB_HEADSET -> "USB Audio DAC"

        AudioDeviceInfo.TYPE_BLUETOOTH_A2DP -> "Bluetooth Headphones"
        26 /* TYPE_BLUETOOTH_LE */ -> "Bluetooth LE Device"

        AudioDeviceInfo.TYPE_WIRED_HEADSET,
        AudioDeviceInfo.TYPE_WIRED_HEADPHONES -> "3.5mm Wired Headphones"

        AudioDeviceInfo.TYPE_BUILTIN_SPEAKER -> "Device Speaker"
        else -> "Output Device"
    }

    private fun bestEncodingFromDevice(dev: AudioDeviceInfo): Pair<Int, Boolean> {
        var maxBits = 16
        var isFloat = false
        for (enc in dev.encodings) {
            when (enc) {
                4  /* ENCODING_PCM_FLOAT */        -> { isFloat = true; if (32 > maxBits) maxBits = 32 }
                21 /* ENCODING_PCM_24BIT_PACKED */ -> if (24 > maxBits) maxBits = 24
                22 /* ENCODING_PCM_32BIT */        -> if (32 > maxBits) maxBits = 32
                2  /* ENCODING_PCM_16BIT */        -> if (16 > maxBits) maxBits = 16
            }
        }
        return Pair(maxBits, isFloat)
    }

    private fun supportedBitDepthsFromDevice(dev: AudioDeviceInfo): List<Int> {
        val bits = sortedSetOf<Int>()
        for (enc in dev.encodings) {
            when (enc) {
                2  /* ENCODING_PCM_16BIT */        -> bits.add(16)
                21 /* ENCODING_PCM_24BIT_PACKED */ -> bits.add(24)
                22 /* ENCODING_PCM_32BIT */,
                4  /* ENCODING_PCM_FLOAT */        -> bits.add(32)
            }
        }
        return bits.toList()
    }

    private fun captureCodecConfigFromIntent(intent: Intent) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        try {
            @Suppress("DEPRECATION")
            val device = intent.getParcelableExtra<BluetoothDevice>(BluetoothDevice.EXTRA_DEVICE)
            if (device != null && hasBtPermission()) {
                @Suppress("DEPRECATION")
                cachedBtDeviceName = device.name ?: cachedBtDeviceName
            }
            @Suppress("DEPRECATION")
            val codecStatus = intent.getParcelableExtra<android.os.Parcelable>(EXTRA_CODEC_STATUS)
            if (codecStatus != null) {
                val getConfigMethod = codecStatus.javaClass.getMethod("getCodecConfig")
                val config = getConfigMethod.invoke(codecStatus) as? BluetoothCodecConfig
                if (config != null) {
                    cachedBtCodecConfig = config
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "captureCodecConfigFromIntent failed: ${e.message}")
        }
    }

    private data class BluetoothCodecSnapshot(
        val codecName: String,
        val deviceName: String,
        val sampleRate: Int,
        val bitDepth: Int,
        val channelMode: String? = null,
        val qualityLabel: String? = null,
    )

    private fun parseBluetoothCodecConfig(
        config: BluetoothCodecConfig,
        deviceName: String
    ): BluetoothCodecSnapshot {
        // Check codecName / toString() first for vendor codecs (LHDC, aptX Adaptive, aptX Lossless, SSC, etc.)
        val rawStr = config.toString().uppercase()
        val codecName = when (config.codecType) {
            BluetoothCodecConfig.SOURCE_CODEC_TYPE_SBC     -> "SBC"
            BluetoothCodecConfig.SOURCE_CODEC_TYPE_AAC     -> "AAC"
            BluetoothCodecConfig.SOURCE_CODEC_TYPE_APTX    -> "aptX"
            BluetoothCodecConfig.SOURCE_CODEC_TYPE_APTX_HD -> "aptX HD"
            BluetoothCodecConfig.SOURCE_CODEC_TYPE_LDAC    -> "LDAC"
            5 /* SOURCE_CODEC_TYPE_LC3 (API 33+) */        -> if (rawStr.contains("OPUS")) "Opus" else "LC3"
            6 /* SOURCE_CODEC_TYPE_OPUS / LC3 */           -> when {
                rawStr.contains("OPUS") -> "Opus"
                rawStr.contains("LC3") -> "LC3"
                rawStr.contains("APTX") && rawStr.contains("ADAPTIVE") -> "aptX Adaptive"
                rawStr.contains("LHDC") -> "LHDC"
                else -> "LC3"
            }
            7                                              -> when {
                rawStr.contains("OPUS") -> "Opus"
                rawStr.contains("LHDC") -> "LHDC"
                rawStr.contains("APTX") && rawStr.contains("LOSSLESS") -> "aptX Lossless"
                rawStr.contains("APTX") && rawStr.contains("ADAPTIVE") -> "aptX Adaptive"
                else -> "Opus"
            }
            else                                           -> when {
                rawStr.contains("APTX") && rawStr.contains("LOSSLESS") -> "aptX Lossless"
                rawStr.contains("APTX") && rawStr.contains("ADAPTIVE") -> "aptX Adaptive"
                rawStr.contains("APTX") && rawStr.contains("HD") -> "aptX HD"
                rawStr.contains("APTX") -> "aptX"
                rawStr.contains("LDAC") -> "LDAC"
                rawStr.contains("LHDC") -> "LHDC"
                rawStr.contains("SSC") || rawStr.contains("SCALABLE") -> "Samsung SSC"
                rawStr.contains("LC3") -> "LC3"
                rawStr.contains("OPUS") -> "Opus"
                rawStr.contains("AAC") -> "AAC"
                else -> "SBC"
            }
        }

        val sampleRate = when (config.sampleRate) {
            BluetoothCodecConfig.SAMPLE_RATE_44100  -> 44100
            BluetoothCodecConfig.SAMPLE_RATE_48000  -> 48000
            BluetoothCodecConfig.SAMPLE_RATE_88200  -> 88200
            BluetoothCodecConfig.SAMPLE_RATE_96000  -> 96000
            BluetoothCodecConfig.SAMPLE_RATE_176400 -> 176400
            BluetoothCodecConfig.SAMPLE_RATE_192000 -> 192000
            else                                    -> when (codecName) {
                "aptX HD", "LDAC", "LHDC", "LC3", "Opus" -> 48000
                else -> 44100
            }
        }

        val bits = when (config.bitsPerSample) {
            BluetoothCodecConfig.BITS_PER_SAMPLE_16 -> 16
            BluetoothCodecConfig.BITS_PER_SAMPLE_24 -> 24
            BluetoothCodecConfig.BITS_PER_SAMPLE_32 -> 32
            else                                    -> when (codecName) {
                "aptX HD", "LDAC", "LHDC", "aptX Adaptive", "aptX Lossless" -> 24
                else -> 16
            }
        }

        val channelMode = when (config.channelMode) {
            BluetoothCodecConfig.CHANNEL_MODE_MONO   -> "Mono"
            BluetoothCodecConfig.CHANNEL_MODE_STEREO -> "Stereo"
            else                                     -> "Stereo"
        }

        var qualityLabel: String? = null
        if (codecName == "LDAC") {
            qualityLabel = when (config.codecSpecific1) {
                1000L -> "990/909 kbps (Quality)"
                1001L -> "660/606 kbps (Balanced)"
                1002L -> "330/303 kbps (Connection)"
                1003L -> "Adaptive Bitrate"
                else  -> null
            }
        }

        return BluetoothCodecSnapshot(
            codecName = codecName,
            deviceName = deviceName,
            sampleRate = sampleRate,
            bitDepth = bits,
            channelMode = channelMode,
            qualityLabel = qualityLabel,
        )
    }

    private fun queryBluetoothCodecViaReflection(
        a2dp: BluetoothA2dp,
        device: BluetoothDevice,
        deviceName: String
    ): BluetoothCodecSnapshot {
        try {
            val method = a2dp.javaClass.getMethod("getCodecStatus", BluetoothDevice::class.java)
            val codecStatus = method.invoke(a2dp, device)
            if (codecStatus != null) {
                val getConfigMethod = codecStatus.javaClass.getMethod("getCodecConfig")
                val config = getConfigMethod.invoke(codecStatus) as? BluetoothCodecConfig
                if (config != null) {
                    cachedBtCodecConfig = config
                    return parseBluetoothCodecConfig(config, deviceName)
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "Reflection getCodecStatus failed: ${e.message}")
        }
        cachedBtCodecConfig?.let { return parseBluetoothCodecConfig(it, deviceName) }
        return BluetoothCodecSnapshot("SBC", deviceName, 44100, 16, "Stereo", null)
    }

    private fun queryBluetoothCodec(
        isLeAudio: Boolean = false,
        fallbackName: String = "Bluetooth Audio Device"
    ): BluetoothCodecSnapshot? {
        if (isLeAudio) {
            return BluetoothCodecSnapshot(
                codecName = "LC3",
                deviceName = cachedBtDeviceName ?: fallbackName,
                sampleRate = 48000,
                bitDepth = 24,
                channelMode = "Stereo",
                qualityLabel = "LE Audio"
            )
        }
        if (!hasBtPermission()) {
            cachedBtCodecConfig?.let {
                return parseBluetoothCodecConfig(it, cachedBtDeviceName ?: fallbackName)
            }
            return null
        }
        val a2dp = bluetoothA2dp
        if (a2dp == null) {
            cachedBtCodecConfig?.let {
                return parseBluetoothCodecConfig(it, cachedBtDeviceName ?: fallbackName)
            }
            return null
        }

        return try {
            var connectedDevices: List<BluetoothDevice> = emptyList()
            try {
                @Suppress("DEPRECATION")
                connectedDevices = a2dp.connectedDevices
            } catch (e: Exception) {
                // Ignore exception and try fallback
            }

            if (connectedDevices.isEmpty()) {
                try {
                    connectedDevices = a2dp.getDevicesMatchingConnectionStates(
                        intArrayOf(BluetoothProfile.STATE_CONNECTED)
                    )
                } catch (e: Exception) {
                    // Ignore exception
                }
            }

            if (connectedDevices.isEmpty()) {
                cachedBtCodecConfig?.let {
                    return parseBluetoothCodecConfig(it, cachedBtDeviceName ?: fallbackName)
                }
                return null
            }

            val device = connectedDevices.first()
            @Suppress("DEPRECATION")
            val name = device.name ?: cachedBtDeviceName ?: fallbackName
            cachedBtDeviceName = name

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                queryBluetoothCodecViaReflection(a2dp, device, name)
            } else {
                BluetoothCodecSnapshot("SBC", name, 44100, 16, "Stereo", null)
            }
        } catch (e: Exception) {
            Log.w(TAG, "queryBluetoothCodec error: ${e.message}")
            cachedBtCodecConfig?.let {
                return parseBluetoothCodecConfig(it, cachedBtDeviceName ?: fallbackName)
            }
            null
        }
    }

    private fun hasBtPermission(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            ContextCompat.checkSelfPermission(
                this, Manifest.permission.BLUETOOTH_CONNECT
            ) == PackageManager.PERMISSION_GRANTED
        } else {
            true
        }
    }

    // ── Media Deletion (Scoped Storage & MediaStore compliant) ──────────────────
    private var pendingDeleteResult: MethodChannel.Result? = null
    private var pendingDeletePaths: List<String> = emptyList()
    private val REQUEST_CODE_DELETE_MEDIA = 7750

    private fun deleteMediaTracks(filePaths: List<String>, result: MethodChannel.Result) {
        Thread {
            try {
                val canonicalPaths = filePaths.map { raw ->
                    val file = java.io.File(raw)
                    try { file.canonicalPath } catch (e: Exception) { file.absolutePath }
                }.distinct()

                val succeededPaths = mutableListOf<String>()
                val needsScopedStoragePaths = mutableListOf<String>()

                for (canonicalPath in canonicalPaths) {
                    val targetFile = java.io.File(canonicalPath)
                    if (!targetFile.exists()) {
                        val uri = getMediaUriFromPath(canonicalPath)
                        if (uri != null) {
                            try {
                                contentResolver.delete(uri, null, null)
                            } catch (_: Exception) {}
                        }
                        succeededPaths.add(canonicalPath)
                        continue
                    }

                    // Strategy 1: Direct file deletion attempt (succeeds if app-owned or MANAGE_EXTERNAL_STORAGE is active)
                    var directDeleted = false
                    try {
                        directDeleted = targetFile.delete()
                    } catch (_: Exception) {
                        directDeleted = false
                    }

                    if (directDeleted) {
                        succeededPaths.add(canonicalPath)
                    } else {
                        needsScopedStoragePaths.add(canonicalPath)
                    }
                }

                // If all files were deleted directly, no Scoped Storage system prompt is needed!
                if (needsScopedStoragePaths.isEmpty()) {
                    if (succeededPaths.isNotEmpty()) {
                        MediaScannerConnection.scanFile(
                            this@MainActivity,
                            succeededPaths.toTypedArray(),
                            null,
                            null
                        )
                    }
                    mainHandler.post {
                        result.success(mapOf(
                            "success" to true,
                            "deleted" to true,
                            "deletedCount" to succeededPaths.size,
                            "deletedPaths" to succeededPaths
                        ))
                    }
                    return@Thread
                }

                // Strategy 2: MediaStore delete request (Scoped Storage compliant on Android 10+)
                val urisToDelete = mutableListOf<Uri>()
                val pathsWithUri = mutableListOf<String>()
                val unresolvedPaths = mutableListOf<String>()

                for (path in needsScopedStoragePaths) {
                    var uri = getMediaUriFromPath(path)
                    if (uri == null) {
                        // Attempt synchronous indexing with MediaScanner first
                        val latch = java.util.concurrent.CountDownLatch(1)
                        MediaScannerConnection.scanFile(
                            this@MainActivity,
                            arrayOf(path),
                            null
                        ) { _, scannedUri ->
                            if (scannedUri != null) {
                                uri = scannedUri
                            }
                            latch.countDown()
                        }
                        try {
                            latch.await(500, java.util.concurrent.TimeUnit.MILLISECONDS)
                        } catch (_: Exception) {}
                        if (uri == null) {
                            uri = getMediaUriFromPath(path)
                        }
                    }

                    if (uri != null) {
                        urisToDelete.add(uri!!)
                        pathsWithUri.add(path)
                    } else {
                        unresolvedPaths.add(path)
                    }
                }

                if (urisToDelete.isNotEmpty()) {
                    mainHandler.post {
                        performBatchMediaStoreDelete(urisToDelete, succeededPaths + pathsWithUri, result)
                    }
                } else {
                    mainHandler.post {
                        if (succeededPaths.isNotEmpty()) {
                            result.success(mapOf(
                                "success" to true,
                                "deleted" to false,
                                "deletedCount" to succeededPaths.size,
                                "deletedPaths" to succeededPaths,
                                "failedPaths" to unresolvedPaths
                            ))
                        } else {
                            result.error(
                                "PERMISSION_DENIED",
                                "Android denied permission to delete these files. Please ensure 'All files access' is granted in App Info > Permissions.",
                                null
                            )
                        }
                    }
                }
            } catch (e: Exception) {
                mainHandler.post {
                    result.error("DELETE_ERROR", "Error during media deletion: ${e.message}", null)
                }
            }
        }.start()
    }

    private fun getMediaUriFromPath(canonicalPath: String): Uri? {
        try {
            val collection = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                MediaStore.Audio.Media.getContentUri(MediaStore.VOLUME_EXTERNAL)
            } else {
                MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
            }
            val projection = arrayOf(MediaStore.Audio.Media._ID, MediaStore.Audio.Media.DATA)

            contentResolver.query(
                collection,
                projection,
                "${MediaStore.Audio.Media.DATA} = ?",
                arrayOf(canonicalPath),
                null
            )?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val id = cursor.getLong(cursor.getColumnIndexOrThrow(MediaStore.Audio.Media._ID))
                    return ContentUris.withAppendedId(collection, id)
                }
            }

            // Fallback: Check MediaStore.Files in case it was indexed as generic media/download file
            val filesCollection = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                MediaStore.Files.getContentUri(MediaStore.VOLUME_EXTERNAL)
            } else {
                MediaStore.Files.getContentUri("external")
            }
            contentResolver.query(
                filesCollection,
                arrayOf(MediaStore.Files.FileColumns._ID, MediaStore.Files.FileColumns.DATA),
                "${MediaStore.Files.FileColumns.DATA} = ?",
                arrayOf(canonicalPath),
                null
            )?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val id = cursor.getLong(cursor.getColumnIndexOrThrow(MediaStore.Files.FileColumns._ID))
                    return ContentUris.withAppendedId(filesCollection, id)
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "getMediaUriFromPath error: ${e.message}")
        }
        return null
    }

    private fun performBatchMediaStoreDelete(
        mediaUris: List<Uri>,
        expectedPaths: List<String>,
        result: MethodChannel.Result
    ) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            // Android 11+ (API 30+) - ONE single system prompt for all files combined!
            try {
                val pendingIntent = MediaStore.createDeleteRequest(contentResolver, mediaUris)
                pendingDeleteResult = result
                pendingDeletePaths = expectedPaths
                startIntentSenderForResult(
                    pendingIntent.intentSender,
                    REQUEST_CODE_DELETE_MEDIA,
                    null,
                    0,
                    0,
                    0
                )
            } catch (e: Exception) {
                Log.e(TAG, "createDeleteRequest failed", e)
                result.error("DELETE_FAILED", "Failed to request media deletion: ${e.message}", null)
            }
        } else if (Build.VERSION.SDK_INT == Build.VERSION_CODES.Q) {
            // Android 10 (API 29)
            try {
                var deletedCount = 0
                for (uri in mediaUris) {
                    val rows = contentResolver.delete(uri, null, null)
                    if (rows > 0) deletedCount++
                }
                result.success(mapOf(
                    "success" to true,
                    "deleted" to true,
                    "deletedCount" to deletedCount,
                    "deletedPaths" to expectedPaths
                ))
            } catch (recoverable: Exception) {
                val intentSender = if (recoverable is android.app.RecoverableSecurityException) {
                    recoverable.userAction.actionIntent.intentSender
                } else null

                if (intentSender != null) {
                    pendingDeleteResult = result
                    pendingDeletePaths = expectedPaths
                    try {
                        startIntentSenderForResult(
                            intentSender,
                            REQUEST_CODE_DELETE_MEDIA,
                            null,
                            0,
                            0,
                            0
                        )
                    } catch (e: Exception) {
                        result.error("DELETE_FAILED", "User action intent failed: ${e.message}", null)
                    }
                } else {
                    result.error("DELETE_FAILED", "Failed to delete: ${recoverable.message}", null)
                }
            }
        } else {
            // Android 9 and below
            try {
                for (uri in mediaUris) {
                    contentResolver.delete(uri, null, null)
                }
                val deletedList = mutableListOf<String>()
                for (path in expectedPaths) {
                    val f = java.io.File(path)
                    if (f.exists()) f.delete()
                    deletedList.add(path)
                }
                result.success(mapOf(
                    "success" to true,
                    "deleted" to true,
                    "deletedCount" to deletedList.size,
                    "deletedPaths" to deletedList
                ))
            } catch (e: Exception) {
                result.error("DELETE_FAILED", "Failed to delete file: ${e.message}", null)
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQUEST_CODE_DELETE_MEDIA) {
            val res = pendingDeleteResult
            val paths = pendingDeletePaths
            pendingDeleteResult = null
            pendingDeletePaths = emptyList()

            if (resultCode == Activity.RESULT_OK) {
                val actuallyDeleted = mutableListOf<String>()
                for (path in paths) {
                    try {
                        val f = java.io.File(path)
                        if (f.exists()) f.delete()
                    } catch (_: Exception) {}
                    actuallyDeleted.add(path)
                }
                if (paths.isNotEmpty()) {
                    MediaScannerConnection.scanFile(this@MainActivity, paths.toTypedArray(), null, null)
                }
                res?.success(mapOf(
                    "success" to true,
                    "deleted" to true,
                    "deletedCount" to actuallyDeleted.size,
                    "deletedPaths" to actuallyDeleted
                ))
            } else {
                res?.success(mapOf(
                    "success" to false,
                    "cancelled" to true,
                    "message" to "Deletion was cancelled by user.",
                    "deletedCount" to 0,
                    "deletedPaths" to emptyList<String>()
                ))
            }
        }
    }
}

data class Quadruple<A, B, C, D>(val first: A, val second: B, val third: C, val fourth: D)
