import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../models/desktop_node.dart';
import '../models/sim_params.dart';

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
  const RenderJob(this.name, this.device, this.vram, this.frames, this.sim);

  final String name;
  final String device;
  final int vram;
  final int frames;
  final SimKind sim;
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
  });

  final String prompt;
  final String negative;
  final String resolution;
  final String frameRate;
  final String solver;
  final int seed;
  final bool volumetric;
  final bool denoise;

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

  /// Called once when a user-launched render reaches 100%.
  void Function(PromptSpec spec)? onComplete;

  /// Live telemetry, drifting toward the active job's load.
  int vram = 78;
  int fps = 60;

  bool get hasUserJob => _user != null;
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
        _userProgress += _tickSeconds / userRenderSeconds;
        if (_userProgress >= 0.9999) {
          final spec = _spec!;
          _user = null;
          _spec = null;
          _userProgress = 0;
          notifyListeners();
          onComplete?.call(spec);
          return;
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
    fps = paused
        ? 0
        : (60 - (_user != null ? _userProgress * 6 : 0) - _rng.nextInt(4)).round();
    notifyListeners();
  }

  void togglePause() {
    paused = !paused;
    notifyListeners();
  }

  void skip() {
    if (_user != null) return;
    index = (index + 1) % jobs.length;
    _ambient = 0;
    notifyListeners();
  }

  void launch(PromptSpec spec) {
    _spec = spec;
    _user = RenderJob('${spec.title}.exr', 'Cloud GPU', 62, 240, spec.sim);
    _userProgress = 0;
    paused = false;
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
  WorkspaceController() {
    renderQueue.onComplete = _onRenderComplete;
  }

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
    final spec = PromptSpec(
      prompt: text,
      negative: draft.negative.text.trim(),
      resolution: draft.resolution.text.trim(),
      frameRate: draft.frameRate.text.trim(),
      solver: draft.solver.text.trim(),
      seed: seed,
      volumetric: draft.checks[0],
      denoise: draft.checks[1],
    );
    renderQueue.launch(spec);
    draft.reset();
    overlay = StudioOverlay.none;
    exploreOpen = false;
    renderDropdownOpen = true;
    notifyListeners();
    return true;
  }

  static const List<Offset> _slots = [
    Offset(0.64, 0.80),
    Offset(0.74, 0.77),
    Offset(0.31, 0.70),
    Offset(0.88, 0.78),
    Offset(0.40, 0.16),
    Offset(0.60, 0.15),
  ];

  /// A finished render becomes a new desktop node and opens in a viewport.
  void _onRenderComplete(PromptSpec spec) {
    final n = _generated++;
    final slot = _slots[n % _slots.length] + Offset(0.012, 0.012) * (n ~/ _slots.length).toDouble();
    final node = DesktopNode(
      id: 'gen_$n',
      label: '${spec.title}.vfx',
      kind: NodeKind.vfx,
      home: slot,
      sim: spec.sim,
      solver: spec.solver.isEmpty ? 'Photon Auto Solver' : spec.solver,
      blurb: spec.prompt,
      prompt: spec.prompt,
      params: spec.params(),
      seed: spec.seed,
      generated: true,
    );
    nodes.add(node);
    openNode(node);
  }

  @override
  void dispose() {
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
