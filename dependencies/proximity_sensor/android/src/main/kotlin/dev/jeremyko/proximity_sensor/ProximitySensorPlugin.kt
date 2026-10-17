
package dev.jeremyko.proximity_sensor

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

////////////////////////////////////////////////////////////////////////////////////////////////////
class ProximitySensorPlugin: FlutterPlugin, MethodCallHandler  {
  private lateinit var methodChannel: MethodChannel
  private lateinit var eventChannel : EventChannel
  private lateinit var streamHandler : ProximityStreamHandler

  override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    methodChannel = MethodChannel(flutterPluginBinding.binaryMessenger, "proximity_sensor_enable")
    methodChannel.setMethodCallHandler(this)

    eventChannel = EventChannel(flutterPluginBinding.binaryMessenger, "proximity_sensor")
    streamHandler = ProximityStreamHandler( flutterPluginBinding.applicationContext)
    eventChannel.setStreamHandler(streamHandler)
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    eventChannel.setStreamHandler(null)
  }

  override fun onMethodCall(call: MethodCall, result: Result) {
    if (call.method == "enableProximityScreenOff") {
      val enabled: Boolean? = call.argument("enabled")
      if (enabled == null) {
        result.error("INVALID_ARGUMENTS", "'enabled' cannot be null", null)
      } else {
        streamHandler.setScreenOffEnabled(enabled)
        result.success(null);
      }
    } else if (call.method == "isProximitySensorAvailable") {
      result.success(streamHandler.isProximitySensorAvailable())
    } else {
      result.notImplemented()
    }
  }
}


