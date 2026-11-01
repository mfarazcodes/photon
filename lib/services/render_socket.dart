import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

enum RenderLink { offline, connecting, live }

/// WebSocket link to the local render engine.
///
/// [connect] keeps the link up: a refused or dropped connection is retried
/// with capped exponential backoff until [disconnect] or [dispose]. Text
/// frames that decode to a JSON object are broadcast on [messages]; anything
/// else is dropped.
class RenderSocket {
  RenderSocket({
    Uri? uri,
    this.minBackoff = const Duration(milliseconds: 500),
    this.maxBackoff = const Duration(seconds: 10),
    this.connectTimeout = const Duration(seconds: 4),
  }) : uri = uri ?? defaultUri;

  static final Uri defaultUri = Uri.parse('ws://127.0.0.1:8765');

  final Uri uri;
  final Duration minBackoff;
  final Duration maxBackoff;
  final Duration connectTimeout;

  final ValueNotifier<RenderLink> link = ValueNotifier(RenderLink.offline);

  final StreamController<Map<String, dynamic>> _messages = StreamController.broadcast();
  Stream<Map<String, dynamic>> get messages => _messages.stream;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _sub;
  Timer? _retry;
  int _attempt = 0;
  bool _running = false;
  bool _disposed = false;

  /// Bumped on every connect/disconnect so a handshake that finishes after
  /// the link was torn down knows to discard its channel.
  int _session = 0;

  bool get isLive => link.value == RenderLink.live;

  void connect() {
    if (_disposed || _running) return;
    _running = true;
    _attempt = 0;
    _open(++_session);
  }

  void disconnect() {
    _running = false;
    _session++;
    _retry?.cancel();
    _retry = null;
    _sub?.cancel();
    _sub = null;
    _channel?.sink.close();
    _channel = null;
    _setLink(RenderLink.offline);
  }

  /// Sends [message] as JSON. Returns false, without queueing, when offline.
  bool send(Map<String, Object?> message) {
    final channel = _channel;
    if (channel == null || !isLive) return false;
    try {
      channel.sink.add(jsonEncode(message));
      return true;
    } on StateError {
      return false;
    }
  }

  Future<void> _open(int session) async {
    _retry = null;
    _setLink(RenderLink.connecting);
    final channel = WebSocketChannel.connect(uri);
    try {
      await channel.ready.timeout(connectTimeout);
      if (session != _session) {
        unawaited(channel.sink.close());
        return;
      }
      _channel = channel;
      _attempt = 0;
      _sub = channel.stream.listen(
        _onData,
        onDone: () => _onClosed(session),
        onError: (Object _) => _onClosed(session),
        cancelOnError: true,
      );
      _setLink(RenderLink.live);
    } catch (e) {
      unawaited(channel.sink.close());
      if (session != _session) return;
      // The engine being down is the normal case; log the first miss only.
      if (_attempt == 0) debugPrint('RenderSocket: $uri unreachable ($e), retrying');
      _scheduleRetry(session);
    }
  }

  void _onData(dynamic data) {
    if (data is! String) return;
    final Object? decoded;
    try {
      decoded = jsonDecode(data);
    } on FormatException catch (e) {
      debugPrint('RenderSocket: dropped malformed frame ($e)');
      return;
    }
    if (decoded is Map<String, dynamic> && !_messages.isClosed) _messages.add(decoded);
  }

  void _onClosed(int session) {
    if (session != _session) return;
    _sub = null;
    _channel = null;
    _scheduleRetry(session);
  }

  void _scheduleRetry(int session) {
    _setLink(RenderLink.offline);
    if (!_running || _disposed) return;
    final ms = math.min(
      maxBackoff.inMilliseconds,
      minBackoff.inMilliseconds * (1 << math.min(_attempt, 10)),
    );
    _attempt++;
    _retry = Timer(Duration(milliseconds: ms), () => _open(session));
  }

  void _setLink(RenderLink value) {
    if (!_disposed) link.value = value;
  }

  void dispose() {
    disconnect();
    _disposed = true;
    _messages.close();
    link.dispose();
  }
}
