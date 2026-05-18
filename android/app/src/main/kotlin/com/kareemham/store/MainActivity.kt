package com.kareemham.store

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var bluetoothThermalHandler: BluetoothThermalHandler? = null
    private var whatsappShareHandler: WhatsappShareHandler? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        bluetoothThermalHandler = BluetoothThermalHandler(this, messenger)
        whatsappShareHandler = WhatsappShareHandler(this, messenger)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        bluetoothThermalHandler?.dispose()
        bluetoothThermalHandler = null
        whatsappShareHandler?.dispose()
        whatsappShareHandler = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
