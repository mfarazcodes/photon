import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

enum EngineConnection { disconnected, connecting, connected }

/// WebSocket link to the local Python render server.
///
/// After [connect], the link keeps itself up: a dropped or refused connection
/// is retried with capped exponential backoff until [disconnect] or [dispose].
/// Incoming text frames are decoded as JSON objects and broadcast on
/// [messages]; anything else is dropped.
class EngineSocket {
  EngineSocket({
    Uri? uri,
    this.connectTimeout = const Duration(seconds: 4),
    this.pingInterval = const Duration(seconds: 5),
    this.minBackoff = const Duration(milliseconds: 500),
    this.maxBackoff = const Duration(seconds: 10),
  }) : uri = uri ?? defaultUri;

  static final Uri defaultUri = Uri.parse('ws://127.0.0.1:8765');

  final Uri uri;
  final Duration connectTimeout;

  /// Keep-alive pings; a server that stops answering is treated as gone.
  final Duration pingInterval;
  final Duration minBackoff;
  final Duration maxBackoff;

  /// [EngineConnection.connecting] only during a handshake; between retries
  /// the link reports [EngineConnection.disconnected].
  final ValueNotifier<EngineConnection> state = ValueNotifier(EngineConnection.disconnected);

  final StreamController<Map<String, dynamic>> _messages = StreamController.broadcast();

  /// Decoded JSON objects from the server.
  Stream<Map<String, dynamic>> get messages => _messages.stream;

  bool get isConnected => state.value == EngineConnection.connected;

  WebSocket? _socket;
  StreamSubscription<dynamic>? _sub;
  Timer? _retry;
  int _attempt = 0;
  bool _running = false;
  bool _disposed = false;

  /// Bumped on every connect/disconnect so a handshake that finishes after
  /// the link was torn down knows to discard its socket.
  int _session = 0;

  /// Starts connecting and keeps the link up until [disconnect] or [dispose].
  void connect() {
    if (_disposed || _running) return;
    _running = true;
    _attempt = 0;
    _open(++_session);
  }

  /// Closes the link and stops reconnecting.
  void disconnect() {
    _running = false;
    _session++;
    _retry?.cancel();
    _retry = null;
    _sub?.cancel();
    _sub = null;
    _socket?.close(WebSocketStatus.normalClosure);
    _socket = null;
    _setState(EngineConnection.disconnected);
  }

  /// Encodes [message] as JSON and sends it. Returns false, without queueing,
  /// when the link is down.
  bool send(Map<String, Object?> message) {
    final socket = _socket;
    if (socket == null || socket.readyState != WebSocket.open) return false;
    try {
      socket.add(jsonEncode(message));
      return true;
    } on StateError {
      return false;
    }
  }

  Future<void> _open(int session) async {
    _retry = null;
    _setState(EngineConnection.connecting);
    final client = HttpClient()..connectionTimeout = connectTimeout;
    try {
      final socket = await WebSocket.connect(uri.toString(), customClient: client);
      if (session != _session) {
        await socket.close(WebSocketStatus.normalClosure);
        return;
      }
      socket.pingInterval = pingInterval;
      _socket = socket;
      _attempt = 0;
      _sub = socket.listen(
        _onData,
        onDone: () => _onClosed(session),
        onError: (Object _) => _onClosed(session),
        cancelOnError: true,
      );
      _setState(EngineConnection.connected);
    } catch (e) {
      if (session != _session) return;
      // Log the first failure only; the server being down is the normal case.
      if (_attempt == 0) debugPrint('EngineSocket: $uri unreachable ($e), retrying');
      _scheduleRetry(session);
    } finally {
      client.close();
    }
  }

  void _onData(dynamic data) {
    if (data is! String) return;
    final Object? decoded;
    try {
      decoded = jsonDecode(data);
    } on FormatException catch (e) {
      debugPrint('EngineSocket: dropped malformed frame ($e)');
      return;
    }
    if (decoded is Map<String, dynamic> && !_messages.isClosed) _messages.add(decoded);
  }

  void _onClosed(int session) {
    if (session != _session) return;
    _sub = null;
    _socket = null;
    debugPrint('EngineSocket: connection to $uri closed, reconnecting');
    _scheduleRetry(session);
  }

  void _scheduleRetry(int session) {
    _setState(EngineConnection.disconnected);
    if (!_running || _disposed) return;
    final ms = math.min(
      maxBackoff.inMilliseconds,
      minBackoff.inMilliseconds * (1 << math.min(_attempt, 10)),
    );
    _attempt++;
    _retry = Timer(Duration(milliseconds: ms), () => _open(session));
  }

  void _setState(EngineConnection value) {
    if (!_disposed) state.value = value;
  }

  void dispose() {
    disconnect();
    _disposed = true;
    _messages.close();
    state.dispose();
  }
}
