package com.wambugu.sautiplay.sautiplay

import android.Manifest
import android.bluetooth.BluetoothA2dp
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothCodecConfig
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.media.AudioDeviceCallback  // Top-level class, NOT AudioManager.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.annotation.RequiresApi
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

        // ACTION_CODEC_CONFIG_CHANGED was added in API 28 — use raw string to avoid
        // compileSdk issues on older toolchain versions
        private const val ACTION_CODEC_CONFIG_CHANGED =
            "android.bluetooth.a2dp.profile.action.CODEC_CONFIG_CHANGED"

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

    // BluetoothA2dp profile proxy — obtained asynchronously
    private var bluetoothA2dp: BluetoothA2dp? = null
    private var bluetoothAdapter: BluetoothAdapter? = null

    // AudioDeviceCallback — declared lazily so API-23 guard works at the call site
    // (the callback field itself is fine to reference at any API since the class is
    //  in android.media.AudioDeviceCallback from API 23 onward)
    private var audioDeviceCallback: AudioDeviceCallback? = null

    // BroadcastReceiver for Bluetooth A2DP connection and codec changes
    private val bluetoothReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            when (intent.action) {
                BluetoothA2dp.ACTION_CONNECTION_STATE_CHANGED -> {
                    Log.d(TAG, "BT A2DP connection state changed")
                    pushCurrentSpecs()
                }
                ACTION_CODEC_CONFIG_CHANGED -> {
                    Log.d(TAG, "BT codec config changed")
                    pushCurrentSpecs()
                }
                BluetoothDevice.ACTION_NAME_CHANGED -> {
                    Log.d(TAG, "BT device name changed")
                    pushCurrentSpecs()
                }
            }
        }
    }

    // BluetoothProfile service listener — connects to A2DP profile proxy
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
            }
        }
    }

    // ── Flutter Engine Setup ──────────────────────────────────────────────────
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // ── Legacy one-shot MethodChannel (kept for backward compat) ───────────
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            METHOD_CHANNEL
        ).setMethodCallHandler { call, result ->
            if (call.method == "getHardwareAudioSpecs") {
                try {
                    result.success(buildSpecsMap())
                } catch (e: Exception) {
                    result.error("ERROR", e.message, null)
                }
            } else {
                result.notImplemented()
            }
        }

        // ── Live EventChannel ──────────────────────────────────────────────────
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
        setupAudioDeviceCallback()
        requestBluetoothPermissionIfNeeded()
        registerBluetoothReceiver()
    }

    override fun onStop() {
        super.onStop()
        teardownAudioDeviceCallback()
        teardownBluetoothProfile()
        unregisterBluetoothReceiver()
    }

    /**
     * On Android 12+ (API 31), BLUETOOTH_CONNECT is a runtime permission.
     * We request it here — the system dialog appears once and is remembered.
     * On older Android versions no runtime permission is required.
     */
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
                // setupBluetoothProfile() called from onRequestPermissionsResult
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
            // Push updated specs either way
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

    private fun registerBluetoothReceiver() {
        val filter = IntentFilter().apply {
            addAction(BluetoothA2dp.ACTION_CONNECTION_STATE_CHANGED)
            addAction(ACTION_CODEC_CONFIG_CHANGED)
            addAction(BluetoothDevice.ACTION_NAME_CHANGED)
        }
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                registerReceiver(bluetoothReceiver, filter, Context.RECEIVER_EXPORTED)
            } else {
                registerReceiver(bluetoothReceiver, filter)
            }
            Log.d(TAG, "BT BroadcastReceiver registered")
        } catch (e: Exception) {
            Log.w(TAG, "Failed to register BT receiver: ${e.message}")
        }
    }

    private fun unregisterBluetoothReceiver() {
        try {
            unregisterReceiver(bluetoothReceiver)
        } catch (e: Exception) {
            // Already unregistered or never registered
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

    private fun buildSpecsMap(): Map<String, Any?> {
        val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val sampleRate = audioManager.getProperty(AudioManager.PROPERTY_OUTPUT_SAMPLE_RATE)?.toIntOrNull() ?: 48000
        val periodFrames = audioManager.getProperty(AudioManager.PROPERTY_OUTPUT_FRAMES_PER_BUFFER)?.toIntOrNull() ?: 192

        var deviceName = "Default Output Device"
        var bitDepth = 32
        var isFloat = true
        var deviceType = "Speakers / Output Device"
        var btCodec: String? = null
        var btDeviceName: String? = null
        var btSampleRate: Int? = null
        var btBitDepth: Int? = null
        var selectedDeviceTypeCode = -1

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
                val name = dev.productName?.toString()
                if (!name.isNullOrBlank()) deviceName = name

                selectedDeviceTypeCode = dev.type
                deviceType = mapDeviceType(dev.type)

                val (depth, float) = bestEncodingFromDevice(dev)
                bitDepth = depth
                isFloat = float
            }
        }

        // Bluetooth codec — only when BT is the active route
        if (selectedDeviceTypeCode == AudioDeviceInfo.TYPE_BLUETOOTH_A2DP ||
            selectedDeviceTypeCode == 26 /* TYPE_BLUETOOTH_LE, API 31+ */
        ) {
            val btInfo = queryBluetoothCodec()
            btCodec = btInfo?.first
            btDeviceName = btInfo?.second
            btSampleRate = btInfo?.third
            btBitDepth = btInfo?.fourth
            if (!btDeviceName.isNullOrBlank()) deviceName = btDeviceName!!
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
            "androidVersion" to Build.VERSION.SDK_INT,
            "androidRelease" to Build.VERSION.RELEASE,
        )
    }

    private fun devicePriority(type: Int): Int = when (type) {
        AudioDeviceInfo.TYPE_USB_DEVICE,
        AudioDeviceInfo.TYPE_USB_HEADSET -> 4
        AudioDeviceInfo.TYPE_BLUETOOTH_A2DP,
        26 /* TYPE_BLUETOOTH_LE */ -> 3
        AudioDeviceInfo.TYPE_WIRED_HEADSET,
        AudioDeviceInfo.TYPE_WIRED_HEADPHONES -> 2
        AudioDeviceInfo.TYPE_BUILTIN_SPEAKER -> 1
        else -> 0
    }

    private fun mapDeviceType(type: Int): String = when (type) {
        AudioDeviceInfo.TYPE_USB_DEVICE,
        AudioDeviceInfo.TYPE_USB_HEADSET -> "USB DAC"
        AudioDeviceInfo.TYPE_BLUETOOTH_A2DP -> "Bluetooth Wireless"
        26 /* TYPE_BLUETOOTH_LE */ -> "Bluetooth LE Audio"
        AudioDeviceInfo.TYPE_WIRED_HEADSET -> "3.5mm Headset"
        AudioDeviceInfo.TYPE_WIRED_HEADPHONES -> "3.5mm Headphone Jack"
        AudioDeviceInfo.TYPE_BUILTIN_SPEAKER -> "Built-in Speaker"
        AudioDeviceInfo.TYPE_BUILTIN_EARPIECE -> "Built-in Earpiece"
        AudioDeviceInfo.TYPE_HDMI -> "HDMI Audio"
        AudioDeviceInfo.TYPE_LINE_ANALOG -> "Line Out (Analog)"
        AudioDeviceInfo.TYPE_DOCK -> "Dock / Accessory"
        else -> "Speakers / Output Device"
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

    /**
     * Queries BluetoothA2dp for the active connected device and its codec.
     * Returns (codecName, deviceName, sampleRateHz, bitDepth) or null.
     * getCodecStatus() requires API 26 — gated with @RequiresApi.
     */
    @RequiresApi(Build.VERSION_CODES.O)
    private fun queryBluetoothCodecApi26(
        a2dp: BluetoothA2dp,
        device: BluetoothDevice,
        deviceName: String
    ): Quadruple<String, String, Int, Int> {
        val codecStatus = a2dp.getCodecStatus(device)
            ?: return Quadruple("SBC", deviceName, 44100, 16)
        val config: BluetoothCodecConfig = codecStatus.codecConfig

        val codecName = when (config.codecType) {
            BluetoothCodecConfig.SOURCE_CODEC_TYPE_SBC    -> "SBC"
            BluetoothCodecConfig.SOURCE_CODEC_TYPE_AAC    -> "AAC"
            BluetoothCodecConfig.SOURCE_CODEC_TYPE_APTX   -> "aptX"
            BluetoothCodecConfig.SOURCE_CODEC_TYPE_APTX_HD -> "aptX HD"
            BluetoothCodecConfig.SOURCE_CODEC_TYPE_LDAC   -> "LDAC"
            6 /* SOURCE_CODEC_TYPE_LC3 — API 33+ */       -> "LC3"
            7 /* SOURCE_CODEC_TYPE_OPUS */                -> "Opus"
            else                                          -> "SBC"
        }

        val sampleRate = when (config.sampleRate) {
            BluetoothCodecConfig.SAMPLE_RATE_44100  -> 44100
            BluetoothCodecConfig.SAMPLE_RATE_48000  -> 48000
            BluetoothCodecConfig.SAMPLE_RATE_88200  -> 88200
            BluetoothCodecConfig.SAMPLE_RATE_96000  -> 96000
            BluetoothCodecConfig.SAMPLE_RATE_176400 -> 176400
            BluetoothCodecConfig.SAMPLE_RATE_192000 -> 192000
            else                                    -> 44100
        }

        val bits = when (config.bitsPerSample) {
            BluetoothCodecConfig.BITS_PER_SAMPLE_16 -> 16
            BluetoothCodecConfig.BITS_PER_SAMPLE_24 -> 24
            BluetoothCodecConfig.BITS_PER_SAMPLE_32 -> 32
            else                                    -> 16
        }

        return Quadruple(codecName, deviceName, sampleRate, bits)
    }

    private fun queryBluetoothCodec(): Quadruple<String, String, Int, Int>? {
        if (!hasBtPermission()) return null
        val a2dp = bluetoothA2dp ?: return null

        return try {
            @Suppress("DEPRECATION")
            val connectedDevices: List<BluetoothDevice> = a2dp.connectedDevices
            if (connectedDevices.isEmpty()) return null

            val device = connectedDevices.first()
            @Suppress("DEPRECATION")
            val name = device.name ?: "Bluetooth Device"

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                queryBluetoothCodecApi26(a2dp, device, name)
            } else {
                // Pre-Oreo: codec info not available, return device name with SBC
                Quadruple("SBC", name, 44100, 16)
            }
        } catch (e: Exception) {
            Log.w(TAG, "queryBluetoothCodec error: ${e.message}")
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
}

/** Simple 4-tuple (Kotlin stdlib only has Triple). */
data class Quadruple<A, B, C, D>(val first: A, val second: B, val third: C, val fourth: D)
