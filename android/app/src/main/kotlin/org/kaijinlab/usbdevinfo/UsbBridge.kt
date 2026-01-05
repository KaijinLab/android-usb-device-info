package org.kaijinlab.usbdevinfo

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.input.InputManager
import android.hardware.usb.UsbConfiguration
import android.hardware.usb.UsbConstants
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbDeviceConnection
import android.hardware.usb.UsbEndpoint
import android.hardware.usb.UsbInterface
import android.hardware.usb.UsbManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.InputDevice
import androidx.annotation.MainThread
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ConcurrentHashMap

class UsbBridge(
    private val activity: FlutterActivity,
    messenger: BinaryMessenger
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    private val tag = "USBDevInfo"
    private val ctx: Context = activity.applicationContext

    private val usbManager: UsbManager =
        ctx.getSystemService(Context.USB_SERVICE) as UsbManager

    private val inputManager: InputManager? =
        try { ctx.getSystemService(Context.INPUT_SERVICE) as InputManager } catch (_: Throwable) { null }

    private val mainHandler = Handler(Looper.getMainLooper())

    private val methodChannel = MethodChannel(messenger, "usbdevinfo/methods")
    private val eventChannel = EventChannel(messenger, "usbdevinfo/events")

    private var eventSink: EventChannel.EventSink? = null

    private val permissionResults = ConcurrentHashMap<String, MethodChannel.Result>()
    private val permissionAction = "${ctx.packageName}.USB_PERMISSION"

    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            when (intent.action) {
                UsbManager.ACTION_USB_DEVICE_ATTACHED,
                UsbManager.ACTION_USB_DEVICE_DETACHED -> {
                    val device: UsbDevice? =
                        intent.getParcelableExtraCompat(UsbManager.EXTRA_DEVICE, UsbDevice::class.java)

                    emitEvent(
                        mapOf(
                            "type" to "devices_changed",
                            "reason" to (intent.action ?: "unknown"),
                            "deviceName" to device?.deviceName
                        )
                    )
                }

                permissionAction -> {
                    val device: UsbDevice? =
                        intent.getParcelableExtraCompat(UsbManager.EXTRA_DEVICE, UsbDevice::class.java)

                    val granted = intent.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false)
                    val name = device?.deviceName

                    if (name != null) {
                        permissionResults.remove(name)?.success(granted)
                    }

                    emitEvent(
                        mapOf(
                            "type" to "permission_result",
                            "deviceName" to name,
                            "granted" to granted
                        )
                    )
                    // Permission change unlocks fields: refresh list.
                    emitEvent(
                        mapOf(
                            "type" to "devices_changed",
                            "reason" to "permission_result",
                            "deviceName" to name
                        )
                    )
                }
            }
        }
    }

    private val inputListener = object : InputManager.InputDeviceListener {
        override fun onInputDeviceAdded(deviceId: Int) {
            emitEvent(
                mapOf(
                    "type" to "devices_changed",
                    "reason" to "input_added",
                    "deviceName" to inputKey(deviceId)
                )
            )
        }

        override fun onInputDeviceRemoved(deviceId: Int) {
            emitEvent(
                mapOf(
                    "type" to "devices_changed",
                    "reason" to "input_removed",
                    "deviceName" to inputKey(deviceId)
                )
            )
        }

        override fun onInputDeviceChanged(deviceId: Int) {
            emitEvent(
                mapOf(
                    "type" to "devices_changed",
                    "reason" to "input_changed",
                    "deviceName" to inputKey(deviceId)
                )
            )
        }
    }

    fun start() {
        methodChannel.setMethodCallHandler(this)
        eventChannel.setStreamHandler(this)
        registerReceiver()
        registerInputListener()
    }

    fun stop() {
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        unregisterReceiver()
        unregisterInputListener()
    }

    fun handleIntent(intent: Intent?) {
        if (intent == null) return
        val action = intent.action ?: return

        if (action == UsbManager.ACTION_USB_DEVICE_ATTACHED || action == UsbManager.ACTION_USB_DEVICE_DETACHED) {
            val device: UsbDevice? =
                intent.getParcelableExtraCompat(UsbManager.EXTRA_DEVICE, UsbDevice::class.java)

            emitEvent(
                mapOf(
                    "type" to "devices_changed",
                    "reason" to "activity_intent:$action",
                    "deviceName" to device?.deviceName
                )
            )
        }
    }

    private fun registerReceiver() {
        val filter = IntentFilter().apply {
            addAction(UsbManager.ACTION_USB_DEVICE_ATTACHED)
            addAction(UsbManager.ACTION_USB_DEVICE_DETACHED)
            addAction(permissionAction)
        }

        if (Build.VERSION.SDK_INT >= 33) {
            ctx.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("DEPRECATION")
            ctx.registerReceiver(receiver, filter)
        }
    }

    private fun unregisterReceiver() {
        try {
            ctx.unregisterReceiver(receiver)
        } catch (_: Throwable) {
            // ignore
        }
    }

    private fun registerInputListener() {
        try {
            inputManager?.registerInputDeviceListener(inputListener, mainHandler)
        } catch (t: Throwable) {
            Log.w(tag, "InputManager listener not available: ${t.message}")
        }
    }

    private fun unregisterInputListener() {
        try {
            inputManager?.unregisterInputDeviceListener(inputListener)
        } catch (_: Throwable) {
            // ignore
        }
    }

    @MainThread
    private fun emitEvent(event: Map<String, Any?>) {
        eventSink?.success(event)
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
        emitEvent(mapOf("type" to "ready"))
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "listDevices" -> result.success(listDevices())

                "requestPermission" -> {
                    val deviceName = call.argument<String>("deviceName") ?: ""
                    requestPermission(deviceName, result)
                }

                "getDeviceDetails" -> {
                    val deviceName = call.argument<String>("deviceName") ?: ""
                    result.success(getDeviceDetails(deviceName))
                }

                else -> result.notImplemented()
            }
        } catch (se: SecurityException) {
            result.error("security_exception", se.message, null)
        } catch (t: Throwable) {
            Log.e(tag, "Method failed: ${call.method}", t)
            result.error("error", t.message, null)
        }
    }

    /* ------------------------- */
    /* Device enumeration */
    /* ------------------------- */

    private fun listDevices(): List<Map<String, Any?>> {
        val usb = usbManager.deviceList.values.toList()
        val out = ArrayList<Map<String, Any?>>(usb.size + 8)

        // De-dupe input devices by VID:PID when UsbManager already shows them.
        val usbVidPid = HashSet<String>(usb.size * 2)
        for (d in usb) {
            usbVidPid.add("${d.vendorId}:${d.productId}")
            out.add(deviceSummaryUsb(d))
        }

        out.addAll(listExternalInputDevices(usbVidPid))
        return out
    }

    private fun listExternalInputDevices(usbVidPid: Set<String>): List<Map<String, Any?>> {
        val im = inputManager ?: return emptyList()
        val ids = getInputDeviceIdsCompat(im) ?: return emptyList()

        val out = ArrayList<Map<String, Any?>>()
        for (id in ids) {
            val dev = safeGet { im.getInputDevice(id) } ?: continue

            // Prefer *external* devices (usually USB OTG)
            val isExternal = inputIsExternal(dev)
            if (!isExternal) continue

            val sourcesMask = dev.sources
            val isKb = (sourcesMask and InputDevice.SOURCE_KEYBOARD) == InputDevice.SOURCE_KEYBOARD
            val isMouse = (sourcesMask and InputDevice.SOURCE_MOUSE) == InputDevice.SOURCE_MOUSE
            if (!isKb && !isMouse) continue

            val vid = inputVendorId(dev)
            val pid = inputProductId(dev)
            if (vid <= 0 || pid <= 0) continue

            // If UsbManager already listed same VID:PID, prefer the real UsbDevice entry.
            if (usbVidPid.contains("$vid:$pid")) continue

            out.add(deviceSummaryInput(dev, vid, pid))
        }

        return out
    }

    private fun requestPermission(deviceName: String, result: MethodChannel.Result) {
        if (isInputKey(deviceName)) {
            // InputDevices do not use UsbManager permission model.
            result.success(true)
            return
        }

        val device = findUsbByName(deviceName)
        if (device == null) {
            result.success(false)
            return
        }

        if (usbManager.hasPermission(device)) {
            result.success(true)
            return
        }

        // Only one pending permission request per device name.
        permissionResults[deviceName] = result

        val baseFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) PendingIntent.FLAG_MUTABLE else 0
        val flags = baseFlags or PendingIntent.FLAG_UPDATE_CURRENT

        val intent = Intent(permissionAction).setPackage(ctx.packageName)
        val pending = PendingIntent.getBroadcast(ctx, deviceName.hashCode(), intent, flags)
        usbManager.requestPermission(device, pending)
    }

    private fun getDeviceDetails(deviceName: String): Map<String, Any?> {
        if (isInputKey(deviceName)) {
            val id = parseInputId(deviceName)
            val dev = if (id == null) null else safeGet { inputManager?.getInputDevice(id) }
            if (dev == null) {
                return mapOf(
                    "summary" to mapOf(
                        "deviceName" to deviceName,
                        "vendorId" to 0,
                        "productId" to 0,
                        "deviceClass" to UsbConstants.USB_CLASS_HID,
                        "deviceSubclass" to 0,
                        "deviceProtocol" to 0,
                        "interfaceCount" to 0,
                        "configurationCount" to 0,
                        "hasPermission" to true,
                        "isInputDevice" to true
                    ),
                    "interfaces" to emptyList<Map<String, Any?>>(),
                    "configurations" to emptyList<Map<String, Any?>>(),
                    "deviceDescriptor" to null,
                    "input" to null
                )
            }

            val vid = inputVendorId(dev)
            val pid = inputProductId(dev)

            return mapOf(
                "summary" to deviceSummaryInput(dev, vid, pid),
                "interfaces" to emptyList<Map<String, Any?>>(),
                "configurations" to emptyList<Map<String, Any?>>(),
                "deviceDescriptor" to null,
                "input" to buildInputDetails(dev, vid, pid)
            )
        }

        val device = findUsbByName(deviceName)
            ?: return mapOf(
                "summary" to mapOf(
                    "deviceName" to deviceName,
                    "vendorId" to 0,
                    "productId" to 0,
                    "deviceClass" to 0,
                    "deviceSubclass" to 0,
                    "deviceProtocol" to 0,
                    "interfaceCount" to 0,
                    "configurationCount" to 0,
                    "hasPermission" to false,
                    "isInputDevice" to false
                ),
                "interfaces" to emptyList<Map<String, Any?>>(),
                "configurations" to emptyList<Map<String, Any?>>(),
                "deviceDescriptor" to null,
                "input" to null
            )

        val summary = deviceSummaryUsb(device)
        val interfaces = buildInterfaces(device)
        val configurations = buildConfigurations(device)
        val deviceDescriptor = readDeviceDescriptor(device)

        return mapOf(
            "summary" to summary,
            "interfaces" to interfaces,
            "configurations" to configurations,
            "deviceDescriptor" to deviceDescriptor,
            "input" to null
        )
    }

    /* ------------------------- */
    /* Summaries */
    /* ------------------------- */

    private fun deviceSummaryUsb(device: UsbDevice): Map<String, Any?> {
        val hasPerm = usbManager.hasPermission(device)

        var manufacturer: String? = null
        var product: String? = null
        var serial: String? = null
        if (hasPerm) {
            manufacturer = safeGet { device.manufacturerName }
            product = safeGet { device.productName }
            serial = safeReadSerial(device)
        }

        val usbVersionStr = readUsbVersion(device)
        val speedStr = readSpeed(device)
        val maxPower = readMaxPowerMa(device)
        val portNumber = readPortNumber(device)

        return mapOf(
            "deviceName" to device.deviceName,
            "deviceId" to device.deviceId,
            "portNumber" to portNumber,
            "vendorId" to device.vendorId,
            "productId" to device.productId,
            "deviceClass" to device.deviceClass,
            "deviceSubclass" to device.deviceSubclass,
            "deviceProtocol" to device.deviceProtocol,
            "interfaceCount" to device.interfaceCount,
            "configurationCount" to device.configurationCount,
            "hasPermission" to hasPerm,
            "manufacturerName" to manufacturer,
            "productName" to product,
            "serialNumber" to serial,
            "usbVersion" to usbVersionStr,
            "speed" to speedStr,
            "maxPowerMa" to maxPower,
            "isInputDevice" to false
        )
    }

    private fun deviceSummaryInput(dev: InputDevice, vid: Int, pid: Int): Map<String, Any?> {
        val sources = inputSources(dev)
        val name = safeGet { dev.name } ?: "Input device"

        return mapOf(
            "deviceName" to inputKey(dev.id),
            "deviceId" to dev.id,
            "portNumber" to null,
            "vendorId" to vid,
            "productId" to pid,
            "deviceClass" to UsbConstants.USB_CLASS_HID,
            "deviceSubclass" to 0,
            "deviceProtocol" to 0,
            "interfaceCount" to 0,
            "configurationCount" to 0,
            "hasPermission" to true,
            "manufacturerName" to null,
            "productName" to name,
            "serialNumber" to null,
            "usbVersion" to null,
            "speed" to null,
            "maxPowerMa" to null,
            "isInputDevice" to true,
            "inputSources" to sources
        )
    }

    /* ------------------------- */
    /* Interfaces / endpoints */
    /* ------------------------- */

    private fun buildInterfaces(device: UsbDevice): List<Map<String, Any?>> {
        val out = ArrayList<Map<String, Any?>>(device.interfaceCount)
        for (i in 0 until device.interfaceCount) {
            val intf = device.getInterface(i)
            out.add(interfaceToMap(intf))
        }
        return out
    }

    private fun buildConfigurations(device: UsbDevice): List<Map<String, Any?>> {
        val out = ArrayList<Map<String, Any?>>()
        val count = device.configurationCount
        if (count <= 0) return out

        for (c in 0 until count) {
            val cfg = device.getConfiguration(c)
            val ifaces = ArrayList<Map<String, Any?>>(cfg.interfaceCount)
            for (i in 0 until cfg.interfaceCount) {
                ifaces.add(interfaceToMap(cfg.getInterface(i)))
            }

            out.add(
                mapOf(
                    "id" to cfg.id,
                    "name" to safeGet { cfg.name },
                    "attributes" to getUsbConfigurationAttributes(cfg),
                    "maxPowerMa" to cfg.maxPower,
                    "interfaceCount" to cfg.interfaceCount,
                    "interfaces" to ifaces
                )
            )
        }
        return out
    }

    private fun interfaceToMap(intf: UsbInterface): Map<String, Any?> {
        val endpoints = ArrayList<Map<String, Any?>>(intf.endpointCount)
        for (i in 0 until intf.endpointCount) {
            val ep = intf.getEndpoint(i)
            endpoints.add(endpointToMap(ep))
        }

        return mapOf(
            "id" to intf.id,
            "alternateSetting" to getUsbInterfaceAlternateSetting(intf),
            "name" to safeGet { intf.name },
            "interfaceClass" to intf.interfaceClass,
            "interfaceSubclass" to intf.interfaceSubclass,
            "interfaceProtocol" to intf.interfaceProtocol,
            "endpointCount" to intf.endpointCount,
            "endpoints" to endpoints
        )
    }

    private fun endpointToMap(ep: UsbEndpoint): Map<String, Any?> {
        return mapOf(
            "address" to ep.address,
            "direction" to directionLabel(ep.direction),
            "type" to endpointTypeLabel(ep.type),
            "maxPacketSize" to ep.maxPacketSize,
            "interval" to ep.interval,
            "attributes" to getUsbEndpointAttributes(ep),
            "number" to ep.endpointNumber
        )
    }

    private fun directionLabel(direction: Int): String = when (direction) {
        UsbConstants.USB_DIR_IN -> "IN"
        UsbConstants.USB_DIR_OUT -> "OUT"
        else -> "Unknown"
    }

    private fun endpointTypeLabel(type: Int): String = when (type) {
        UsbConstants.USB_ENDPOINT_XFER_CONTROL -> "Control"
        UsbConstants.USB_ENDPOINT_XFER_ISOC -> "Isochronous"
        UsbConstants.USB_ENDPOINT_XFER_BULK -> "Bulk"
        UsbConstants.USB_ENDPOINT_XFER_INT -> "Interrupt"
        else -> "Unknown"
    }

    /* ------------------------- */
    /* Input device details */
    /* ------------------------- */

    private fun buildInputDetails(dev: InputDevice, vid: Int, pid: Int): Map<String, Any?> {
        val ranges = ArrayList<Map<String, Any?>>()
        val motionRanges: List<Any> = inputMotionRanges(dev)

        for (r in motionRanges) {
            // MotionRange is hidden behind reflection for compatibility.
            val axis = callInt(r, "getAxis") ?: 0
            val min = callFloat(r, "getMin") ?: 0f
            val max = callFloat(r, "getMax") ?: 0f
            val flat = callFloat(r, "getFlat") ?: 0f
            val fuzz = callFloat(r, "getFuzz") ?: 0f
            val res = callFloat(r, "getResolution") ?: 0f

            ranges.add(
                mapOf(
                    "axis" to axis,
                    "min" to min.toDouble(),
                    "max" to max.toDouble(),
                    "flat" to flat.toDouble(),
                    "fuzz" to fuzz.toDouble(),
                    "resolution" to res.toDouble()
                )
            )
        }

        return mapOf(
            "id" to dev.id,
            "name" to safeGet { dev.name },
            "descriptor" to inputDescriptor(dev),
            "isExternal" to inputIsExternal(dev),
            "vendorId" to vid,
            "productId" to pid,
            "sources" to inputSources(dev),
            "keyboardType" to inputKeyboardType(dev),
            "motionRanges" to ranges
        )
    }

    private fun inputSources(dev: InputDevice): List<String> {
        val s = dev.sources
        val out = ArrayList<String>(4)

        if ((s and InputDevice.SOURCE_KEYBOARD) == InputDevice.SOURCE_KEYBOARD) out.add("keyboard")
        if ((s and InputDevice.SOURCE_MOUSE) == InputDevice.SOURCE_MOUSE) out.add("mouse")
        if ((s and InputDevice.SOURCE_TOUCHPAD) == InputDevice.SOURCE_TOUCHPAD) out.add("touchpad")
        if ((s and InputDevice.SOURCE_JOYSTICK) == InputDevice.SOURCE_JOYSTICK) out.add("joystick")

        if (out.isEmpty()) out.add("unknown")
        return out
    }

    /* ------------------------- */
    /* Helpers: find / IDs */
    /* ------------------------- */

    private fun findUsbByName(deviceName: String): UsbDevice? {
        val map = usbManager.deviceList
        for (d in map.values) {
            if (d.deviceName == deviceName) return d
        }
        return null
    }

    private fun safeReadSerial(device: UsbDevice): String? {
        return try {
            val conn: UsbDeviceConnection? = usbManager.openDevice(device)
            val s = safeGet { conn?.serial }
            conn?.close()
            s ?: safeGet { device.serialNumber }
        } catch (_: Throwable) {
            null
        }
    }

    private fun readUsbVersion(device: UsbDevice): String? {
        // Prefer parsed device descriptor (bcdUSB) when available
        val fromRaw = readDeviceDescriptor(device)?.get("usbVersion") as? String
        if (!fromRaw.isNullOrBlank()) return fromRaw

        // Fallback: try UsbDevice.getVersion() (string) via reflection
        return try {
            val m = UsbDevice::class.java.getMethod("getVersion")
            (m.invoke(device) as? String)?.trim()
        } catch (_: Throwable) {
            null
        }
    }

    private fun readSpeed(device: UsbDevice): String? {
        return try {
            val m = UsbDevice::class.java.getMethod("getSpeed")
            val speed = (m.invoke(device) as? Int) ?: return null
            when (speed) {
                1 -> "Low speed (1.5 Mbps)"
                2 -> "Full speed (12 Mbps)"
                3 -> "High speed (480 Mbps)"
                4 -> "SuperSpeed (5 Gbps)"
                5 -> "SuperSpeed+ (10+ Gbps)"
                else -> "Unknown"
            }
        } catch (_: Throwable) {
            null
        }
    }

    private fun readMaxPowerMa(device: UsbDevice): Int? {
        return try {
            if (device.configurationCount <= 0) return null
            val cfg: UsbConfiguration = device.getConfiguration(0)
            cfg.maxPower
        } catch (_: Throwable) {
            null
        }
    }

    private fun readPortNumber(device: UsbDevice): Int? {
        return try {
            val m = UsbDevice::class.java.getMethod("getPortNumber")
            (m.invoke(device) as? Int)
        } catch (_: Throwable) {
            null
        }
    }

    private fun readDeviceDescriptor(device: UsbDevice): Map<String, Any?>? {
        if (!usbManager.hasPermission(device)) return null

        return try {
            val conn = usbManager.openDevice(device) ?: return null
            val raw = tryGetRawDescriptors(conn)
            conn.close()

            if (raw == null || raw.size < 18) return null

            val bcdUsb = le16(raw[2], raw[3])
            val bcdDevice = le16(raw[12], raw[13])
            val maxPkt0 = u8(raw[7])
            val numCfg = u8(raw[17])
            val iMan = u8(raw[14])
            val iProd = u8(raw[15])
            val iSer = u8(raw[16])

            mapOf(
                "bcdUsb" to bcdUsb,
                "usbVersion" to bcdToVersionString(bcdUsb),
                "bcdDevice" to bcdDevice,
                "deviceRelease" to bcdToVersionString(bcdDevice),
                "maxPacketSize0" to maxPkt0,
                "numConfigurations" to numCfg,
                "iManufacturer" to iMan,
                "iProduct" to iProd,
                "iSerialNumber" to iSer
            )
        } catch (_: Throwable) {
            null
        }
    }

    private fun tryGetRawDescriptors(conn: UsbDeviceConnection): ByteArray? {
        return try {
            val m = UsbDeviceConnection::class.java.getMethod("getRawDescriptors")
            @Suppress("UNCHECKED_CAST")
            m.invoke(conn) as? ByteArray
        } catch (_: Throwable) {
            null
        }
    }

    private fun u8(b: Byte): Int = b.toInt() and 0xFF
    private fun le16(lo: Byte, hi: Byte): Int = u8(lo) or (u8(hi) shl 8)

    private fun bcdToVersionString(bcd: Int): String {
        // bcd like 0x0200 => 2.00, 0x0310 => 3.10
        val major = (bcd ushr 8) and 0xFF
        val minorTens = (bcd ushr 4) and 0x0F
        val minorOnes = bcd and 0x0F
        val minor = minorTens * 10 + minorOnes
        return String.format("%d.%02d", major, minor)
    }

    /* ------------------------- */
    /* Reflection-safe accessors */
    /* ------------------------- */

    private fun getUsbEndpointAttributes(ep: UsbEndpoint): Int {
        return try {
            val m = UsbEndpoint::class.java.getMethod("getAttributes")
            (m.invoke(ep) as? Int) ?: 0
        } catch (_: Throwable) {
            0
        }
    }

    private fun getUsbConfigurationAttributes(cfg: UsbConfiguration): Int {
        return try {
            val m = UsbConfiguration::class.java.getMethod("getAttributes")
            (m.invoke(cfg) as? Int) ?: 0
        } catch (_: Throwable) {
            0
        }
    }

    private fun getUsbInterfaceAlternateSetting(intf: UsbInterface): Int {
        return try {
            val m = UsbInterface::class.java.getMethod("getAlternateSetting")
            (m.invoke(intf) as? Int) ?: 0
        } catch (_: Throwable) {
            0
        }
    }

    private fun getInputDeviceIdsCompat(im: InputManager): IntArray? {
        return try {
            val m = InputManager::class.java.getMethod("getInputDeviceIds")
            m.invoke(im) as? IntArray
        } catch (_: Throwable) {
            null
        }
    }

    private fun inputIsExternal(dev: InputDevice): Boolean {
        return try {
            val m = InputDevice::class.java.getMethod("isExternal")
            (m.invoke(dev) as? Boolean) ?: false
        } catch (_: Throwable) {
            // Some builds expose it as a field-like getter; try property fallback.
            safeGet { dev.isExternal } ?: false
        }
    }

    private fun inputVendorId(dev: InputDevice): Int {
        return try {
            val m = InputDevice::class.java.getMethod("getVendorId")
            (m.invoke(dev) as? Int) ?: 0
        } catch (_: Throwable) {
            0
        }
    }

    private fun inputProductId(dev: InputDevice): Int {
        return try {
            val m = InputDevice::class.java.getMethod("getProductId")
            (m.invoke(dev) as? Int) ?: 0
        } catch (_: Throwable) {
            0
        }
    }

    private fun inputDescriptor(dev: InputDevice): String? {
        return try {
            val m = InputDevice::class.java.getMethod("getDescriptor")
            (m.invoke(dev) as? String)
        } catch (_: Throwable) {
            null
        }
    }

    private fun inputKeyboardType(dev: InputDevice): Int {
        return try {
            val m = InputDevice::class.java.getMethod("getKeyboardType")
            (m.invoke(dev) as? Int) ?: 0
        } catch (_: Throwable) {
            0
        }
    }

    private fun inputMotionRanges(dev: InputDevice): List<Any> {
        return try {
            val m = InputDevice::class.java.getMethod("getMotionRanges")
            @Suppress("UNCHECKED_CAST")
            (m.invoke(dev) as? List<Any>) ?: emptyList()
        } catch (_: Throwable) {
            emptyList()
        }
    }

    private fun callInt(target: Any, method: String): Int? {
        return try {
            val m = target::class.java.getMethod(method)
            (m.invoke(target) as? Int)
        } catch (_: Throwable) {
            null
        }
    }

    private fun callFloat(target: Any, method: String): Float? {
        return try {
            val m = target::class.java.getMethod(method)
            (m.invoke(target) as? Float)
        } catch (_: Throwable) {
            null
        }
    }

    /* ------------------------- */
    /* Input key helpers */
    /* ------------------------- */

    private fun isInputKey(name: String): Boolean = name.startsWith("input:")
    private fun inputKey(id: Int): String = "input:$id"
    private fun parseInputId(name: String): Int? {
        if (!isInputKey(name)) return null
        return name.removePrefix("input:").toIntOrNull()
    }

    private fun <T> safeGet(block: () -> T): T? {
        return try { block() } catch (_: Throwable) { null }
    }

    @Suppress("DEPRECATION")
    private fun <T> Intent.getParcelableExtraCompat(key: String, clazz: Class<T>): T? {
        return if (Build.VERSION.SDK_INT >= 33) {
            getParcelableExtra(key, clazz)
        } else {
            getParcelableExtra(key) as? T
        }
    }
}
