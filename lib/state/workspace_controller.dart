import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../models/desktop_node.dart';
import '../models/sim_params.dart';
import '../models/vfx_dna.dart';
import '../services/engine_socket.dart';

enum WindowType { viewport, compositor, inspector, finder }

enum StudioOverlay { none, promptDrawer, about, archive }

/// Title bars may never be dragged above the bottom edge of the pill bar.
const double kWindowMinTop = 72;

/// Default top margin of a freshly centred window, and the space kept free at
/// the bottom for the explore dock when a window is maximized.
const double kWindowTop = 82;
const double kWindowDockClearance = 104;

/// A floating macOS-style window on the desktop.
class OpenWindow {
  OpenWindow({
    required this.id,
    required this.type,
    required this.title,
    required this.size,
    this.node,
    this.finderView = FinderView.presetVault,
  });

  final String id;
  final WindowType type;
  final String title;
  final Size size;
  final DesktopNode? node;
  FinderView finderView;

  /// Offset from the centred default position.
  Offset offset = Offset.zero;
  bool maximized = false;
  bool minimized = false;
  bool dragging = false;

  /// The centred rect for [vp] before any drag [offset] is applied.
  Rect baseRectIn(Size vp) {
    final width = math.max(math.min(size.width, vp.width - 32), 280.0);
    final height = math.max(math.min(size.height, vp.height - kWindowTop - 16), 220.0);
    return Rect.fromLTWH(
      (vp.width - width) / 2,
      kWindowTop + (vp.height - kWindowTop - 16 - height) / 2,
      width,
      height,
    );
  }

  /// Where the window sits for [vp], honouring maximize and drag offset.
  Rect rectIn(Size vp) {
    if (maximized) {
      return Rect.fromLTWH(
        16,
        kWindowTop,
        math.max(vp.width - 32, 280),
        math.max(vp.height - kWindowTop - kWindowDockClearance, 220),
      );
    }
    return baseRectIn(vp).shift(offset);
  }

  /// Clamps [offset] so the title bar stays below the pill bar and at least
  /// part of the window stays reachable on every edge.
  void clampOffset(Size vp) {
    final base = baseRectIn(vp);
    const grab = 120.0;
    final minLeft = grab - base.width, maxLeft = vp.width - grab;
    final minTop = kWindowMinTop, maxTop = vp.height - 56;
    offset = Offset(
      (base.left + offset.dx).clamp(minLeft, math.max(minLeft, maxLeft)) - base.left,
      (base.top + offset.dy).clamp(minTop, math.max(minTop, maxTop)) - base.top,
    );
  }
}

class RenderJob {
  const RenderJob(this.name, this.device, this.vram, this.frames, this.sim, {this.dna});

  final String name;
  final String device;
  final int vram;
  final int frames;
  final SimKind sim;

  /// Set on user renders: the effect compiled from their prompt, so the queue
  /// thumbnail previews it rather than a preset [sim].
  final VfxDna? dna;
}

/// Everything the Prompt Studio form collects for one render.
class PromptSpec {
  const PromptSpec({
    required this.prompt,
    required this.negative,
    required this.resolution,
    required this.frameRate,
    required this.solver,
    required this.seed,
    required this.volumetric,
    required this.denoise,
    required this.exportExr,
    this.dna,
  });

  final String prompt;
  final String negative;
  final String resolution;
  final String frameRate;
  final String solver;
  final int seed;
  final bool volumetric;
  final bool denoise;
  final bool exportExr;

  /// The visual effect compiled from this form, once [compileDna] has run.
  final VfxDna? dna;

  /// Compiles the form into a [VfxDna]. [overrides] is the optional `dna`
  /// object from the render server.
  VfxDna compileDna({Map<String, dynamic>? overrides}) => VfxDna.compile(
        prompt: prompt,
        negative: negative,
        solver: solver,
        seed: seed,
        resolution: resolution,
        frameRate: frameRate,
        volumetric: volumetric,
        denoise: denoise,
        overrides: overrides,
      );

  PromptSpec withDna(VfxDna value) => PromptSpec(
        prompt: prompt,
        negative: negative,
        resolution: resolution,
        frameRate: frameRate,
        solver: solver,
        seed: seed,
        volumetric: volumetric,
        denoise: denoise,
        exportExr: exportExr,
        dna: value,
      );

  /// Form fields as sent to the engine. Blank optional fields are null so the
  /// server can apply its own defaults.
  Map<String, Object?> toJson() {
    String? orNull(String s) => s.isEmpty ? null : s;
    return {
      'prompt': prompt,
      'negative_prompt': orNull(negative),
      'resolution': orNull(resolution),
      'frame_rate': orNull(frameRate),
      'solver': orNull(solver),
      'seed': seed,
      'options': {
        'volumetric': volumetric,
        'denoise': denoise,
        'export_exr': exportExr,
      },
    };
  }

  /// Short uppercase file-style title from the first words of the prompt.
  String get title {
    final words = prompt
        .trim()
        .split(RegExp(r'[^A-Za-z0-9]+'))
        .where((w) => w.isNotEmpty)
        .take(3)
        .map((w) => w.toUpperCase())
        .join('_');
    final slug = words.isEmpty ? 'UNTITLED_PROMPT' : words;
    return slug.length > 22 ? slug.substring(0, 22) : slug;
  }

  SimKind get sim {
    final t = '$solver $prompt'.toLowerCase();
    bool has(List<String> keys) => keys.any(t.contains);
    if (has(['chrome', 'metal', 'frag', 'pbr'])) return SimKind.chrome;
    if (has(['liquid', 'goo', 'fluid', 'sph', 'slime', 'splash'])) return SimKind.liquid;
    if (has(['marble', 'smoke', 'turbul', 'fbm'])) return SimKind.marble;
    if (has(['water', 'caustic', 'pool', 'photon map'])) return SimKind.caustics;
    if (has(['swarm', 'nano', 'particle', 'boid'])) return SimKind.swarm;
    if (has(['cloth', 'vacuum', 'plastic', 'membrane'])) return SimKind.cloth;
    if (has(['wire', 'mesh', 'topolog'])) return SimKind.wireframe;
    return SimKind.fog;
  }

  /// Stable FNV-1a hash of the prompt, so one prompt always seeds the same look.
  int get _hash {
    var h = 0x811C9DC5;
    for (final c in prompt.codeUnits) {
      h = ((h ^ c) * 0x01000193) & 0xFFFFFFFF;
    }
    return h;
  }

  /// Shader parameters derived from the prompt and the form toggles.
  SimParams params() {
    double f(int shift) => ((_hash >> shift) & 0xFF) / 255;
    return SimParams(
      turbulence: 0.3 + 0.6 * f(0),
      coherence: (0.3 + 0.5 * f(8) + (denoise ? 0.15 : 0)).clamp(0.0, 1.0),
      density: (0.5 + 0.35 * f(16) + (volumetric ? 0.15 : 0)).clamp(0.0, 1.0),
      dispersion: 0.1 + 0.3 * f(24),
      timeScale: 1.0,
    );
  }
}

/// Mutable form state for the Prompt Studio drawer, owned here so that drafts
/// survive the drawer closing.
class PromptDraft {
  final prompt = TextEditingController();
  final negative = TextEditingController();
  final resolution = TextEditingController();
  final frameRate = TextEditingController();
  final solver = TextEditingController();
  final seed = TextEditingController();
  final List<bool> checks = [true, false, true];

  /// True after a submit attempt with an empty scene prompt.
  final ValueNotifier<bool> error = ValueNotifier(false);

  void reset() {
    for (final c in [prompt, negative, resolution, frameRate, solver, seed]) {
      c.clear();
    }
    error.value = false;
  }

  void dispose() {
    for (final c in [prompt, negative, resolution, frameRate, solver, seed]) {
      c.dispose();
    }
    error.dispose();
  }
}

/// Background render queue shown in the top-right pill.
///
/// While the Python engine is online, a user render runs there and the
/// engine's telemetry drives its progress, status and the FPS readout.
/// Offline, a user render falls back to a local preview that takes
/// [userRenderSeconds].
class RenderQueue extends ChangeNotifier {
  RenderQueue() {
    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) => _tick());
  }

  late final Timer _timer;
  final math.Random _rng = math.Random();

  /// A user render takes exactly this long, 0% to 100%.
  static const double userRenderSeconds = 4;
  static const double _tickSeconds = 0.1;

  final List<RenderJob> jobs = [
    const RenderJob('Volumetric Shockwave_v4.exr', 'CUDA GPU', 78, 240, SimKind.fog),
    const RenderJob('Liquid Chrome Bloom_v2.exr', 'Vulkan Compute', 64, 180, SimKind.chrome),
    const RenderJob('Nanobot Dissolve_v7.mp4', 'CUDA GPU', 71, 300, SimKind.swarm),
    const RenderJob('Caustic Pool Loop_v1.exr', 'Cloud Cluster', 52, 120, SimKind.caustics),
  ];

  int index = 0;
  double _ambient = 0.37;
  bool paused = false;

  RenderJob? _user;
  PromptSpec? _spec;
  double _userProgress = 0;

  /// Engine-side id of the active user job; null for a local preview.
  String? _jobId;

  /// `dna` overrides the engine sent for the active job, applied when it
  /// completes.
  Map<String, dynamic>? _dnaOverride;

  /// Called once when a user-launched render reaches 100%.
  void Function(PromptSpec spec)? onComplete;

  /// Forwards pause/resume of an engine job to the server.
  void Function(String action)? onControl;

  /// Live telemetry. VRAM drifts toward the active job's load; FPS is
  /// simulated offline and reported by the engine online.
  int vram = 78;
  int fps = 60;

  /// True while the Python engine is reachable.
  bool engineOnline = false;

  /// Last status string reported by the engine, e.g. "rendering".
  String? engineStatus;

  /// The active engine job failed or lost its connection. It stays in the
  /// queue, frozen, until skipped.
  bool failed = false;

  static const _doneStatuses = {'complete', 'completed', 'done', 'finished'};
  static const _failedStatuses = {'error', 'failed', 'cancelled', 'canceled'};

  bool get hasUserJob => _user != null;
  bool get isRemoteJob => _jobId != null;
  String? get jobId => _jobId;
  RenderJob get current => _user ?? jobs[index];
  double get progress => _user != null ? _userProgress : _ambient;
  int get frame => (progress * current.frames).floor();
  Duration get eta {
    final remaining = (1 - progress) * current.frames;
    return Duration(seconds: (remaining * 0.8).round());
  }

  void _tick() {
    if (!paused) {
      if (_user != null) {
        // Engine jobs advance only through [applyTelemetry].
        if (_jobId == null) {
          _userProgress += _tickSeconds / userRenderSeconds;
          if (_userProgress >= 0.9999) {
            _finish();
            return;
          }
        }
      } else {
        _ambient += 0.0011;
        if (_ambient >= 1) {
          _ambient = 0;
          index = (index + 1) % jobs.length;
        }
      }
    }
    final load = _user != null ? 62 + 30 * _userProgress : current.vram.toDouble();
    vram = (vram + (load - vram) * 0.25 + (_rng.nextDouble() - 0.5) * 3)
        .round()
        .clamp(40, 99);
    if (!engineOnline) {
      fps = paused
          ? 0
          : (60 - (_user != null ? _userProgress * 6 : 0) - _rng.nextInt(4)).round();
    }
    notifyListeners();
  }

  void _clearUser() {
    _user = null;
    _spec = null;
    _jobId = null;
    _dnaOverride = null;
    _userProgress = 0;
    failed = false;
  }

  void _finish() {
    // Whatever happened, the finished render carries a compiled effect, with
    // the engine's overrides on top when it sent any.
    var spec = _spec!;
    final override = _dnaOverride;
    if (override != null) {
      spec = spec.withDna((spec.dna ?? spec.compileDna()).withOverrides(override));
    } else if (spec.dna == null) {
      spec = spec.withDna(spec.compileDna());
    }
    _clearUser();
    notifyListeners();
    onComplete?.call(spec);
  }

  void togglePause() {
    paused = !paused;
    if (_jobId != null && !failed) onControl?.call(paused ? 'pause' : 'resume');
    notifyListeners();
  }

  void skip() {
    if (_user != null) {
      // A live user job runs to completion; only a failed one is dismissable.
      if (!failed) return;
      _clearUser();
      notifyListeners();
      return;
    }
    index = (index + 1) % jobs.length;
    _ambient = 0;
    notifyListeners();
  }

  /// Starts a user render. With a [jobId] the engine is rendering it and
  /// telemetry drives progress; without one it runs as a local preview.
  void launch(PromptSpec spec, {String? jobId}) {
    _spec = spec;
    _jobId = jobId;
    _user = RenderJob(
      '${spec.title}.exr',
      jobId != null ? 'Photon Engine' : 'Local Preview',
      62,
      240,
      spec.sim,
      dna: spec.dna,
    );
    _dnaOverride = null;
    _userProgress = 0;
    failed = false;
    engineStatus = null;
    paused = false;
    notifyListeners();
  }

  void setEngineOnline(bool online) {
    if (online == engineOnline) return;
    engineOnline = online;
    if (!online && _jobId != null && !failed) {
      failed = true;
      engineStatus = 'engine offline';
    }
    notifyListeners();
  }

  /// Applies a `{"type": "telemetry", "progress": 0..1, "fps": n,
  /// "status": "..."}` frame; every field is optional. Progress and status
  /// only touch the active engine job, and only when the frame's `job_id`, if
  /// present, matches it. A frame may also carry a `"dna": {...}` object (see
  /// [VfxDna.withOverrides]); the last one received before the job completes,
  /// normally on the `complete` frame, overrides the locally compiled effect.
  void applyTelemetry(Map<String, dynamic> msg) {
    final fps = msg['fps'];
    if (fps is num && fps.isFinite) this.fps = fps.round().clamp(0, 999);
    final status = msg['status'];
    final id = msg['job_id'];
    final ours = _jobId != null && !failed && (id == null || id == _jobId);
    if (!ours) {
      if (status is String && _user == null) engineStatus = status;
      notifyListeners();
      return;
    }
    if (status is String) engineStatus = status;
    final dna = msg['dna'];
    if (dna is Map<String, dynamic>) _dnaOverride = dna;
    final progress = msg['progress'];
    if (progress is num && progress.isFinite) {
      _userProgress = progress.toDouble().clamp(0.0, 1.0);
    }
    final s = engineStatus?.toLowerCase();
    if (_failedStatuses.contains(s)) {
      failed = true;
    } else if (_userProgress >= 1 || _doneStatuses.contains(s)) {
      _finish();
      return;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }
}

/// Single source of truth for the spatial desktop.
class WorkspaceController extends ChangeNotifier {
  /// Takes ownership of [engine] and, if [connectEngine], connects it.
  WorkspaceController({EngineSocket? engine, bool connectEngine = true})
      : engine = engine ?? EngineSocket() {
    renderQueue.onComplete = _onRenderComplete;
    renderQueue.onControl = _sendControl;
    this.engine.state.addListener(_onEngineState);
    _engineSub = this.engine.messages.listen(_onEngineMessage);
    if (connectEngine) this.engine.connect();
  }

  /// Link to the local Python render server.
  final EngineSocket engine;
  late final StreamSubscription<Map<String, dynamic>> _engineSub;

  final RenderQueue renderQueue = RenderQueue();
  final PromptDraft draft = PromptDraft();

  /// Workspace-wide shader parameters edited by the engine inspector.
  final SimParams params = SimParams();

  /// Desktop nodes. Starts as the built-in set; renders append to it.
  final List<DesktopNode> nodes = List.of(kDesktopNodes);

  String? selectedId;
  final List<OpenWindow> windows = [];
  bool gravity = false;
  bool renderDropdownOpen = false;
  bool exploreOpen = false;
  StudioOverlay overlay = StudioOverlay.none;
  int _cascade = 0;
  int _generated = 0;

  /// Size of the window area, set by the window layer.
  Size viewport = Size.zero;

  OpenWindow? get topWindow => windows.isEmpty ? null : windows.last;

  /// Shader parameters a node's viewport should use.
  SimParams paramsFor(DesktopNode node) => node.params ?? params;

  void setViewport(Size size) {
    if (size == viewport) return;
    viewport = size;
    for (final w in windows) {
      w.clampOffset(size);
    }
  }

  void select(String? id) {
    if (selectedId == id && !exploreOpen && !renderDropdownOpen) return;
    selectedId = id;
    exploreOpen = false;
    renderDropdownOpen = false;
    notifyListeners();
  }

  void openNode(DesktopNode node) {
    selectedId = node.id;
    if (node.isFolder) {
      openFinder(node.finderView ?? FinderView.presetVault);
      return;
    }
    final compositor = node.kind == NodeKind.comp;
    _openOrFocus(
      'node:${node.id}',
      () => OpenWindow(
        id: 'node:${node.id}',
        type: compositor ? WindowType.compositor : WindowType.viewport,
        title: node.label,
        node: node,
        size: compositor ? const Size(980, 600) : const Size(780, 700),
      ),
    );
  }

  void openInspector() {
    selectedId = kCoreCardId;
    _openOrFocus(
      'inspector',
      () => OpenWindow(
        id: 'inspector',
        type: WindowType.inspector,
        title: 'PHOTON_ENGINE_V3.4',
        size: const Size(1040, 880),
      ),
    );
  }

  void openFinder(FinderView view) {
    final i = windows.indexWhere((w) => w.id == 'finder');
    if (i >= 0) windows[i].finderView = view;
    _openOrFocus(
      'finder',
      () => OpenWindow(
        id: 'finder',
        type: WindowType.finder,
        title: 'PHOTON FINDER',
        size: const Size(1000, 640),
        finderView: view,
      ),
    );
  }

  void _openOrFocus(String id, OpenWindow Function() create) {
    exploreOpen = false;
    renderDropdownOpen = false;
    overlay = StudioOverlay.none;
    final i = windows.indexWhere((w) => w.id == id);
    if (i >= 0) {
      final w = windows.removeAt(i)..minimized = false;
      windows.add(w);
    } else {
      final w = create();
      final step = _cascade % 4;
      w.offset = Offset(26.0 * step, 20.0 * step);
      _cascade++;
      windows.add(w);
    }
    notifyListeners();
  }

  /// Promotes a window to the top of the stack.
  void focus(String id) {
    if (topWindow?.id == id) return;
    final i = windows.indexWhere((w) => w.id == id);
    if (i < 0) return;
    windows.add(windows.removeAt(i));
    notifyListeners();
  }

  void close(String id) {
    windows.removeWhere((w) => w.id == id);
    notifyListeners();
  }

  void minimize(String id) {
    for (final w in windows) {
      if (w.id == id) w.minimized = true;
    }
    notifyListeners();
  }

  void toggleMaximize(String id) {
    for (final w in windows) {
      if (w.id == id) w.maximized = !w.maximized;
    }
    notifyListeners();
  }

  void dragWindow(String id, Offset delta) {
    for (final w in windows) {
      if (w.id != id) continue;
      if (w.maximized) {
        // Dragging a maximized window restores it under the pointer.
        w.maximized = false;
        w.offset = Offset.zero;
      }
      w.offset += delta;
      if (viewport != Size.zero) w.clampOffset(viewport);
      w.dragging = true;
    }
    notifyListeners();
  }

  void endDragWindow(String id) {
    for (final w in windows) {
      if (w.id == id) w.dragging = false;
    }
    notifyListeners();
  }

  void setFinderView(FinderView view) {
    for (final w in windows) {
      if (w.id == 'finder') w.finderView = view;
    }
    notifyListeners();
  }

  void setGravity(bool on) {
    gravity = on;
    notifyListeners();
  }

  void toggleRenderDropdown() {
    renderDropdownOpen = !renderDropdownOpen;
    exploreOpen = false;
    notifyListeners();
  }

  void toggleExplore() {
    exploreOpen = !exploreOpen;
    renderDropdownOpen = false;
    notifyListeners();
  }

  void closeTransient() {
    if (!exploreOpen && !renderDropdownOpen) return;
    exploreOpen = false;
    renderDropdownOpen = false;
    notifyListeners();
  }

  void openOverlay(StudioOverlay value) {
    overlay = value;
    exploreOpen = false;
    renderDropdownOpen = false;
    notifyListeners();
  }

  void closeOverlay() {
    overlay = StudioOverlay.none;
    notifyListeners();
  }

  void togglePromptDrawer() {
    if (overlay == StudioOverlay.promptDrawer) {
      closeOverlay();
    } else {
      openOverlay(StudioOverlay.promptDrawer);
    }
  }

  /// Escape: closes the topmost thing — overlay, then menus, then the front
  /// window, then clears the selection.
  void escape() {
    if (overlay != StudioOverlay.none) {
      closeOverlay();
    } else if (exploreOpen || renderDropdownOpen) {
      closeTransient();
    } else if (topWindow != null) {
      close(topWindow!.id);
    } else {
      select(null);
    }
  }

  /// Validates the draft and starts a render. Returns false when the scene
  /// prompt is empty.
  bool submitPrompt() {
    final text = draft.prompt.text.trim();
    if (text.isEmpty) {
      draft.error.value = true;
      return false;
    }
    final seed = int.tryParse(draft.seed.text.trim()) ?? (100000 + math.Random().nextInt(899999));
    final form = PromptSpec(
      prompt: text,
      negative: draft.negative.text.trim(),
      resolution: draft.resolution.text.trim(),
      frameRate: draft.frameRate.text.trim(),
      solver: draft.solver.text.trim(),
      seed: seed,
      volumetric: draft.checks[0],
      denoise: draft.checks[1],
      exportExr: draft.checks[2],
    );
    final spec = form.withDna(form.compileDna());
    final jobId = 'job_${DateTime.now().microsecondsSinceEpoch}';
    final sent = engine.send(_renderPayload(spec, jobId));
    renderQueue.launch(spec, jobId: sent ? jobId : null);
    draft.reset();
    overlay = StudioOverlay.none;
    exploreOpen = false;
    renderDropdownOpen = true;
    notifyListeners();
    return true;
  }

  /// The `render` request for the engine: the form plus the inspector's
  /// live sliders (the XY pad writes turbulence as x, coherence as y).
  Map<String, Object?> _renderPayload(PromptSpec spec, String jobId) => {
        'type': 'render',
        'job_id': jobId,
        ...spec.toJson(),
        'params': {
          'turbulence': params.turbulence,
          'coherence': params.coherence,
          'density': params.density,
          'dispersion': params.dispersion,
          'time_scale': params.timeScale,
        },
      };

  void _onEngineState() => renderQueue.setEngineOnline(engine.isConnected);

  void _onEngineMessage(Map<String, dynamic> msg) {
    if (msg['type'] == 'telemetry') renderQueue.applyTelemetry(msg);
  }

  void _sendControl(String action) {
    engine.send({'type': 'control', 'action': action, 'job_id': renderQueue.jobId});
  }

  static const List<Offset> _slots = [
    Offset(0.64, 0.80),
    Offset(0.74, 0.77),
    Offset(0.31, 0.70),
    Offset(0.88, 0.78),
    Offset(0.40, 0.16),
    Offset(0.60, 0.15),
  ];

  /// A finished render becomes a new desktop node and opens in a viewport,
  /// taking the place of any earlier render viewport rather than stacking on
  /// top of it.
  void _onRenderComplete(PromptSpec spec) {
    renderDropdownOpen = false;
    final dna = spec.dna ?? spec.compileDna();
    final n = _generated++;
    final slot = _slots[n % _slots.length] + Offset(0.012, 0.012) * (n ~/ _slots.length).toDouble();
    final node = DesktopNode(
      id: 'gen_$n',
      label: '${spec.title}.vfx',
      kind: NodeKind.vfx,
      home: slot,
      sim: spec.sim,
      solver: spec.solver.isEmpty ? dna.label : spec.solver,
      blurb: spec.prompt,
      prompt: spec.prompt,
      params: spec.params(),
      seed: spec.seed,
      dna: dna,
      generated: true,
    );
    nodes.add(node);

    // Windows are ordered back to front, so the last match is the topmost.
    final earlier = [
      for (final w in windows)
        if (w.type == WindowType.viewport && (w.node?.generated ?? false)) w,
    ];
    windows.removeWhere(earlier.contains);
    final cascade = _cascade;
    openNode(node);
    if (earlier.isNotEmpty) {
      // Reuse the old window's slot so the new render appears where it was.
      _cascade = cascade;
      final w = topWindow!
        ..offset = earlier.last.offset
        ..maximized = earlier.last.maximized;
      if (viewport != Size.zero) w.clampOffset(viewport);
      notifyListeners();
    }
  }

  @override
  void dispose() {
    // Detach first: disposing the socket reports a final state change.
    _engineSub.cancel();
    engine.state.removeListener(_onEngineState);
    engine.dispose();
    renderQueue.dispose();
    draft.dispose();
    params.dispose();
    super.dispose();
  }
}

/// Exposes the [WorkspaceController] to the widget tree.
class WorkspaceScope extends InheritedNotifier<WorkspaceController> {
  const WorkspaceScope({
    super.key,
    required WorkspaceController controller,
    required super.child,
  }) : super(notifier: controller);

  /// Subscribes the caller to every workspace change.
  static WorkspaceController of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<WorkspaceScope>()!.notifier!;

  /// Reads the controller without subscribing (for callbacks).
  static WorkspaceController read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<WorkspaceScope>()!.notifier!;
}
