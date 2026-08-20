package com.daytrace.daytrace

import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        const val launchChannel = "daytrace/widget_launch"
        const val extraQuickAdd = "com.daytrace.daytrace.QUICK_ADD"
    }

    private var channel: MethodChannel? = null
    private var pendingQuickAdd = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        pendingQuickAdd = intent?.getBooleanExtra(extraQuickAdd, false) == true
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, launchChannel)
        channel?.setMethodCallHandler { call: MethodCall, result: MethodChannel.Result ->
            if (call.method == "consumeInitialQuickAdd") {
                result.success(pendingQuickAdd)
                pendingQuickAdd = false
            } else if (call.method == "acknowledgeQuickAdd") {
                pendingQuickAdd = false
                result.success(null)
            } else {
                result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        if (intent.getBooleanExtra(extraQuickAdd, false)) {
            pendingQuickAdd = true
            channel?.invokeMethod("openQuickAdd", null)
        }
    }
}
