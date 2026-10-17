package dev.jeremyko.proximity_sensor

import android.annotation.SuppressLint
import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Build
import android.os.PowerManager
import io.flutter.plugin.common.EventChannel
import java.lang.UnsupportedOperationException

////////////////////////////////////////////////////////////////////////////////////////////////////
class ProximityStreamHandler(
        private val applicationContext: Context,
): EventChannel.StreamHandler, SensorEventListener {

    private var eventSink: EventChannel.EventSink? = null
    private lateinit var sensorManager: SensorManager
    private var proximitySensor: Sensor? = null

    private lateinit var powerManager: PowerManager
    private var wakeLock: PowerManager.WakeLock? = null
    private var enableScreenOff: Boolean = false

    @SuppressLint("WakelockTimeout")
    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
        initProximitySensor();
        if (proximitySensor == null) {
            throw UnsupportedOperationException("proximity sensor unavailable")
        }

        //sensor is available
        sensorManager.registerListener(this, proximitySensor, SensorManager.SENSOR_DELAY_NORMAL)
        powerManager = applicationContext.getSystemService(Context.POWER_SERVICE) as
            PowerManager

        if (enableScreenOff && Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            if (wakeLock == null) {
                wakeLock = powerManager.newWakeLock(PowerManager.PROXIMITY_SCREEN_OFF_WAKE_LOCK, 
                                                    "dev.jeremyko.proximity_sensor:lock")
            }
            if (!wakeLock!!.isHeld) {
                wakeLock!!.acquire()
            }
        }
    }

    fun isProximitySensorAvailable(): Boolean {
        if (proximitySensor != null) {
            return true
        }
        initProximitySensor()
        return proximitySensor != null
    }

    fun initProximitySensor() {
        sensorManager =  applicationContext.getSystemService(Context.SENSOR_SERVICE) as SensorManager

        if (proximitySensor == null) {
            proximitySensor = sensorManager.getDefaultSensor(Sensor.TYPE_PROXIMITY)
        }
    }

    override fun onCancel(arguments: Any?) {
        sensorManager.unregisterListener(this, proximitySensor)
        if (wakeLock != null && wakeLock!!.isHeld) {
            wakeLock!!.release()
        }
    }

    override fun onSensorChanged(event: SensorEvent?) {
        val distance = event ?.values?.get(0)?.toInt() //get distance
        if (distance != null) {
            if(distance > 0) {
                // distance > 0 , nothing is near
                eventSink ?.success(0)
            }else{
                // distance == 0, something is near
                eventSink ?.success(1)
            }
        }
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {
        //do nothing
    }

    fun setScreenOffEnabled(enabled: Boolean) {
        enableScreenOff = enabled;
        if (!enabled && wakeLock != null && wakeLock!!.isHeld) {
            wakeLock!!.release()
        }
    }
}
