package com.kareemham.store

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var bluetoothThermalHandler: BluetoothThermalHandler? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        bluetoothThermalHandler = BluetoothThermalHandler(
            this,
            flutterEngine.dartExecutor.binaryMessenger,
        )
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        bluetoothThermalHandler?.dispose()
        bluetoothThermalHandler = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
