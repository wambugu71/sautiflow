import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' as foundation;
import 'dart:io' show Platform;

////////////////////////////////////////////////////////////////////////////////
class ProximitySensor {
  static EventChannel _streamChannel = EventChannel('proximity_sensor');
  static MethodChannel _methodChannel =
      MethodChannel('proximity_sensor_enable');

  // for ios and android only
  static Stream<int> get events {
    if (!foundation.kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      return _streamChannel.receiveBroadcastStream().map((event) {
        return event;
      });
    } else {
      return Stream.periodic(Duration(hours: 1), (x) => 0); // fake stream...
    }
  }

  // for android only
  static Future<void> setProximityScreenOff(bool enabled) async {
    if (!foundation.kIsWeb && Platform.isAndroid) {
      await _methodChannel
          .invokeMethod<void>('enableProximityScreenOff', <String, dynamic>{
        'enabled': enabled,
      });
    }
  }

  static Future<bool> isProximitySensorAvailable() async {
    return await _methodChannel
            .invokeMethod<bool>('isProximitySensorAvailable') ??
        false;
  }
}
