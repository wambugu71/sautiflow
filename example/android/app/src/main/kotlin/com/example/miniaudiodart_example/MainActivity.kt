package com.example.miniaudiodart_example

import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    companion object {
        init {
            try {
                System.loadLibrary("audio_engine")
            } catch (e: Throwable) {
                // System.loadLibrary triggers JNI_OnLoad in audio_engine.cpp
            }
        }
    }
}
