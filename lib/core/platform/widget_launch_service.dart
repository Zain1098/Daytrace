import 'dart:async';

import 'package:flutter/services.dart';

final WidgetLaunchService widgetLaunchService = WidgetLaunchService();

class WidgetLaunchService {
  WidgetLaunchService();

  static const MethodChannel _channel = MethodChannel('daytrace/widget_launch');
  final StreamController<int> _quickAddController =
      StreamController<int>.broadcast();
  bool _initialized = false;
  bool _pendingQuickAdd = false;
  int _requestNumber = 0;

  Stream<int> get quickAddRequests => _quickAddController.stream;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    _quickAddController.onListen = _emitPendingRequest;
    _channel.setMethodCallHandler((MethodCall call) async {
      if (call.method == 'openQuickAdd') {
        _requestQuickAdd();
        try {
          await _channel.invokeMethod<void>('acknowledgeQuickAdd');
        } on MissingPluginException {
          // Non-Android platforms do not provide the native widget bridge.
        }
      }
    });
    try {
      final bool initialQuickAdd =
          await _channel.invokeMethod<bool>('consumeInitialQuickAdd') ?? false;
      if (initialQuickAdd) _requestQuickAdd();
    } on MissingPluginException {
      // The app remains usable on non-Android targets without the widget bridge.
    }
  }

  void _requestQuickAdd() {
    if (_quickAddController.hasListener) {
      _quickAddController.add(++_requestNumber);
    } else {
      _pendingQuickAdd = true;
    }
  }

  void _emitPendingRequest() {
    if (!_pendingQuickAdd) return;
    _pendingQuickAdd = false;
    _quickAddController.add(++_requestNumber);
  }
}
