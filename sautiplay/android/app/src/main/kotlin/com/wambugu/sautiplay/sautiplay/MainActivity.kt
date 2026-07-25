package com.wambugu.sautiplay.sautiplay

import android.content.Context
import android.media.AudioDeviceInfo
import android.media.AudioFormat
import android.media.AudioManager
import android.os.Build
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {

    companion object {
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

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.wambugu.sautiflow/hardware").setMethodCallHandler { call, result ->
            if (call.method == "getHardwareAudioSpecs") {
                try {
                    val audioManager = applicationContext.getSystemService(Context.AUDIO_SERVICE) as AudioManager
                    val sampleRateStr = audioManager.getProperty(AudioManager.PROPERTY_OUTPUT_SAMPLE_RATE)
                    val bufferSizeStr = audioManager.getProperty(AudioManager.PROPERTY_OUTPUT_FRAMES_PER_BUFFER)

                    val sampleRate = sampleRateStr?.toIntOrNull() ?: 48000
                    val periodFrames = bufferSizeStr?.toIntOrNull() ?: 192

                    var deviceName = "Default Output Device"
                    var bitDepth = 32
                    var isFloat = true
                    var deviceType = "Speakers / Output Device"

                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        val devices = audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
                        var selectedPriority = -1
                        var selectedDevice: AudioDeviceInfo? = null

                        for (dev in devices) {
                            val type = dev.type
                            var priority = 1
                            if (type == AudioDeviceInfo.TYPE_USB_DEVICE || type == AudioDeviceInfo.TYPE_USB_HEADSET) priority = 4
                            else if (type == AudioDeviceInfo.TYPE_BLUETOOTH_A2DP || (Build.VERSION.SDK_INT >= 31 && type == AudioDeviceInfo.TYPE_BLUETOOTH_LE)) priority = 3
                            else if (type == AudioDeviceInfo.TYPE_WIRED_HEADSET || type == AudioDeviceInfo.TYPE_WIRED_HEADPHONES) priority = 2

                            if (priority > selectedPriority) {
                                selectedPriority = priority
                                selectedDevice = dev
                            }
                        }

                        selectedDevice?.let { dev ->
                            val name = dev.productName?.toString()
                            if (!name.isNullOrEmpty()) {
                                deviceName = name
                            }
                            val devType = dev.type
                            if (devType == AudioDeviceInfo.TYPE_USB_DEVICE || devType == AudioDeviceInfo.TYPE_USB_HEADSET) {
                                deviceType = "USB DAC"
                            } else if (devType == AudioDeviceInfo.TYPE_BLUETOOTH_A2DP || (Build.VERSION.SDK_INT >= 31 && devType == AudioDeviceInfo.TYPE_BLUETOOTH_LE)) {
                                deviceType = "Bluetooth Wireless"
                            } else if (devType == AudioDeviceInfo.TYPE_WIRED_HEADSET || devType == AudioDeviceInfo.TYPE_WIRED_HEADPHONES) {
                                deviceType = "3.5mm Headphone Jack"
                            }

                            val encodings = dev.encodings
                            var maxBits = 16
                            var floatFmt = false
                            for (enc in encodings) {
                                if (enc == AudioFormat.ENCODING_PCM_FLOAT) {
                                    floatFmt = true
                                    if (32 > maxBits) maxBits = 32
                                } else if (Build.VERSION.SDK_INT >= 31 && enc == AudioFormat.ENCODING_PCM_24BIT_PACKED) {
                                    if (24 > maxBits) maxBits = 24
                                } else if (Build.VERSION.SDK_INT >= 31 && enc == AudioFormat.ENCODING_PCM_32BIT) {
                                    if (32 > maxBits) maxBits = 32
                                } else if (enc == AudioFormat.ENCODING_PCM_16BIT) {
                                    if (16 > maxBits) maxBits = 16
                                }
                            }
                            if (maxBits > 0) bitDepth = maxBits
                            isFloat = floatFmt
                        }
                    }

                    val latencyMs = (periodFrames.toDouble() * 2.0 / sampleRate.toDouble()) * 1000.0

                    val resultMap = mapOf(
                        "deviceName" to deviceName,
                        "sampleRate" to sampleRate,
                        "bitDepth" to bitDepth,
                        "isFloat" to isFloat,
                        "channels" to 2,
                        "periodSizeFrames" to periodFrames,
                        "periodCount" to 2,
                        "latencyMs" to latencyMs,
                        "deviceType" to deviceType
                    )
                    result.success(resultMap)
                } catch (e: Exception) {
                    result.error("ERROR", e.message, null)
                }
            } else {
                result.notImplemented()
            }
        }
    }
}
