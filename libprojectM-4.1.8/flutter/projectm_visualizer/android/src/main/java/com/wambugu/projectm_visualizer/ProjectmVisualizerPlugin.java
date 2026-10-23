package com.wambugu.projectm_visualizer;

import android.view.Surface;
import androidx.annotation.NonNull;
import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;
import io.flutter.view.TextureRegistry;
import java.util.HashMap;
import java.util.Map;

/**
 * Flutter Android Plugin providing zero-copy hardware surface rendering
 * for projectM Milkdrop visualizations.
 */
public class ProjectmVisualizerPlugin implements FlutterPlugin, MethodCallHandler {
    private MethodChannel channel;
    private TextureRegistry textureRegistry;
    private final Map<Long, TextureRegistry.SurfaceTextureEntry> textures = new HashMap<>();
    private final Map<Long, Surface> surfaces = new HashMap<>();

    static {
        try {
            System.loadLibrary("projectm_visualizer");
        } catch (UnsatisfiedLinkError e) {
            // May already be loaded via dart:ffi
        }
    }

    @Override
    public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
        channel = new MethodChannel(binding.getBinaryMessenger(), "com.wambugu.projectm_visualizer/texture");
        channel.setMethodCallHandler(this);
        textureRegistry = binding.getTextureRegistry();
    }

    @Override
    public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
        if (channel != null) {
            channel.setMethodCallHandler(null);
            channel = null;
        }
        for (Long id : textures.keySet()) {
            TextureRegistry.SurfaceTextureEntry entry = textures.get(id);
            if (entry != null) {
                entry.release();
            }
            Surface surface = surfaces.get(id);
            if (surface != null) {
                surface.release();
            }
        }
        textures.clear();
        surfaces.clear();
        textureRegistry = null;
    }

    @Override
    public void onMethodCall(@NonNull MethodCall call, @NonNull Result result) {
        if ("createTexture".equals(call.method)) {
            Number handleNum = call.argument("handle");
            Number widthNum = call.argument("width");
            Number heightNum = call.argument("height");
            if (handleNum == null || textureRegistry == null) {
                result.error("INVALID_ARGS", "Missing visualizer handle or TextureRegistry", null);
                return;
            }
            long handle = handleNum.longValue();
            int width = widthNum != null ? widthNum.intValue() : 960;
            int height = heightNum != null ? heightNum.intValue() : 540;

            TextureRegistry.SurfaceTextureEntry entry = textureRegistry.createSurfaceTexture();
            entry.surfaceTexture().setDefaultBufferSize(width, height);
            Surface surface = new Surface(entry.surfaceTexture());
            long textureId = entry.id();

            textures.put(textureId, entry);
            surfaces.put(textureId, surface);

            nativeAttachSurface(handle, surface, width, height);
            result.success(textureId);
        } else if ("destroyTexture".equals(call.method)) {
            Number handleNum = call.argument("handle");
            Number textureIdNum = call.argument("textureId");
            if (handleNum != null) {
                nativeDetachSurface(handleNum.longValue());
            }
            if (textureIdNum != null) {
                long textureId = textureIdNum.longValue();
                TextureRegistry.SurfaceTextureEntry entry = textures.remove(textureId);
                if (entry != null) {
                    entry.release();
                }
                Surface surface = surfaces.remove(textureId);
                if (surface != null) {
                    surface.release();
                }
            }
            result.success(null);
        } else if ("updateTextureSize".equals(call.method)) {
            Number textureIdNum = call.argument("textureId");
            Number widthNum = call.argument("width");
            Number heightNum = call.argument("height");
            if (textureIdNum != null && widthNum != null && heightNum != null) {
                long textureId = textureIdNum.longValue();
                TextureRegistry.SurfaceTextureEntry entry = textures.get(textureId);
                if (entry != null) {
                    try {
                        entry.surfaceTexture().setDefaultBufferSize(widthNum.intValue(), heightNum.intValue());
                    } catch (Exception ignored) {
                    }
                }
            }
            result.success(null);
        } else {
            result.notImplemented();
        }
    }

    private static native void nativeAttachSurface(long handle, Surface surface, int width, int height);
    private static native void nativeDetachSurface(long handle);
}
