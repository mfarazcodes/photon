import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:photon/models/vfx_dna.dart';
import 'package:photon/services/engine_socket.dart';
import 'package:photon/state/workspace_controller.dart';

// Plain test() (not testWidgets) on purpose: no widget binding, so HTTP is not
// mocked and the socket talks to a real in-process server.

/// Minimal stand-in for the Python render server.
class FakeEngine {
  late HttpServer _server;
  final List<WebSocket> clients = [];
  final List<Map<String, dynamic>> received = [];

  Uri get uri => Uri.parse('ws://127.0.0.1:${_server.port}');

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.transform(WebSocketTransformer()).listen((ws) {
      clients.add(ws);
      ws.listen((d) => received.add(jsonDecode(d as String) as Map<String, dynamic>));
    });
  }

  void broadcast(Object frame) {
    final text = frame is String ? frame : jsonEncode(frame);
    for (final c in clients) {
      c.add(text);
    }
  }

  Future<void> stop() async {
    for (final c in clients) {
      await c.close();
    }
    await _server.close(force: true);
  }
}

Future<void> until(bool Function() test, {String? reason}) async {
  for (var i = 0; i < 250; i++) {
    if (test()) return;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  fail('timed out waiting for ${reason ?? 'condition'}');
}

EngineSocket socketFor(FakeEngine engine) => EngineSocket(
      uri: engine.uri,
      minBackoff: const Duration(milliseconds: 50),
      maxBackoff: const Duration(milliseconds: 200),
    );

PromptSpec spec(String prompt) => PromptSpec(
      prompt: prompt,
      negative: '',
      resolution: '',
      frameRate: '',
      solver: '',
      seed: 1,
      volumetric: true,
      denoise: false,
      exportExr: true,
    );

void main() {
  group('EngineSocket', () {
    late FakeEngine server;
    setUp(() async => (server = FakeEngine()).start());
    tearDown(() async => server.stop());

    test('connects, streams JSON objects, drops junk, sends', () async {
      final socket = socketFor(server);
      addTearDown(socket.dispose);
      final got = <Map<String, dynamic>>[];
      socket.messages.listen(got.add);

      expect(socket.send({'type': 'x'}), isFalse, reason: 'not connected yet');
      socket.connect();
      await until(() => socket.isConnected, reason: 'connect');

      server.broadcast('not json');
      server.broadcast('[1, 2]');
      server.broadcast({'type': 'telemetry', 'progress': 0.5, 'fps': 42, 'status': 'rendering'});
      await until(() => got.isNotEmpty, reason: 'telemetry');
      expect(got.single['fps'], 42);

      expect(socket.send({'type': 'render', 'prompt': 'fog'}), isTrue);
      await until(() => server.received.isNotEmpty, reason: 'server receive');
      expect(server.received.single['prompt'], 'fog');
    });

    test('reconnects after the server drops the connection', () async {
      final socket = socketFor(server);
      addTearDown(socket.dispose);
      final states = <EngineConnection>[];
      socket.state.addListener(() => states.add(socket.state.value));

      socket.connect();
      await until(() => socket.isConnected, reason: 'first connect');
      await server.clients.single.close();
      await until(() => !socket.isConnected, reason: 'drop noticed');
      await until(() => socket.isConnected, reason: 'reconnect');
      expect(server.clients, hasLength(2));
      expect(states, containsAllInOrder([
        EngineConnection.connected,
        EngineConnection.disconnected,
        EngineConnection.connecting,
        EngineConnection.connected,
      ]));
    });

    test('keeps retrying while the server is down', () async {
      final port = server.uri.port;
      await server.stop();
      final socket = EngineSocket(
        uri: Uri.parse('ws://127.0.0.1:$port'),
        minBackoff: const Duration(milliseconds: 50),
        maxBackoff: const Duration(milliseconds: 100),
      );
      addTearDown(socket.dispose);
      socket.connect();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(socket.isConnected, isFalse);

      // Server comes back on the same port.
      final revived = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
      addTearDown(() => revived.close(force: true));
      revived.transform(WebSocketTransformer()).listen((_) {});
      await until(() => socket.isConnected, reason: 'connect once server is up');
    });
  });

  group('RenderQueue telemetry', () {
    late RenderQueue q;
    setUp(() => q = RenderQueue()..setEngineOnline(true));
    tearDown(() => q.dispose());

    test('progress, fps and status drive an engine job to completion', () {
      PromptSpec? done;
      q.onComplete = (s) => done = s;
      q.launch(spec('chrome splash'), jobId: 'job_1');
      expect(q.isRemoteJob, isTrue);
      expect(q.current.device, 'Photon Engine');

      q.applyTelemetry({'type': 'telemetry', 'progress': 0.4, 'fps': 31, 'status': 'denoising'});
      expect(q.progress, 0.4);
      expect(q.fps, 31);
      expect(q.engineStatus, 'denoising');

      // Another job's frames are ignored.
      q.applyTelemetry({'type': 'telemetry', 'job_id': 'job_0', 'progress': 0.9});
      expect(q.progress, 0.4);

      q.applyTelemetry({'type': 'telemetry', 'job_id': 'job_1', 'progress': 1.0});
      expect(done?.prompt, 'chrome splash');
      expect(q.hasUserJob, isFalse);
    });

    test('error status and lost connection fail the job until skipped', () {
      q.launch(spec('fog'), jobId: 'job_2');
      q.applyTelemetry({'type': 'telemetry', 'status': 'error'});
      expect(q.failed, isTrue);
      q.skip();
      expect(q.hasUserJob, isFalse);

      q.launch(spec('fog'), jobId: 'job_3');
      q.setEngineOnline(false);
      expect(q.failed, isTrue);
      expect(q.engineStatus, 'engine offline');
    });

    test('a dna object on the complete frame overrides the compiled effect', () {
      PromptSpec? done;
      q.onComplete = (s) => done = s;
      final form = spec('neon fluid');
      q.launch(form.withDna(form.compileDna()), jobId: 'job_5');
      expect(q.current.dna?.primary, VfxSolver.metaballFluid);

      // A dna object for some other job is ignored.
      q.applyTelemetry({'job_id': 'job_9', 'progress': 0.2, 'dna': {'primary': 'cyberGridWave'}});
      q.applyTelemetry({'type': 'telemetry', 'job_id': 'job_5', 'progress': 0.5, 'status': 'rendering'});
      expect(done, isNull);
      q.applyTelemetry({
        'type': 'telemetry',
        'job_id': 'job_5',
        'progress': 1.0,
        'status': 'complete',
        'dna': {
          'palette': 'ice',
          'primary': 'neuralPlexus',
          'fx': ['scanlines'],
        },
      });
      expect(done!.dna!.primary, VfxSolver.neuralPlexus);
      expect(done!.dna!.paletteName, 'ice');
      expect(done!.dna!.fx, {VfxFx.scanlines});
    });

    test('without a dna object the completed render keeps its compiled effect', () {
      PromptSpec? done;
      q.onComplete = (s) => done = s;
      q.launch(spec('golden solar shockwave vortex'), jobId: 'job_6'); // spec has no dna yet
      q.applyTelemetry({'type': 'telemetry', 'progress': 1.0, 'status': 'complete'});
      expect(done!.dna, isNotNull);
      expect(done!.dna!.primary, VfxSolver.shockwaveRings);
    });

    test('pause forwards a control action for engine jobs', () {
      final actions = <String>[];
      q.onControl = actions.add;
      q.launch(spec('fog'), jobId: 'job_4');
      q.togglePause();
      q.togglePause();
      expect(actions, ['pause', 'resume']);
    });
  });

  test('submitPrompt sends the form and live params to the engine', () async {
    final server = FakeEngine();
    await server.start();
    addTearDown(server.stop);
    final ws = WorkspaceController(engine: socketFor(server));
    addTearDown(ws.dispose);
    await until(() => ws.engine.isConnected, reason: 'connect');
    expect(ws.renderQueue.engineOnline, isTrue);

    ws.params.update(turbulence: 0.25, coherence: 0.75);
    ws.draft.prompt.text = 'volumetric shockwave';
    ws.draft.resolution.text = '3840x2160';
    ws.draft.solver.text = 'SPH';
    ws.draft.seed.text = '42';
    expect(ws.submitPrompt(), isTrue);

    await until(() => server.received.isNotEmpty, reason: 'render payload');
    final msg = server.received.single;
    expect(msg['type'], 'render');
    expect(msg['prompt'], 'volumetric shockwave');
    expect(msg['resolution'], '3840x2160');
    expect(msg['frame_rate'], isNull);
    expect(msg['solver'], 'SPH');
    expect(msg['seed'], 42);
    expect(msg['params'], containsPair('turbulence', 0.25));
    expect(msg['params'], containsPair('coherence', 0.75));
    expect(msg['job_id'], ws.renderQueue.jobId);

    server.broadcast({'type': 'telemetry', 'progress': 0.6, 'fps': 24, 'status': 'rendering'});
    await until(() => ws.renderQueue.progress == 0.6, reason: 'telemetry applied');
    expect(ws.renderQueue.fps, 24);
  });
}
