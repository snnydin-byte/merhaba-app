import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

abstract interface class NetworkAvailabilityMonitor {
  Stream<bool> get availabilityChanges;
  Future<bool> isAvailable();
}

class ConnectivityNetworkAvailabilityMonitor
    implements NetworkAvailabilityMonitor {
  ConnectivityNetworkAvailabilityMonitor({Connectivity? connectivity})
      : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  @override
  Stream<bool> get availabilityChanges =>
      _connectivity.onConnectivityChanged.map(_hasConnection).distinct();

  @override
  Future<bool> isAvailable() async {
    final result = await _connectivity.checkConnectivity();
    return _hasConnection(result);
  }

  static bool _hasConnection(List<ConnectivityResult> results) =>
      results.any((result) => result != ConnectivityResult.none);
}

class ManualNetworkAvailabilityMonitor implements NetworkAvailabilityMonitor {
  ManualNetworkAvailabilityMonitor({bool initiallyAvailable = true})
      : _available = initiallyAvailable;

  final StreamController<bool> _controller =
      StreamController<bool>.broadcast(sync: true);
  bool _available;

  @override
  Stream<bool> get availabilityChanges => _controller.stream;

  @override
  Future<bool> isAvailable() async => _available;

  void setAvailable(bool value) {
    if (_available == value) return;
    _available = value;
    _controller.add(value);
  }

  Future<void> dispose() => _controller.close();
}
