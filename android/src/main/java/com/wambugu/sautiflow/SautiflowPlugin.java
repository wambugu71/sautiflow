package com.wambugu.sautiflow;

import io.flutter.embedding.engine.plugins.FlutterPlugin;

/**
 * SautiflowPlugin
 *
 * Ensures the native C++ engine library ('sautiflow' / 'audio_engine') is
 * loaded into the Android ART/JVM runtime via System.loadLibrary(), which
 * automatically invokes JNI_OnLoad and captures the JavaVM* pointer for
 * native AudioTrack and Direct Hi-Res playback backends.
 */
public class SautiflowPlugin implements FlutterPlugin {
    static {
        try {
            System.loadLibrary("sautiflow");
        } catch (Throwable t1) {
            try {
                System.loadLibrary("audio_engine");
            } catch (Throwable t2) {
                // Fallback handled by direct FFI dlopen
            }
        }
    }

    @Override
    public void onAttachedToEngine(FlutterPluginBinding binding) {
    }

    @Override
    public void onDetachedFromEngine(FlutterPluginBinding binding) {
    }
}
