import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/scene_asset.dart';
import '../models/studio_project.dart';
import '../services/render_socket.dart';
import '../theme/photon_theme.dart';

export '../models/studio_project.dart' show IntegratorMode, ProjectStatus, StudioProject, kDefaultProjects;

/// Definition of one scrubbable optics parameter.
@immutable
class OpticsParam {
  const OpticsParam({
    required this.id,
    required this.label,
    required this.min,
    required this.max,
    required this.initial,
    required this.format,
    this.integer = false,
    this.hint,
  });

  final String id;
  final String label;
  final double min;
  final double max;
  final double initial;
  final bool integer;

  /// Secondary caption shown under the label, e.g. `Crown Glass`.
  final String? hint;
  final String Function(double value) format;

  double clamp(double v) {
    final c = v.clamp(min, max).toDouble();
    return integer ? c.roundToDouble() : c;
  }
}

/// The six parameters on the optics deck, in display order.
final List<OpticsParam> kOpticsParams = [
  OpticsParam(
    id: 'aperture',
    label: 'Aperture',
    min: 1.0,
    max: 16.0,
    initial: 1.4,
    hint: 'DoF Bokeh',
    format: (v) => 'f/${v.toStringAsFixed(1)}',
  ),
  OpticsParam(
    id: 'focal_distance',
    label: 'Focal Distance',
    min: 0.2,
    max: 10.0,
    initial: 1.82,
    format: (v) => '${v.toStringAsFixed(2)}m',
  ),
  OpticsParam(
    id: 'ior',
    label: 'IOR',
    min: 1.0,
    max: 3.0,
    initial: 1.542,
    hint: 'Crown Glass / Liquid Metal',
    format: (v) => v.toStringAsFixed(3),
  ),
  OpticsParam(
    id: 'max_bounces',
    label: 'Max Bounces',
    min: 1,
    max: 32,
    initial: 12,
    integer: true,
    format: (v) => v.round().toString(),
  ),
  OpticsParam(
    id: 'samples_per_pixel',
    label: 'Samples Per Pixel',
    min: 16,
    max: 2048,
    initial: 256,
    integer: true,
    format: (v) => v.round().toString(),
  ),
  OpticsParam(
    id: 'caustics_energy',
    label: 'Caustics Energy',
    min: 0.0,
    max: 2.0,
    initial: 1.0,
    format: (v) => '${v.toStringAsFixed(2)}×',
  ),
];

/// The five spatial desktop nodes from the Stitch design.
const List<SceneAsset> kSceneAssets = [
  SceneAsset(
    name: 'LIQUID_GLASS',
    extension: 'ior',
    kind: SceneAssetKind.shader,
    subtitle: '.ior shader',
    icon: Icons.bubble_chart,
    badge: '1.54',
  ),
  SceneAsset(
    name: 'GOLD_ROUGH',
    extension: 'bsdf',
    kind: SceneAssetKind.material,
    subtitle: '.bsdf material',
    icon: Icons.circle,
    previewAsset: 'assets/images/gold_bsdf_sphere.jpg',
  ),
  SceneAsset(
    name: 'CAUSTIC_MESH',
    extension: 'usd',
    kind: SceneAssetKind.mesh,
    subtitle: '.usd 3D mesh',
    icon: Icons.view_in_ar,
    badge: 'USD',
  ),
  SceneAsset(
    name: 'HDRI_STUDIO',
    extension: '',
    kind: SceneAssetKind.light,
    subtitle: 'Dome Light',
    icon: Icons.wb_sunny,
    badge: '32K',
  ),
  SceneAsset(
    name: 'EXR_PASSES',
    extension: '',
    kind: SceneAssetKind.passes,
    subtitle: 'Multi-Layer',
    icon: Icons.layers,
    badge: '32b',
  ),
];

/// Single source of truth for the studio workspace.
///
/// Low-frequency state (theme, parameters, selection) notifies as a whole.
/// High-frequency state (incoming frames, sample counter, orbit, FPS) lives in
/// its own [ValueNotifier] so a 60 fps stream does not rebuild the workspace.
class StudioController extends ChangeNotifier {
  /// [now] replaces the wall clock for the idle-frame check (tests).
  StudioController({
    RenderSocket? socket,
    bool autoConnect = true,
    DateTime Function()? now,
  }) : socket = socket ?? RenderSocket(),
       _now = now ?? DateTime.now {
    for (final p in kOpticsParams) {
      _params[p.id] = p.initial;
    }
    // Launch inside the first project, silently (no toast, no socket traffic).
    _applyProject(kDefaultProjects.first);
    this.socket.link.addListener(_onLinkChanged);
    _messageSub = this.socket.messages.listen(handleMessage);
    _ensureTicking();
    if (autoConnect) this.socket.connect();
  }

  final RenderSocket socket;
  final DateTime Function() _now;
  late final StreamSubscription<Map<String, dynamic>> _messageSub;

  /// Drives convergence and the idle-frame check. It only exists while one of
  /// those has work left, so a converged, idle studio schedules no timers.
  Timer? _ticker;
  bool _disposed = false;

  void _ensureTicking() {
    if (_disposed) return;
    _ticker ??= Timer.periodic(const Duration(milliseconds: 100), (_) => _tick());
  }

  @visibleForTesting
  bool get tickerActive => _ticker != null;

  @visibleForTesting
  void debugTick() => _tick();

  // --- Theme -----------------------------------------------------------

  /// Dark Studio is the default; Daylight Lab is the alternate.
  bool _darkGrading = true;
  bool get darkGrading => _darkGrading;
  PhotonPalette get palette => _darkGrading ? PhotonPalette.grading : PhotonPalette.daylight;

  void setDarkGrading(bool value) {
    if (_darkGrading == value) return;
    _darkGrading = value;
    notifyListeners();
  }

  // --- Link & frames ---------------------------------------------------

  RenderLink get link => socket.link.value;

  /// Latest decoded engine frame. It stays on screen when the stream goes
  /// quiet; only a lost link or [resetFrames] clears it.
  final ValueNotifier<Uint8List?> frame = ValueNotifier(null);

  /// Unfiltered Monte Carlo pass, when the engine sends `raw_frame`.
  final ValueNotifier<Uint8List?> rawFrame = ValueNotifier(null);

  /// Measured arrival rate of engine frames; decays to 0 when they stop.
  final ValueNotifier<double> fps = ValueNotifier(0);

  DateTime? _lastFrameAt;
  static const _idleAfter = Duration(seconds: 3);

  void _onLinkChanged() {
    if (socket.link.value != RenderLink.live) resetFrames();
    notifyListeners();
  }

  /// Drops every held frame so the viewport falls back to the preview render.
  void resetFrames() {
    frame.value = null;
    rawFrame.value = null;
    fps.value = 0;
    _lastFrameAt = null;
  }

  /// Applies one decoded engine message (`frame`, `raw_frame`). The socket
  /// feeds this; tests call it directly.
  void handleMessage(Map<String, dynamic> data) {
    final raw = _decodeImage(data['raw_frame']);
    if (raw != null) rawFrame.value = raw;

    final bytes = _decodeImage(data['frame']);
    if (bytes == null) return;
    final now = _now();
    final last = _lastFrameAt;
    if (last != null) {
      final dt = now.difference(last).inMicroseconds;
      if (dt > 0) {
        final inst = 1e6 / dt;
        fps.value = fps.value == 0 ? inst : fps.value * 0.85 + inst * 0.15;
      }
    }
    _lastFrameAt = now;
    frame.value = bytes;
    _ensureTicking();
  }

  Uint8List? _decodeImage(Object? value) {
    if (value is! String) return null;
    try {
      return base64Decode(value);
    } on FormatException catch (e) {
      debugPrint('StudioController: dropped undecodable image ($e)');
      return null;
    }
  }

  // --- Parameters ------------------------------------------------------

  final Map<String, double> _params = {};
  double param(String id) => _params[id]!;

  OpticsParam _def(String id) => kOpticsParams.firstWhere((p) => p.id == id);

  void setParam(String id, double value) {
    final v = _def(id).clamp(value);
    if (_params[id] == v) return;
    _params[id] = v;
    _syncActiveProject();
    _restartConvergence();
    socket.send({'param': id, 'value': v});
    notifyListeners();
  }

  int get targetSamples => param('samples_per_pixel').round();
  int get maxBounces => param('max_bounces').round();

  // --- Convergence (local estimate) -----------------------------------

  /// Samples accumulated so far, from a local estimate that restarts whenever
  /// the scene changes. It is not reported by the engine.
  final ValueNotifier<int> samples = ValueNotifier(0);
  double _samplesF = 0;

  double get convergence => (samples.value / targetSamples).clamp(0.0, 1.0);
  bool get converged => samples.value >= targetSamples;

  void _restartConvergence() {
    _samplesF = 0;
    samples.value = 0;
    _ensureTicking();
  }

  void _tick() {
    final target = targetSamples;
    if (_samplesF < target) {
      // Exponential approach with a floor so the last samples still land.
      final step = math.max(0.8, (target - _samplesF) * 0.035);
      _samplesF = math.min(target.toDouble(), _samplesF + step);
      samples.value = _samplesF >= target - 0.5 ? target : _samplesF.floor();
    }
    final last = _lastFrameAt;
    if (last != null && _now().difference(last) > _idleAfter) {
      // The stream went quiet. The last frame is a finished render and stays
      // on screen; only the measured rate is stale.
      fps.value = 0;
      _lastFrameAt = null;
    }
    if (_samplesF >= target && _lastFrameAt == null) {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  // --- Viewport interaction -------------------------------------------

  /// Accumulated orbit, used for the fallback render's parallax.
  final ValueNotifier<Offset> orbit = ValueNotifier(Offset.zero);

  void orbitBy(double dx, double dy) {
    final o = orbit.value;
    orbit.value = Offset(
      (o.dx + dx).clamp(-240.0, 240.0).toDouble(),
      (o.dy + dy).clamp(-240.0, 240.0).toDouble(),
    );
    _restartConvergence();
    socket.send({'orbit_dx': dx, 'orbit_dy': dy});
  }

  /// Recenters the camera.
  void resetOrbit() {
    orbit.value = Offset.zero;
    _restartConvergence();
    socket.send({'orbit_reset': true});
  }

  // --- Viewport tools --------------------------------------------------

  bool _abWipeEnabled = true;
  bool get abWipeEnabled => _abWipeEnabled;

  void setAbWipeEnabled(bool value) {
    if (_abWipeEnabled == value) return;
    _abWipeEnabled = value;
    notifyListeners();
  }

  /// Curtain position for the A/B wipe, as a fraction of the stage width.
  final ValueNotifier<double> abSplit = ValueNotifier(0.5);

  void setAbSplit(double value) => abSplit.value = value.clamp(0.05, 0.95).toDouble();

  void resetAbSplit() => abSplit.value = 0.5;

  bool _falseColorEnabled = false;
  bool get falseColorEnabled => _falseColorEnabled;

  void setFalseColor(bool value) {
    if (_falseColorEnabled == value) return;
    _falseColorEnabled = value;
    notifyListeners();
  }

  void toggleFalseColor() => setFalseColor(!_falseColorEnabled);

  bool _loupeEnabled = false;
  bool get loupeEnabled => _loupeEnabled;

  void setLoupe(bool value) {
    if (_loupeEnabled == value) return;
    _loupeEnabled = value;
    notifyListeners();
  }

  void toggleLoupe() => setLoupe(!_loupeEnabled);

  /// Pointer position over the stage, normalized to 0..1; null when the
  /// pointer is elsewhere.
  final ValueNotifier<Offset?> probePosition = ValueNotifier(null);

  // --- Assets ----------------------------------------------------------

  String? _selectedAsset;
  String? get selectedAsset => _selectedAsset;

  SceneAsset? _loadedAsset;
  SceneAsset? get loadedAsset => _loadedAsset;

  void selectAsset(String? fileName) {
    if (_selectedAsset == fileName) return;
    _selectedAsset = fileName;
    notifyListeners();
  }

  /// Handles an asset dropped on the viewport.
  void loadAsset(String fileName) {
    // A dragged project card carries its id; route it to the project loader.
    if (_projects.any((p) => p.id == fileName)) {
      selectProject(fileName);
      return;
    }
    final asset = kSceneAssets.where((a) => a.fileName == fileName).firstOrNull;
    if (asset == null) {
      showToast('Unknown asset: $fileName');
      return;
    }
    _loadedAsset = asset;
    _selectedAsset = fileName;
    _restartConvergence();
    final sent = socket.send({'load_asset': asset.fileName, 'kind': asset.kind.name});
    showToast(sent ? 'LOADED ${asset.fileName}' : 'STAGED ${asset.fileName} · ENGINE OFFLINE');
    notifyListeners();
  }

  // --- Prompt & export -------------------------------------------------

  /// Returns true when the prompt reached the engine.
  bool sendPrompt(String text) {
    final prompt = text.trim();
    if (prompt.isEmpty) {
      showToast('DESCRIBE A SCENE FIRST');
      return false;
    }
    final sent = socket.send({'prompt': prompt});
    _restartConvergence();
    showToast(sent ? 'PROMPT DISPATCHED' : 'ENGINE OFFLINE · PROMPT NOT SENT');
    return sent;
  }

  void exportExr() {
    final sent = socket.send({'action': 'export_exr'});
    showToast(sent ? 'EXR EXPORT REQUESTED' : 'ENGINE OFFLINE · EXPORT UNAVAILABLE');
  }

  // --- Projects --------------------------------------------------------

  final List<StudioProject> _projects = List.of(kDefaultProjects);
  String _activeProjectId = kDefaultProjects.first.id;
  int _projectSeq = kDefaultProjects.length;

  List<StudioProject> get projects => List.unmodifiable(_projects);
  String get activeProjectId => _activeProjectId;

  StudioProject? get activeProject => _projects.where((p) => p.id == _activeProjectId).firstOrNull;

  /// Loads [p]'s parameters and integrator and restarts convergence.
  void _applyProject(StudioProject p) {
    for (final def in kOpticsParams) {
      final v = p.params[def.id];
      if (v != null) _params[def.id] = def.clamp(v);
    }
    _integrator = p.integrator;
    _activeProjectId = p.id;
    _restartConvergence();
  }

  /// Writes the live parameters back into the active project, so switching
  /// away and returning does not lose edits.
  void _syncActiveProject() {
    final i = _projects.indexWhere((p) => p.id == _activeProjectId);
    if (i < 0) return;
    _projects[i] = _projects[i].copyWith(
      params: Map<String, double>.of(_params),
      integrator: _integrator,
      updatedAt: 'just now',
    );
  }

  void selectProject(String id) {
    final project = _projects.where((p) => p.id == id).firstOrNull;
    if (project == null) {
      showToast('UNKNOWN PROJECT');
      return;
    }
    _applyProject(project);
    socket.send({'load_project': id, 'params': Map<String, double>.of(_params)});
    showToast('PROJECT LOADED · ${project.name}');
    notifyListeners();
  }

  /// Snapshots the current studio parameters into a new draft and selects it.
  void createNewProject([String? name]) {
    _projectSeq++;
    final trimmed = name?.trim() ?? '';
    final title = trimmed.isEmpty ? 'UNTITLED_${_projectSeq.toString().padLeft(2, '0')}' : trimmed;
    final slug = title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    final project = StudioProject(
      id: '${slug}_$_projectSeq',
      name: title,
      code: 'PRJ-${_projectSeq.toString().padLeft(2, '0')}',
      sceneType: 'Custom Scene',
      subtitle: '.pht · ${_integrator.solverCaption}',
      updatedAt: 'just now',
      status: ProjectStatus.draft,
      previewAsset: 'assets/images/caustic_wave.jpg',
      params: Map<String, double>.of(_params),
      integrator: _integrator,
    );
    _projects.insert(0, project);
    _activeProjectId = project.id;
    showToast('PROJECT CREATED · $title');
    notifyListeners();
  }

  void duplicateProject(String id) {
    final source = _projects.where((p) => p.id == id).firstOrNull;
    if (source == null) return;
    _projectSeq++;
    final copy = source.copyWith(
      id: '${source.id}_copy_$_projectSeq',
      name: '${source.name}_COPY',
      code: 'PRJ-${_projectSeq.toString().padLeft(2, '0')}',
      status: ProjectStatus.draft,
      updatedAt: 'just now',
    );
    _projects.insert(_projects.indexOf(source) + 1, copy);
    showToast('PROJECT DUPLICATED · ${copy.name}');
    notifyListeners();
  }

  void deleteProject(String id) {
    final project = _projects.where((p) => p.id == id).firstOrNull;
    if (project == null) return;
    if (_projects.length == 1) {
      showToast('KEEP AT LEAST ONE PROJECT');
      return;
    }
    _projects.remove(project);
    if (id == _activeProjectId) {
      final next = _projects.first;
      _applyProject(next);
      socket.send({'load_project': next.id, 'params': Map<String, double>.of(_params)});
    }
    showToast('PROJECT DELETED · ${project.name}');
    notifyListeners();
  }

  // --- Integrator & bounces -------------------------------------------

  IntegratorMode _integrator = IntegratorMode.unidirectional;
  IntegratorMode get integrator => _integrator;

  void setIntegrator(IntegratorMode mode) {
    _integrator = mode;
    _syncActiveProject();
    _restartConvergence();
    socket.send({'integrator': mode.name});
    showToast('INTEGRATOR · ${mode.label}');
    notifyListeners();
  }

  void cycleIntegrator() => setIntegrator(_integrator.next);

  static const List<int> _bounceSteps = [4, 8, 12, 16, 24, 32];

  /// Steps `max_bounces` through 4, 8, 12, 16, 24, 32 and wraps.
  void cycleMaxBounces() {
    final next = _bounceSteps.firstWhere((s) => s > maxBounces, orElse: () => _bounceSteps.first);
    setParam('max_bounces', next.toDouble());
  }

  void nudgeMaxBounces(int delta) => setParam('max_bounces', (maxBounces + delta).toDouble());

  // --- Panel windows ---------------------------------------------------

  bool _viewportCollapsed = false;
  bool _opticsCollapsed = false;
  String? _maximizedPanel;

  bool get viewportCollapsed => _viewportCollapsed;
  bool get opticsCollapsed => _opticsCollapsed;

  /// `'viewport'`, `'optics'`, or null for the normal split.
  String? get maximizedPanel => _maximizedPanel;

  void toggleViewportCollapsed() {
    _viewportCollapsed = !_viewportCollapsed;
    notifyListeners();
  }

  void toggleOpticsCollapsed() {
    _opticsCollapsed = !_opticsCollapsed;
    notifyListeners();
  }

  void toggleMaximizedPanel(String panelId) => setMaximizedPanel(_maximizedPanel == panelId ? null : panelId);

  /// Maximizing a panel also expands it, so the two states never fight.
  void setMaximizedPanel(String? panelId) {
    _maximizedPanel = panelId;
    if (panelId == 'viewport') _viewportCollapsed = false;
    if (panelId == 'optics') _opticsCollapsed = false;
    notifyListeners();
  }

  /// Optics window, red pip.
  void resetAllParams() {
    for (final p in kOpticsParams) {
      _params[p.id] = p.initial;
      socket.send({'param': p.id, 'value': p.initial});
    }
    _syncActiveProject();
    _restartConvergence();
    showToast('OPTICS RESET TO DEFAULT');
    notifyListeners();
  }

  /// Viewport window, red pip.
  void resetViewportStage() {
    resetOrbit();
    resetAbSplit();
    _falseColorEnabled = false;
    _loupeEnabled = false;
    showToast('VIEWPORT RESET');
    notifyListeners();
  }

  // --- Toast -----------------------------------------------------------

  final ValueNotifier<String?> toast = ValueNotifier(null);
  Timer? _toastTimer;

  void showToast(String message) {
    toast.value = message;
    _toastTimer?.cancel();
    _toastTimer = Timer(const Duration(milliseconds: 2400), () => toast.value = null);
  }

  @override
  void dispose() {
    _disposed = true;
    _ticker?.cancel();
    _ticker = null;
    _toastTimer?.cancel();
    _messageSub.cancel();
    socket.link.removeListener(_onLinkChanged);
    socket.dispose();
    frame.dispose();
    rawFrame.dispose();
    fps.dispose();
    samples.dispose();
    orbit.dispose();
    abSplit.dispose();
    probePosition.dispose();
    toast.dispose();
    super.dispose();
  }
}

/// Exposes the [StudioController] to the widget tree.
class StudioScope extends InheritedNotifier<StudioController> {
  const StudioScope({super.key, required StudioController controller, required super.child})
    : super(notifier: controller);

  /// Subscribes the caller to low-frequency controller changes.
  static StudioController of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<StudioScope>()!.notifier!;

  /// Reads the controller without rebuilding on change.
  static StudioController read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<StudioScope>()!.notifier!;
}
