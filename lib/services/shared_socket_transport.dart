import 'package:socket_io_client/socket_io_client.dart' as io;

import 'socket_client_options.dart';
import 'webrtc_service.dart' show signalingServerUrl;

/// Messaging and call signaling share one authenticated Socket.IO transport.
/// Event ownership stays in the feature services; this class only owns the
/// physical connection and its reconnect lifecycle.
class SharedSocketTransport {
  SharedSocketTransport._();

  static final SharedSocketTransport instance = SharedSocketTransport._();

  factory SharedSocketTransport() => instance;

  io.Socket? _socket;
  DateTime? _lastReconnectAt;
  bool _plannedReconnect = false;

  io.Socket? get socket => _socket;
  bool get isPlannedReconnect => _plannedReconnect;

  io.Socket socketFor(String authToken) {
    final existing = _socket;
    if (existing != null) {
      existing.auth = <String, dynamic>{'token': authToken};
      return existing;
    }

    return _socket = io.io(
      signalingServerUrl,
      buildSocketClientOptions(authToken: authToken),
    );
  }

  void connect(String authToken) {
    final current = socketFor(authToken);
    if (!current.connected) current.connect();
  }

  bool reconnect(String authToken) {
    final current = socketFor(authToken);
    final now = DateTime.now();
    final last = _lastReconnectAt;
    if (last != null &&
        now.difference(last) < const Duration(milliseconds: 500)) {
      return false;
    }
    _lastReconnectAt = now;
    _plannedReconnect = true;
    current.disconnect();
    current.auth = <String, dynamic>{'token': authToken};
    current.connect();
    Future<void>.delayed(const Duration(seconds: 1), () {
      _plannedReconnect = false;
    });
    return true;
  }

  void disconnect() {
    final current = _socket;
    _socket = null;
    _lastReconnectAt = null;
    _plannedReconnect = false;
    current?.disconnect();
    current?.dispose();
  }
}
