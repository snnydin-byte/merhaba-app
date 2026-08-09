import 'dart:async';

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
  bool _closedByOwner = false;
  String? _authToken;
  Timer? _reconnectTimer;
  Timer? _heartbeatTimer;
  int _reconnectAttempt = 0;

  io.Socket? get socket => _socket;
  bool get isPlannedReconnect => _plannedReconnect;

  io.Socket socketFor(String authToken) {
    _authToken = authToken;
    _closedByOwner = false;
    final existing = _socket;
    if (existing != null) {
      existing.auth = <String, dynamic>{'token': authToken};
      return existing;
    }

    final created = io.io(
      signalingServerUrl,
      buildSocketClientOptions(authToken: authToken),
    );
    created.onConnect((_) {
      if (!identical(_socket, created)) return;
      _reconnectAttempt = 0;
      _reconnectTimer?.cancel();
      _reconnectTimer = null;
      _startHeartbeat(created);
    });
    created.onDisconnect((reason) {
      if (!identical(_socket, created) || _closedByOwner) return;
      if (reason == 'io client disconnect') return;
      _scheduleReconnect(created);
    });
    created.onConnectError((_) {
      if (!identical(_socket, created) || _closedByOwner) return;
      _scheduleReconnect(created);
    });
    _socket = created;
    return created;
  }

  void _startHeartbeat(io.Socket expectedSocket) {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (_closedByOwner || !identical(_socket, expectedSocket)) return;
      if (expectedSocket.connected) {
        expectedSocket.emit('client-heartbeat', <String, dynamic>{
          'sentAt': DateTime.now().millisecondsSinceEpoch,
        });
      }
    });
  }

  void _scheduleReconnect(io.Socket expectedSocket) {
    if (_closedByOwner || !identical(_socket, expectedSocket)) return;
    if (_reconnectTimer?.isActive ?? false) return;
    const delays = <int>[1, 2, 4, 8, 16, 30];
    final seconds = delays[_reconnectAttempt.clamp(0, delays.length - 1)];
    _reconnectAttempt++;
    _reconnectTimer = Timer(Duration(seconds: seconds), () {
      _reconnectTimer = null;
      if (_closedByOwner || !identical(_socket, expectedSocket)) return;
      if (expectedSocket.connected) {
        _reconnectAttempt = 0;
        return;
      }
      final token = _authToken;
      if (token == null || token.isEmpty) return;
      // socket_io_client may leave its Manager in `reconnecting=true` after a
      // mobile ping timeout; calling connect() alone is then a no-op. Reset
      // that half-open manager explicitly before opening the authenticated
      // transport again.
      _plannedReconnect = true;
      expectedSocket.disconnect();
      expectedSocket.auth = <String, dynamic>{'token': token};
      expectedSocket.connect();
      Timer(const Duration(seconds: 1), () {
        if (identical(_socket, expectedSocket)) _plannedReconnect = false;
      });
      _scheduleReconnect(expectedSocket);
    });
  }

  void connect(String authToken) {
    final current = socketFor(authToken);
    if (!current.connected) current.connect();
  }

  bool reconnect(String authToken) {
    _authToken = authToken;
    _closedByOwner = false;
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
    _closedByOwner = true;
    _authToken = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _reconnectAttempt = 0;
    final current = _socket;
    _socket = null;
    _lastReconnectAt = null;
    _plannedReconnect = false;
    current?.disconnect();
    current?.dispose();
  }
}
