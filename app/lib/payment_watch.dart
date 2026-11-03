import 'dart:async';

import 'package:flutter/widgets.dart';

/// Waits for a payment the member makes in the browser, so they never have to come back and tap
/// "Check again". It checks when the app returns to the front, and every few seconds in between,
/// until [check] says the money has arrived or [window] runs out.
///
/// Call [stop] when the screen that started it goes away.
class PaymentWatcher with WidgetsBindingObserver {
  PaymentWatcher({
    required this.check,
    required this.onPaid,
    this.window = const Duration(minutes: 5),
  });

  /// Returns true once the payment has arrived. A failed check (for example no signal) is simply tried again.
  final Future<bool> Function() check;

  /// Called once, when [check] first returns true.
  final VoidCallback onPaid;

  final Duration window;

  Timer? _timer;
  DateTime? _until;
  bool _checking = false;
  bool _active = false;

  void start() {
    if (_active) return;
    _active = true;
    _until = DateTime.now().add(window);
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _tick());
  }

  void stop() {
    if (!_active) return;
    _active = false;
    _timer?.cancel();
    _timer = null;
    WidgetsBinding.instance.removeObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _tick();
  }

  Future<void> _tick() async {
    if (!_active || _checking) return;
    final until = _until;
    if (until != null && DateTime.now().isAfter(until)) {
      stop();
      return;
    }
    _checking = true;
    try {
      if (await check()) {
        stop();
        onPaid();
      }
    } catch (_) {
      // Network blip: the next tick tries again.
    } finally {
      _checking = false;
    }
  }
}
