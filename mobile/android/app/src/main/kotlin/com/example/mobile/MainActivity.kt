package com.example.mobile

import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.bluetooth.le.AdvertiseCallback
import android.bluetooth.le.AdvertiseData
import android.bluetooth.le.AdvertiseSettings
import android.bluetooth.le.BluetoothLeAdvertiser
import android.content.Context
import android.os.ParcelUuid
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.UUID

class MainActivity : FlutterActivity() {

    private val BLE_CHANNEL = "drd.ops/ble_advertiser"
    private var advertiser: BluetoothLeAdvertiser? = null
    private var advertiseCallback: AdvertiseCallback? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BLE_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startAdvertising" -> {
                        val localName  = call.argument<String>("localName") ?: "DRD-Node"
                        val serviceUuid = call.argument<String>("serviceUuid")
                            ?: "6d726400-0000-1000-8000-000000000001"
                        startBleAdvertising(localName, serviceUuid, result)
                    }
                    "stopAdvertising" -> {
                        stopBleAdvertising()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun startBleAdvertising(
        localName: String,
        serviceUuidStr: String,
        result: MethodChannel.Result
    ) {
        try {
            val btManager = getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
            val btAdapter = btManager?.adapter

            if (btAdapter == null || !btAdapter.isEnabled) {
                result.error("BT_OFF", "Bluetooth adapter is off", null)
                return
            }

            // Set adapter name so other devices see "DRD-xxx" in scan
            @Suppress("DEPRECATION")
            btAdapter.name = localName

            advertiser = btAdapter.bluetoothLeAdvertiser
            if (advertiser == null) {
                result.error("NO_ADVERTISER", "BLE advertising not supported on this device", null)
                return
            }

            stopBleAdvertising() // stop any previous session

            val settings = AdvertiseSettings.Builder()
                .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_BALANCED)
                .setConnectable(true)
                .setTimeout(0) // advertise indefinitely
                .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_MEDIUM)
                .build()

            val serviceUuid = ParcelUuid(UUID.fromString(serviceUuidStr))

            val data = AdvertiseData.Builder()
                .setIncludeDeviceName(true)
                .addServiceUuid(serviceUuid)
                .build()

            advertiseCallback = object : AdvertiseCallback() {
                override fun onStartSuccess(settingsInEffect: AdvertiseSettings) {
                    // success is already returned synchronously below
                }
                override fun onStartFailure(errorCode: Int) {
                    // Already responded — just log
                }
            }

            advertiser!!.startAdvertising(settings, data, advertiseCallback!!)
            result.success(null)
        } catch (e: SecurityException) {
            result.error("PERMISSION", "Missing BLUETOOTH_ADVERTISE permission: ${e.message}", null)
        } catch (e: Exception) {
            result.error("ERROR", e.message, null)
        }
    }

    private fun stopBleAdvertising() {
        try {
            advertiseCallback?.let { advertiser?.stopAdvertising(it) }
        } catch (_: Exception) { }
        advertiseCallback = null
    }

    override fun onDestroy() {
        stopBleAdvertising()
        super.onDestroy()
    }
}
