import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' as foundation;
import 'dart:async';
import 'package:proximity_sensor/proximity_sensor.dart';

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  // ignore: library_private_types_in_public_api
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  bool _isNear = false;
  late StreamSubscription<dynamic> _streamSubscription;

  @override
  void initState() {
    super.initState();
    listenSensor();
  }

  @override
  void dispose() {
    super.dispose();
    _streamSubscription.cancel();
  }

  Future<void> listenSensor() async {
    FlutterError.onError = (FlutterErrorDetails details) {
      if (foundation.kDebugMode) {
        FlutterError.dumpErrorToConsole(details);
      }
    };

    // -------------------------------------------------- <ANDROID ONLY>
    // NOTE: The following calls only work on Android. Otherwise, nothing happens.
    // You only need to make this call if you want to turn off the screen.
    // Add below permission in your AndroidManifest.xml file.
    //     <uses-permission android:name="android.permission.WAKE_LOCK"/>
    await ProximitySensor.setProximityScreenOff(true)
        .onError((error, stackTrace) {
      if (foundation.kDebugMode) {
        debugPrint("could not enable screen off functionality");
      }
      return null;
    });
    // -------------------------------------------------- <ANDROID ONLY>

    _streamSubscription = ProximitySensor.events.listen((int event) {
      setState(() {
        if (foundation.kDebugMode) {
          debugPrint("sensor event = $event");
        }
        _isNear = (event > 0) ? true : false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Proximity Sensor Example'),
        ),
        body: Center(
          child: Text('proximity sensor, is near ?  $_isNear\n'),
        ),
      ),
    );
  }
}

////////////////////////////////////////////////////////////////////////////////
void main() {
  runApp(MyApp());
}
