package com.wambugu.sautiflow;

import android.app.PendingIntent;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.hardware.usb.UsbConstants;
import android.hardware.usb.UsbDevice;
import android.hardware.usb.UsbDeviceConnection;
import android.hardware.usb.UsbEndpoint;
import android.hardware.usb.UsbInterface;
import android.hardware.usb.UsbManager;
import android.os.Build;

import java.util.Map;

import io.flutter.embedding.engine.plugins.FlutterPlugin;

/**
 * SautiflowPlugin
 *
 * Ensures the native C++ engine library ('sautiflow' / 'audio_engine') is
 * loaded into the Android ART/JVM runtime via System.loadLibrary(), which
 * automatically invokes JNI_OnLoad and captures the JavaVM* pointer for
 * native AudioTrack, Direct Hi-Res, and libusb USB DAC playback backends.
 */
public class SautiflowPlugin implements FlutterPlugin {
    public static final String ACTION_USB_PERMISSION = "com.wambugu.sautiflow.USB_PERMISSION";

    private static final int USB_EVENT_PERMISSION = 1;
    private static final int USB_EVENT_ATTACHED = 2;
    private static final int USB_EVENT_DETACHED = 3;

    private static final int USB_SUBCLASS_AUDIOSTREAMING = 2;

    private static Context sAppContext = null;
    private static UsbDevice sActiveDevice = null;
    private static UsbDeviceConnection sActiveConnection = null;
    private static boolean sReceiverRegistered = false;
    private static int sAttachCount = 0;

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

    private static native void nativeOnUsbEvent(int eventType, int granted);

    private static final BroadcastReceiver sUsbReceiver = new BroadcastReceiver() {
        @Override
        public void onReceive(Context context, Intent intent) {
            if (intent == null || intent.getAction() == null) {
                return;
            }
            String action = intent.getAction();
            UsbDevice dev = getUsbDeviceFromIntent(intent);
            if (ACTION_USB_PERMISSION.equals(action)) {
                boolean granted = intent.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false);
                safeNotifyUsbEvent(USB_EVENT_PERMISSION, granted ? 1 : 0);
            } else if (UsbManager.ACTION_USB_DEVICE_ATTACHED.equals(action)) {
                if (dev != null && isUsbAudioPlaybackDevice(dev)) {
                    UsbManager mgr = getUsbManager(context);
                    boolean hasPerm = mgr != null && mgr.hasPermission(dev);
                    safeNotifyUsbEvent(USB_EVENT_ATTACHED, hasPerm ? 1 : 0);
                }
            } else if (UsbManager.ACTION_USB_DEVICE_DETACHED.equals(action)) {
                if (dev == null || isUsbAudioPlaybackDevice(dev) ||
                    (sActiveDevice != null && dev != null && dev.getDeviceId() == sActiveDevice.getDeviceId())) {
                    safeNotifyUsbEvent(USB_EVENT_DETACHED, 0);
                    closeUsbAudioDevice();
                }
            }
        }
    };

    private static void safeNotifyUsbEvent(int eventType, int granted) {
        try {
            nativeOnUsbEvent(eventType, granted);
        } catch (UnsatisfiedLinkError ignored) {
        } catch (Throwable ignored) {
        }
    }

    @SuppressWarnings("deprecation")
    private static UsbDevice getUsbDeviceFromIntent(Intent intent) {
        if (Build.VERSION.SDK_INT >= 33) {
            return intent.getParcelableExtra(UsbManager.EXTRA_DEVICE, UsbDevice.class);
        }
        return intent.getParcelableExtra(UsbManager.EXTRA_DEVICE);
    }

    @Override
    public void onAttachedToEngine(FlutterPluginBinding binding) {
        synchronized (SautiflowPlugin.class) {
            sAppContext = binding.getApplicationContext();
            sAttachCount++;
            ensureReceiverRegistered(sAppContext);
        }
    }

    @Override
    public void onDetachedFromEngine(FlutterPluginBinding binding) {
        synchronized (SautiflowPlugin.class) {
            if (sAttachCount > 0) {
                sAttachCount--;
            }
            if (sAttachCount == 0 && sReceiverRegistered && sAppContext != null) {
                try {
                    sAppContext.unregisterReceiver(sUsbReceiver);
                } catch (Throwable ignored) {
                }
                sReceiverRegistered = false;
            }
        }
    }

    private static void ensureReceiverRegistered(Context context) {
        if (sReceiverRegistered || context == null) {
            return;
        }
        IntentFilter filter = new IntentFilter();
        filter.addAction(ACTION_USB_PERMISSION);
        filter.addAction(UsbManager.ACTION_USB_DEVICE_ATTACHED);
        filter.addAction(UsbManager.ACTION_USB_DEVICE_DETACHED);
        try {
            if (Build.VERSION.SDK_INT >= 33) {
                context.registerReceiver(sUsbReceiver, filter, Context.RECEIVER_EXPORTED);
            } else {
                context.registerReceiver(sUsbReceiver, filter);
            }
            sReceiverRegistered = true;
        } catch (Throwable ignored) {
        }
    }

    private static Context resolveContext(Context context) {
        if (context != null) {
            return context.getApplicationContext() != null ? context.getApplicationContext() : context;
        }
        if (sAppContext != null) {
            return sAppContext;
        }
        try {
            Class<?> atClass = Class.forName("android.app.ActivityThread");
            Object app = atClass.getMethod("currentApplication").invoke(null);
            if (app instanceof Context) {
                sAppContext = (Context) app;
                return sAppContext;
            }
        } catch (Throwable ignored) {
        }
        return null;
    }

    private static UsbManager getUsbManager(Context context) {
        Context ctx = resolveContext(context);
        if (ctx == null) {
            return null;
        }
        ensureReceiverRegistered(ctx);
        Object svc = ctx.getSystemService(Context.USB_SERVICE);
        return (svc instanceof UsbManager) ? (UsbManager) svc : null;
    }

    private static boolean isUsbAudioPlaybackDevice(UsbDevice device) {
        if (device == null) {
            return false;
        }
        int ifCount = device.getInterfaceCount();
        for (int i = 0; i < ifCount; i++) {
            UsbInterface intf = device.getInterface(i);
            if (intf == null) {
                continue;
            }
            if (intf.getInterfaceClass() == UsbConstants.USB_CLASS_AUDIO &&
                intf.getInterfaceSubclass() == USB_SUBCLASS_AUDIOSTREAMING) {
                int epCount = intf.getEndpointCount();
                for (int e = 0; e < epCount; e++) {
                    UsbEndpoint ep = intf.getEndpoint(e);
                    if (ep != null &&
                        ep.getType() == UsbConstants.USB_ENDPOINT_XFER_ISOC &&
                        ep.getDirection() == UsbConstants.USB_DIR_OUT) {
                        return true;
                    }
                }
            }
        }
        return false;
    }

    private static UsbDevice findUsbAudioDac(UsbManager manager) {
        if (manager == null) {
            return null;
        }
        Map<String, UsbDevice> devices = manager.getDeviceList();
        if (devices == null || devices.isEmpty()) {
            return null;
        }
        for (UsbDevice dev : devices.values()) {
            if (isUsbAudioPlaybackDevice(dev)) {
                return dev;
            }
        }
        return null;
    }

    public static boolean hasUsbAudioDevice(Context context) {
        UsbManager manager = getUsbManager(context);
        return findUsbAudioDac(manager) != null;
    }

    /**
     * Checks or requests Android USB permission for the first connected USB Audio DAC.
     *
     * @return 1 if permission is already granted,
     *         0 if a permission prompt was dispatched asynchronously,
     *        -1 if no compatible USB Audio DAC is connected or UsbManager is unavailable.
     */
    public static int requestUsbAudioPermission(Context context) {
        Context ctx = resolveContext(context);
        UsbManager manager = getUsbManager(ctx);
        UsbDevice dac = findUsbAudioDac(manager);
        if (ctx == null || manager == null || dac == null) {
            return -1;
        }
        if (manager.hasPermission(dac)) {
            return 1;
        }

        Intent permIntent = new Intent(ACTION_USB_PERMISSION);
        permIntent.setPackage(ctx.getPackageName());
        int flags = PendingIntent.FLAG_UPDATE_CURRENT;
        if (Build.VERSION.SDK_INT >= 31) {
            flags |= PendingIntent.FLAG_MUTABLE;
        }
        PendingIntent pi = PendingIntent.getBroadcast(ctx, 0, permIntent, flags);
        manager.requestPermission(dac, pi);
        return 0;
    }

    public static synchronized int openUsbAudioDeviceFd(Context context) {
        Context ctx = resolveContext(context);
        UsbManager manager = getUsbManager(ctx);
        UsbDevice dac = findUsbAudioDac(manager);
        if (manager == null || dac == null || !manager.hasPermission(dac)) {
            return -1;
        }

        if (sActiveConnection != null) {
            try {
                sActiveConnection.close();
            } catch (Throwable ignored) {
            }
            sActiveConnection = null;
            sActiveDevice = null;
        }

        UsbDeviceConnection conn = manager.openDevice(dac);
        if (conn == null) {
            return -1;
        }

        int fd = conn.getFileDescriptor();
        if (fd < 0) {
            try {
                conn.close();
            } catch (Throwable ignored) {
            }
            return -1;
        }

        sActiveDevice = dac;
        sActiveConnection = conn;
        return fd;
    }

    public static synchronized byte[] getActiveUsbRawDescriptors() {
        if (sActiveConnection == null) {
            return null;
        }
        return sActiveConnection.getRawDescriptors();
    }

    public static synchronized String getActiveUsbProductName() {
        if (sActiveDevice == null) {
            return "USB Audio DAC";
        }
        String mfr = null;
        String prod = null;
        if (Build.VERSION.SDK_INT >= 21) {
            try {
                mfr = sActiveDevice.getManufacturerName();
                prod = sActiveDevice.getProductName();
            } catch (Throwable ignored) {
            }
        }
        String mfrClean = (mfr != null) ? mfr.trim() : "";
        String prodClean = (prod != null) ? prod.trim() : "";
        if (!mfrClean.isEmpty() && !prodClean.isEmpty()) {
            if (prodClean.startsWith(mfrClean)) {
                return prodClean;
            }
            return mfrClean + " " + prodClean;
        }
        if (!prodClean.isEmpty()) {
            return prodClean;
        }
        if (!mfrClean.isEmpty()) {
            return mfrClean;
        }
        return "USB Audio DAC";
    }

    public static synchronized void closeUsbAudioDevice() {
        if (sActiveConnection != null) {
            try {
                sActiveConnection.close();
            } catch (Throwable ignored) {
            }
            sActiveConnection = null;
        }
        sActiveDevice = null;
    }
}
