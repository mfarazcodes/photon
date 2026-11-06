import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart';

import '../models/prompt_result.dart';
import '../models/render_snapshot.dart';
import '../models/scene_asset.dart';
import '../models/studio_account.dart';
import '../models/studio_project.dart';
import '../services/file_dialog.dart';
import '../services/render_socket.dart';
import '../theme/photon_theme.dart';

export '../models/hero_chapter.dart';
export '../models/prompt_result.dart' show PromptExecutionResult, PromptResultKind, RollerCell;
export '../models/render_snapshot.dart' show RenderSnapshot;
export '../models/studio_account.dart';
export '../models/studio_project.dart'
    show IntegratorMode, ProceduralSceneKind, ProjectStatus, StudioProject, kDefaultProjects;

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

/// PHOTON LUMEN-1, the neural ray-tracing and light-transport model, in three
/// tiers. A tier is a preset: sample count, bounce depth and integrator.
///
/// The display name is [name] (which shadows the built-in enum `name`); the
/// stable identifier, `lite` / `quick` / `pro`, is [id].
enum PhotonModelTier {
  lite(
    'PHOTON LUMEN · LITE',
    'LITE',
    'LUMEN LITE',
    'Neural Draft · 64 SPP · 4 Bounces',
    '64 SPP · 4 Bounces · Sub-8ms Viewport',
    64,
    4,
    IntegratorMode.unidirectional,
    Color(0xFF22D3EE),
  ),
  quick(
    'PHOTON LUMEN · QUICK',
    'QUICK',
    'LUMEN QUICK',
    'ReSTIR Interactive · 256 SPP · 12 Bounces',
    '256 SPP · 12 Bounces · Real-Time OIDN',
    256,
    12,
    IntegratorMode.restir,
    Color(0xFF8A2BE2),
  ),
  pro(
    'PHOTON LUMEN · PRO',
    'PRO',
    'LUMEN PRO',
    'Full Spectral BiDir + SPPM · 1024 SPP · 24 Bounces',
    '1024 SPP · 24 Bounces · Spectral Cauchy',
    1024,
    24,
    IntegratorMode.sppm,
    Color(0xFFFF2D78),
  );

  const PhotonModelTier(
    this.name,
    this.shortTag,
    this.title,
    this.spec,
    this.detail,
    this.defaultSpp,
    this.defaultBounces,
    this.defaultIntegrator,
    this.accent,
  );

  /// The model's id on the engine socket.
  static const String modelId = 'photon_lumen_1';

  /// `PHOTON LUMEN · QUICK`.
  final String name;

  /// The badge on the processor button.
  final String shortTag;

  /// The card title in the selector (`LUMEN QUICK`).
  final String title;

  /// One-line spec (`ReSTIR Interactive · 256 SPP · 12 Bounces`).
  final String spec;

  /// The card's detail line.
  final String detail;
  final int defaultSpp;
  final int defaultBounces;
  final IntegratorMode defaultIntegrator;
  final Color accent;

  /// `lite`, `quick` or `pro`: the Dart enum name that [name] shadows.
  String get id => EnumName(this).name;
}

/// Single source of truth for the studio workspace.
///
/// Low-frequency state (theme, parameters, selection) notifies as a whole.
/// High-frequency state (incoming frames, sample counter, orbit, FPS) lives in
/// its own [ValueNotifier] so a 60 fps stream does not rebuild the workspace.
class StudioController extends ChangeNotifier {
  /// [now] replaces the wall clock for the idle-frame check and undo
  /// coalescing (tests). [animateShader] false freezes the live procedural
  /// scenes at a fixed phase, so tests never wait on a free-running ticker.
  ///
  /// [startInLandingPage] opens the full-bleed landing page over the workspace
  /// (the app does, via [PhotonApp]; tests land in the workspace). [startInDeckView] shows the project
  /// sidebar as a stacked deck instead of a list.
  StudioController({
    RenderSocket? socket,
    bool autoConnect = true,
    DateTime Function()? now,
    bool animateShader = true,
    bool startInLandingPage = false,
    bool startInDeckView = false,
  }) : socket = socket ?? RenderSocket(),
       _now = now ?? DateTime.now,
       _showLaunchPortal = startInLandingPage,
       _inStudioWorkspace = !startInLandingPage,
       _deckView = startInDeckView,
       _autoConnect = autoConnect,
       // A private field cannot be a named parameter, so this stays an assignment.
       // ignore: prefer_initializing_formals
       _animateShader = animateShader {
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

  /// Whether this studio keeps a link to the engine. Off, the engine address
  /// can still be changed but nothing connects.
  final bool _autoConnect;
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

  static const MethodChannel _windowChannel = MethodChannel('photon/window');

  void setDarkGrading(bool value) {
    if (_darkGrading == value) return;
    _darkGrading = value;
    _syncNativeTheme(value);
    notifyListeners();
  }

  /// Repaints the native window caption to match the studio theme. Only the
  /// Windows runner implements this; anywhere else (and in tests) the call
  /// simply has no listener, which is fine.
  void _syncNativeTheme(bool dark) {
    try {
      _windowChannel.invokeMethod<void>('setDarkTheme', dark).catchError((_) {});
    } catch (_) {
      // No platform channel available.
    }
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
    _recordUndo(id);
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
    _advanceUpload();
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
    if (_samplesF >= target && _lastFrameAt == null && !_isUploading) {
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

  // --- Live shader, ray overlay, optics probe -------------------------

  bool _liveShaderEnabled = false;

  /// Shows the real-time procedural simulation instead of the still render.
  /// Projects open in their own default (see [StudioProject.isDynamic]); the
  /// viewport toggle then overrides it for any project.
  bool get liveShaderEnabled => _liveShaderEnabled;

  void setLiveShader(bool value) {
    if (_liveShaderEnabled == value) return;
    _liveShaderEnabled = value;
    notifyListeners();
  }

  void toggleLiveShader() => setLiveShader(!_liveShaderEnabled);

  bool _animateShader;

  /// False pins the live scenes to one fixed phase (play/pause, and tests).
  bool get animateShader => _animateShader;

  void setAnimateShader(bool value) {
    if (_animateShader == value) return;
    _animateShader = value;
    notifyListeners();
  }

  bool _bvhOverlayEnabled = false;
  bool get bvhOverlayEnabled => _bvhOverlayEnabled;

  void setBvhOverlay(bool value) {
    if (_bvhOverlayEnabled == value) return;
    _bvhOverlayEnabled = value;
    notifyListeners();
  }

  void toggleBvhOverlay() => setBvhOverlay(!_bvhOverlayEnabled);

  /// Probe wavelength, nm. 380 (violet) to 700 (red).
  double _wavelengthNm = 540.0;
  double get wavelengthNm => _wavelengthNm;

  /// Named stops the probe steps through: violet, blue, emerald, sodium
  /// yellow, laser red.
  static const List<double> wavelengthStops = [380, 470, 540, 590, 650];

  void setWavelengthNm(double nm) {
    final v = nm.clamp(380.0, 700.0).toDouble();
    if (v == _wavelengthNm) return;
    _wavelengthNm = v;
    notifyListeners();
  }

  /// Jumps to the next named stop (wrapping after the red).
  void stepWavelength() {
    final next = wavelengthStops.firstWhere((s) => s > _wavelengthNm + 0.5, orElse: () => wavelengthStops.first);
    setWavelengthNm(next);
  }

  /// Camera zoom, 0.5x to 4x.
  final ValueNotifier<double> cameraZoom = ValueNotifier(1.0);

  void setCameraZoom(double zoom) => cameraZoom.value = zoom.clamp(0.5, 4.0).toDouble();

  void resetCameraZoom() => cameraZoom.value = 1.0;

  /// Where the optics are focused, normalized to the stage. Center by default.
  final ValueNotifier<Offset> focusPoint = ValueNotifier(const Offset(0.5, 0.5));

  /// Moves the focus to [uv] and pulls `focal_distance` to match its depth.
  ///
  /// Depth here is a stand-in for the scene's depth buffer: points higher in
  /// the frame are treated as farther from the camera (0.4m at the bottom edge
  /// to 5.0m at the top).
  void setFocusPoint(Offset uv) {
    final p = Offset(uv.dx.clamp(0.0, 1.0).toDouble(), uv.dy.clamp(0.0, 1.0).toDouble());
    focusPoint.value = p;
    setParam('focal_distance', 0.4 + (1 - p.dy) * 4.6);
    _restartConvergence();
  }

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

  /// Sends [text] to the engine and applies what it asks for locally, so the
  /// studio visibly responds with the engine offline too (`f/2.8`, `ior 2.4`,
  /// `diamond`, `gold`, ...). Returns true when the prompt reached the engine.
  bool sendPrompt(String text) {
    final prompt = text.trim();
    if (prompt.isEmpty) {
      showToast('DESCRIBE A SCENE FIRST');
      return false;
    }
    final changes = _applyPromptIntent(PromptIntent.parse(prompt));
    final sent = socket.send({'prompt': prompt});
    _restartConvergence();
    _publishPromptResult(prompt: prompt, changes: changes, sent: sent);
    showToast(sent ? 'PROMPT DISPATCHED' : 'ENGINE OFFLINE · PROMPT NOT SENT');
    notifyListeners();
    return sent;
  }

  /// Writes one parameter without recording undo or notifying; the caller
  /// does both once for the whole batch. Returns whether it changed.
  bool _writeParam(String id, double value) {
    final v = _def(id).clamp(value);
    if (_params[id] == v) return false;
    _params[id] = v;
    socket.send({'param': id, 'value': v});
    return true;
  }

  /// Applies a parsed prompt as one undo step and returns labels for what
  /// changed, in the order the roller banner reads them.
  List<String> _applyPromptIntent(PromptIntent intent) {
    if (intent.isEmpty) return const [];
    _recordUndo(Object());
    final changes = <String>[];

    final project = _projects.where((p) => p.id == intent.projectId).firstOrNull;
    if (project != null && project.id != _activeProjectId) {
      _applyProject(project);
      socket.send({'load_project': project.id, 'params': Map<String, double>.of(_params)});
      changes.add('SCENE ${project.name}');
    }
    final mode = intent.integrator;
    if (mode != null && mode != _integrator) {
      _integrator = mode;
      socket.send({'integrator': mode.name});
      changes.add(mode.label);
    }

    String label(String id) => '${_def(id).label.toUpperCase()} ${_def(id).format(_params[id]!)}';
    for (final id in const ['ior']) {
      final v = intent.params[id];
      if (v != null && _writeParam(id, v)) changes.add(label(id));
    }
    final roughness = intent.roughness;
    if (roughness != null) changes.add('ROUGHNESS ${roughness.clamp(0.0, 1.0).toStringAsFixed(2)}');
    for (final id in const ['aperture', 'focal_distance', 'max_bounces']) {
      final v = intent.params[id];
      if (v != null && _writeParam(id, v)) changes.add(label(id));
    }
    final spp = intent.params['samples_per_pixel'];
    if (spp != null && _writeParam('samples_per_pixel', spp)) {
      changes.add('$targetSamples SPP');
    }
    _syncActiveProject();
    return changes;
  }

  // --- Prompt result banner -------------------------------------------

  PromptExecutionResult? _promptResult;
  int _resultSeq = 0;

  /// The latest prompt or ingest outcome, shown by the roller banner until it
  /// is dismissed.
  PromptExecutionResult? get promptResult => _promptResult;

  void _publishPromptResult({required String prompt, required List<String> changes, required bool sent}) {
    final spp = targetSamples;
    final parts = [...changes];
    if (!parts.any((c) => c.endsWith(' SPP'))) parts.add('$spp SPP');
    _promptResult = PromptExecutionResult(
      id: ++_resultSeq,
      kind: PromptResultKind.prompt,
      prompt: prompt,
      changes: changes,
      dispatched: sent,
      headline: changes.isEmpty ? 'PROMPT QUEUED · $spp SPP' : 'PROMPT APPLIED · ${parts.join(' · ')}',
      cells: [
        RollerCell('KERNEL', _integrator.solverCaption.toUpperCase()),
        RollerCell('SOLVER', 'MIS · ${maxBounces}B'),
        RollerCell('DELTA', changes.isEmpty ? 'Δ 0' : 'Δ ${changes.length}'),
        RollerCell('SPP', '$spp'),
        RollerCell('STATUS', sent ? 'DISPATCHED' : 'LOCAL'),
      ],
    );
  }

  void dismissPromptResult() {
    if (_promptResult == null) return;
    _promptResult = null;
    notifyListeners();
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
    _liveShaderEnabled = p.isDynamic;
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
    _recordUndo(Object());
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
      previewAsset: activeProject?.previewAsset ?? 'assets/images/caustic_wave.jpg',
      params: Map<String, double>.of(_params),
      integrator: _integrator,
      sceneKind: activeProject?.sceneKind ?? ProceduralSceneKind.causticWave,
      isDynamic: _liveShaderEnabled,
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
    _recordUndo(Object());
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
    // The account has one home: its console, over the workspace.
    if (panelId == 'account') {
      setAccountModalOpen(true);
      return;
    }
    _maximizedPanel = panelId;
    if (panelId == 'viewport') _viewportCollapsed = false;
    if (panelId == 'optics') _opticsCollapsed = false;
    notifyListeners();
  }

  /// Optics window, red pip.
  void resetAllParams() {
    _recordUndo(Object());
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
    _bvhOverlayEnabled = false;
    cameraZoom.value = 1.0;
    focusPoint.value = const Offset(0.5, 0.5);
    showToast('VIEWPORT RESET');
    notifyListeners();
  }

  // --- Undo / redo -----------------------------------------------------

  final List<_StudioState> _undoStack = [];
  final List<_StudioState> _redoStack = [];
  static const int _undoLimit = 60;
  static const Duration _undoCoalesce = Duration(milliseconds: 600);
  Object? _lastUndoKey;
  DateTime? _lastUndoAt;

  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;

  _StudioState _captureState() => _StudioState(
    params: Map<String, double>.of(_params),
    projectId: _activeProjectId,
    integrator: _integrator,
    modelTier: _modelTier,
  );

  /// Saves the state as it is now, ahead of a change. Consecutive changes to
  /// the same [key] inside [_undoCoalesce] (a scrub drag) share one entry.
  void _recordUndo(Object key) {
    final now = _now();
    final last = _lastUndoAt;
    final coalesce = _lastUndoKey == key && last != null && now.difference(last) < _undoCoalesce;
    _lastUndoKey = key;
    _lastUndoAt = now;
    if (coalesce) return;
    _undoStack.add(_captureState());
    if (_undoStack.length > _undoLimit) _undoStack.removeAt(0);
    _redoStack.clear();
  }

  void undo() {
    if (!canUndo) return;
    _redoStack.add(_captureState());
    _restore(_undoStack.removeLast());
    showToast('UNDO');
  }

  void redo() {
    if (!canRedo) return;
    _undoStack.add(_captureState());
    _restore(_redoStack.removeLast());
    showToast('REDO');
  }

  /// Puts the studio back into [s]. A project that has since been deleted is
  /// skipped; its parameters still apply to the current project.
  void _restore(_StudioState s) {
    _lastUndoKey = null;
    _params
      ..clear()
      ..addAll(s.params);
    _integrator = s.integrator;
    final tierChanged = s.modelTier != null && s.modelTier != _modelTier;
    _modelTier = s.modelTier ?? _modelTier;
    final project = _projects.where((p) => p.id == s.projectId).firstOrNull;
    if (project != null && project.id != _activeProjectId) {
      _activeProjectId = project.id;
      _liveShaderEnabled = project.isDynamic;
    }
    _syncActiveProject();
    _restartConvergence();
    socket.send({'load_project': _activeProjectId, 'params': Map<String, double>.of(_params)});
    if (tierChanged) socket.send({'model': PhotonModelTier.modelId, 'tier': _modelTier.id});
    notifyListeners();
  }

  // --- Snapshots (takes) ----------------------------------------------

  final List<RenderSnapshot> _snapshots = [];
  int _snapshotSeq = 0;

  List<RenderSnapshot> get snapshots => List.unmodifiable(_snapshots);

  /// Captures the current optics as the next `TAKE`.
  void captureSnapshot() {
    _snapshotSeq++;
    final label = 'TAKE ${_snapshotSeq.toString().padLeft(2, '0')}';
    _snapshots.add(
      RenderSnapshot(
        id: 'take_$_snapshotSeq',
        label: label,
        projectId: _activeProjectId,
        projectName: activeProject?.name ?? 'UNSAVED',
        params: Map<String, double>.of(_params),
        integrator: _integrator,
        timestamp: _now(),
      ),
    );
    showToast('SNAPSHOT · $label');
    notifyListeners();
  }

  /// Restores a take's exact optics (undoable).
  void restoreSnapshot(String id) {
    final take = _snapshots.where((s) => s.id == id).firstOrNull;
    if (take == null) return;
    _recordUndo(Object());
    _restore(_StudioState(params: take.params, projectId: take.projectId, integrator: take.integrator));
    showToast('TAKE RESTORED · ${take.label}');
  }

  // --- Account ---------------------------------------------------------

  StudioAccount _account = StudioAccount.initial();
  StudioAccount get account => _account;

  bool _accountModalOpen = false;
  bool get accountModalOpen => _accountModalOpen;

  void setAccountModalOpen(bool open) {
    if (_accountModalOpen == open) return;
    if (open) _closeOverlays();
    _accountModalOpen = open;
    notifyListeners();
  }

  void toggleAccountModal() => setAccountModalOpen(!_accountModalOpen);

  void setPlanTier(PlanTier tier) {
    _account = _account.copyWith(tier: tier);
    showToast('PLAN UPDATED · ${tier.label}');
    notifyListeners();
  }

  void setAuthMethod(AuthMethod method) {
    _account = _account.copyWith(authMethod: method);
    showToast('AUTH PROTOCOL · ${method.label}');
    notifyListeners();
  }

  void toggleTwoFactor() {
    final on = !_account.twoFactorEnabled;
    _account = _account.copyWith(twoFactorEnabled: on);
    showToast(on ? '2FA ENABLED' : '2FA DISABLED');
    notifyListeners();
  }

  void toggleHardwareKey() {
    final on = !_account.hardwareKeyBound;
    _account = _account.copyWith(hardwareKeyBound: on);
    showToast(on ? 'HARDWARE KEY BOUND' : 'HARDWARE KEY UNBOUND');
    notifyListeners();
  }

  int _keySeq = 0;

  /// A deterministic pseudo-random hex string (FNV-1a seeded LCG). The studio
  /// has no backend to mint real tokens, so keys are derived locally.
  static String _hex(String seed, int length) {
    var h = 0x811C9DC5;
    for (final unit in seed.codeUnits) {
      h ^= unit;
      h = (h * 0x01000193) & 0xFFFFFFFF;
    }
    final out = StringBuffer();
    while (out.length < length) {
      h = (h * 1664525 + 1013904223) & 0xFFFFFFFF;
      out.write(h.toRadixString(16).padLeft(8, '0'));
    }
    return out.toString().substring(0, length);
  }

  void rotateApiKey(String keyId) {
    final i = _account.apiKeys.indexWhere((k) => k.id == keyId);
    if (i < 0) return;
    final key = _account.apiKeys[i];
    final kind = key.prefix.split('_').take(2).join('_');
    final secret = '${kind}_${_hex('$keyId#${++_keySeq}', 32)}';
    final keys = List<ApiKeyRecord>.of(_account.apiKeys);
    keys[i] = key.copyWith(
      secret: secret,
      prefix: secret.substring(0, kind.length + 7),
      lastUsed: 'just now',
    );
    _account = _account.copyWith(apiKeys: keys);
    showToast('API KEY ROTATED');
    notifyListeners();
  }

  void createApiKey(String label) {
    final trimmed = label.trim();
    final id = 'key_new_${++_keySeq}';
    final secret = 'pht_usr_${_hex(id, 32)}';
    _account = _account.copyWith(
      apiKeys: [
        ..._account.apiKeys,
        ApiKeyRecord(
          id: id,
          label: trimmed.isEmpty ? 'Untitled Key' : trimmed,
          prefix: secret.substring(0, 14),
          secret: secret,
          created: 'today',
          lastUsed: 'never',
          scopes: const ['render:submit'],
        ),
      ],
    );
    showToast('API KEY CREATED');
    notifyListeners();
  }

  /// Signs out a remote session. The session this window runs in stays.
  void revokeSession(String sessionId) {
    final target = _account.sessions.where((s) => s.id == sessionId).firstOrNull;
    if (target == null || target.isCurrent) return;
    _account = _account.copyWith(
      sessions: _account.sessions.where((s) => s.id != sessionId).toList(),
    );
    showToast('SESSION REVOKED');
    notifyListeners();
  }

  void updateAccountProfile({String? displayName, String? organization, String? role}) {
    String? clean(String? v) => (v == null || v.trim().isEmpty) ? null : v.trim();
    _account = _account.copyWith(
      displayName: clean(displayName),
      organization: clean(organization),
      role: clean(role),
    );
    notifyListeners();
  }

  // --- Command palette -------------------------------------------------

  bool _commandPaletteOpen = false;
  bool get commandPaletteOpen => _commandPaletteOpen;

  void setCommandPaletteOpen(bool open) {
    if (_commandPaletteOpen == open) return;
    if (open) _closeOverlays();
    _commandPaletteOpen = open;
    notifyListeners();
  }

  void toggleCommandPalette() => setCommandPaletteOpen(!_commandPaletteOpen);

  // --- Landing page ----------------------------------------------------

  bool _showLaunchPortal;
  bool _inStudioWorkspace;

  /// True while the full-bleed landing page covers the workspace.
  bool get showLaunchPortal => _showLaunchPortal;

  /// True once the user has entered the studio window.
  bool get inStudioWorkspace => _inStudioWorkspace;

  /// Brings the landing page back (the header's SHOWCASE pill).
  void openLaunchPortal() {
    if (_showLaunchPortal) return;
    _showLaunchPortal = true;
    _inStudioWorkspace = false;
    _closeOverlays();
    notifyListeners();
  }

  /// Leaves the landing page for the studio. The page stops its own animation
  /// ticker as it goes, so nothing of it runs once the studio is up.
  void enterPhotonStudio() {
    if (_inStudioWorkspace && !_showLaunchPortal) return;
    _showLaunchPortal = false;
    _inStudioWorkspace = true;
    notifyListeners();
  }

  void dismissLaunchPortal() => enterPhotonStudio();

  void toggleLaunchPortal() => _showLaunchPortal ? enterPhotonStudio() : openLaunchPortal();

  /// Whether the live scenes should hold still: something sits over them.
  bool get sceneAnimationPaused =>
      _showLaunchPortal ||
      _accountModalOpen ||
      _commandPaletteOpen ||
      _ingestSheetOpen ||
      _exportModalOpen ||
      _modelPopoverOpen;

  /// Opening any overlay closes the others: one at a time.
  void _closeOverlays() {
    _accountModalOpen = false;
    _commandPaletteOpen = false;
    _ingestSheetOpen = false;
    _exportModalOpen = false;
    _modelPopoverOpen = false;
  }

  // --- File ingest & upload --------------------------------------------

  bool _ingestSheetOpen = false;
  bool get ingestSheetOpen => _ingestSheetOpen;

  void setIngestSheetOpen(bool open) {
    if (_ingestSheetOpen == open) return;
    if (open) _closeOverlays();
    _ingestSheetOpen = open;
    notifyListeners();
  }

  bool _isUploading = false;
  String? _uploadingFileName;
  double _uploadSizeMb = 0;
  double _uploadSeconds = 3;
  Timer? _uploadLingerTimer;
  bool _uploadLingering = false;

  /// Transfer progress (0..1) and the phase it is in. Each tick moves these
  /// two notifiers only, so the loader repaints at tick rate without the
  /// controller rebuilding the workspace; listeners are told once when the
  /// transfer starts and once when it finishes.
  final ValueNotifier<double> uploadProgressNotifier = ValueNotifier(0);
  final ValueNotifier<int> uploadPhaseNotifier = ValueNotifier(0);

  bool get isUploading => _isUploading;
  double get uploadProgress => uploadProgressNotifier.value;
  String? get uploadingFileName => _uploadingFileName;
  int get uploadPhaseIndex => uploadPhaseNotifier.value;
  double get uploadSizeMb => _uploadSizeMb;

  /// True while the loader should be on screen: during the transfer and for a
  /// moment after it, so 100% is seen.
  bool get uploadLoaderVisible => _isUploading || _uploadLingering;

  static const List<String> uploadPhases = [
    'PARSING USD SCENE GRAPH...',
    'BUILDING BVH OCTREE ACCELERATOR...',
    'COMPILING SPECTRAL BSDF SHADERS...',
    'CONVERGING FIRST LIGHT PASS...',
  ];

  String get uploadPhaseLabel => uploadPhases[uploadPhaseIndex];

  /// The phase [progress] (0..1) falls in.
  static int uploadPhaseFor(double progress) {
    if (progress < 0.25) return 0;
    if (progress < 0.55) return 1;
    if (progress < 0.85) return 2;
    return 3;
  }

  /// Starts ingesting [fileName]. Progress advances with the studio ticker;
  /// when it reaches 100% the asset joins the project list.
  void startFileUpload(String fileName, {double sizeMb = 48.5}) => _beginUpload(fileName, sizeMb);

  /// Image types the viewport can show as a still.
  static const Set<String> imageExtensions = {'png', 'jpg', 'jpeg', 'webp', 'bmp', 'gif'};

  // What the transfer in flight will attach to the project it creates.
  String? _pendingLocalPath;
  Uint8List? _pendingBytes;
  String? _pendingUrl;

  void _beginUpload(String fileName, double sizeMb, {String? localPath, Uint8List? bytes, String? url}) {
    if (_isUploading) {
      showToast('INGEST IN PROGRESS · $_uploadingFileName');
      return;
    }
    _pendingLocalPath = localPath;
    _pendingBytes = bytes;
    _pendingUrl = url;
    _uploadLingerTimer?.cancel();
    _uploadLingering = false;
    _isUploading = true;
    uploadProgressNotifier.value = 0;
    uploadPhaseNotifier.value = 0;
    _uploadingFileName = fileName;
    _uploadSizeMb = sizeMb;
    // Bigger files take longer; 2s to 5s.
    _uploadSeconds = (1.6 + sizeMb / 40).clamp(2.0, 5.0).toDouble();
    _ingestSheetOpen = false;
    _ensureTicking();
    notifyListeners();
  }

  /// Brings a file from disk into the studio. The name and size come from the
  /// path and [bytes] (or [sizeMb], or the file itself); the transfer runs the
  /// flux loader, and the project it creates keeps [filePath] and [bytes], so
  /// an image shows in the viewport as it is.
  void startLocalFileIngest({required String filePath, Uint8List? bytes, double? sizeMb}) {
    final path = filePath.trim();
    if (path.isEmpty) {
      showToast('CHOOSE A FILE FIRST');
      return;
    }
    final fileName = path.split(RegExp(r'[\\/]')).last;
    var mb = sizeMb ?? (bytes != null ? bytes.length / (1024 * 1024) : null);
    if (mb == null) {
      try {
        mb = File(path).lengthSync() / (1024 * 1024);
      } on FileSystemException {
        // Not on disk (yet): fall through to a nominal size.
      }
    }
    _beginUpload(fileName.isEmpty ? path : fileName, mb ?? 1.0, localPath: path, bytes: bytes);
  }

  /// Embeds a direct URL. `http` and `https` run the flux loader and create a
  /// project the viewport loads from that address; `ws` and `wss` point the
  /// engine link at that stream instead.
  void startUrlIngest(String rawUrl) {
    final url = rawUrl.trim();
    final uri = Uri.tryParse(url);
    const schemes = {'http', 'https', 'ws', 'wss'};
    if (url.isEmpty || uri == null || !schemes.contains(uri.scheme.toLowerCase()) || uri.host.isEmpty) {
      showToast('INVALID URL · USE HTTP/HTTPS/WS');
      return;
    }
    if (uri.scheme.toLowerCase().startsWith('ws')) {
      _ingestSheetOpen = false;
      socket.retarget(uri, reconnect: _autoConnect);
      showToast('STREAM LINKED · $url');
      notifyListeners();
      return;
    }
    final last = uri.pathSegments.isEmpty ? '' : uri.pathSegments.last;
    final fileName = last.isNotEmpty ? last : '${uri.host.replaceAll('.', '_')}.url';
    _beginUpload(fileName, 8.0, url: url);
  }

  void _advanceUpload() {
    if (!_isUploading) return;
    _setUploadProgress(uploadProgress + 0.1 / _uploadSeconds);
  }

  /// Jumps the transfer to [progress] (0..1). For tests; the ticker does the
  /// same in small steps.
  @visibleForTesting
  void advanceUploadForTest(double progress) => _setUploadProgress(progress);

  void _setUploadProgress(double progress) {
    if (!_isUploading) return;
    final p = progress.clamp(0.0, 1.0).toDouble();
    uploadProgressNotifier.value = p;
    uploadPhaseNotifier.value = uploadPhaseFor(p);
    // Mid-transfer ticks touch only the notifiers; the workspace is not
    // rebuilt. Finishing adds a project, so that one notifies.
    if (p >= 1.0) _finishUpload();
  }

  static const Map<String, String> _ingestSceneTypes = {
    'usd': 'USD Scene Graph',
    'exr': 'EXR Multi-Layer',
    'ior': 'IOR Shader',
    'bsdf': 'BSDF Material',
    'hdr': 'HDRI Dome Light',
    'obj': 'OBJ Mesh',
  };

  void _finishUpload() {
    final fileName = _uploadingFileName ?? 'UNTITLED.usd';
    _isUploading = false;
    uploadProgressNotifier.value = 1.0;
    uploadPhaseNotifier.value = uploadPhases.length - 1;
    _uploadLingering = true;
    _uploadLingerTimer?.cancel();
    _uploadLingerTimer = Timer(const Duration(milliseconds: 1400), () {
      _uploadLingering = false;
      notifyListeners();
    });

    final dot = fileName.lastIndexOf('.');
    final stem = (dot > 0 ? fileName.substring(0, dot) : fileName).toUpperCase();
    final ext = dot > 0 ? fileName.substring(dot + 1).toLowerCase() : 'usd';
    // A stable pick, so the same file always lands on the same look.
    final pick = fileName.codeUnits.fold<int>(0, (a, b) => a + b);
    final kind = ProceduralSceneKind.values[pick % ProceduralSceneKind.values.length];
    final preview = _ingestPreviews[pick % _ingestPreviews.length];

    // What came with the transfer, claimed now so the next one starts clean.
    final localPath = _pendingLocalPath;
    final bytes = _pendingBytes;
    final url = _pendingUrl;
    _pendingLocalPath = null;
    _pendingBytes = null;
    _pendingUrl = null;
    final isImage = imageExtensions.contains(ext);
    final remote = url != null;
    final host = remote ? Uri.parse(url).host : '';

    _projectSeq++;
    final project = StudioProject(
      id: '${stem.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_')}_$_projectSeq',
      name: stem,
      code: 'PRJ-${_projectSeq.toString().padLeft(2, '0')}',
      sceneType: remote
          ? (isImage ? 'Remote Image' : 'Remote Asset')
          : (isImage && localPath != null ? 'Local Image' : (_ingestSceneTypes[ext] ?? 'Imported Asset')),
      subtitle: remote ? '.$ext · $host' : '.$ext · ${_uploadSizeMb.toStringAsFixed(1)} MB',
      updatedAt: 'just now',
      status: ProjectStatus.draft,
      previewAsset: preview,
      params: Map<String, double>.of(_params),
      integrator: _integrator,
      sceneKind: kind,
      // An image, or anything embedded from a URL, is shown as the still it
      // is, not replaced by a simulation.
      isDynamic: !isImage && !remote && const {'usd', 'ior', 'obj'}.contains(ext),
      localFilePath: localPath,
      externalUrl: url,
      customBytes: bytes,
    );
    _projects.insert(0, project);
    selectProject(project.id);

    _promptResult = PromptExecutionResult(
      id: ++_resultSeq,
      kind: PromptResultKind.ingest,
      prompt: fileName,
      changes: ['+ $stem'],
      headline: 'ASSET INGESTED · $fileName · ${_uploadSizeMb.toStringAsFixed(1)} MB · $targetSamples SPP',
      cells: [
        RollerCell('KERNEL', '.${ext.toUpperCase()} IMPORT'),
        const RollerCell('SOLVER', 'BVH · OCTREE'),
        const RollerCell('DELTA', '+1 ASSET'),
        RollerCell('SPP', '$targetSamples'),
        const RollerCell('STATUS', 'INGESTED'),
      ],
    );
    showToast('ASSET INGESTED · $fileName');
    notifyListeners();
  }

  static const List<String> _ingestPreviews = [
    'assets/images/volumetric_prism.png',
    'assets/images/chrome_anisotropic.png',
    'assets/images/emerald_subsurface.png',
    'assets/images/blackhole_lensing.png',
    'assets/images/caustic_wave.jpg',
    'assets/images/gold_bsdf_sphere.jpg',
  ];

  // --- Photon model ----------------------------------------------------

  PhotonModelTier _modelTier = PhotonModelTier.quick;

  /// The PHOTON LUMEN-1 tier in use. Quick is the default.
  PhotonModelTier get modelTier => _modelTier;

  bool _modelPopoverOpen = false;
  bool get modelPopoverOpen => _modelPopoverOpen;

  void setModelPopoverOpen(bool open) {
    if (_modelPopoverOpen == open) return;
    if (open) _closeOverlays();
    _modelPopoverOpen = open;
    notifyListeners();
  }

  /// Switches tier and applies its preset: sample count, bounce depth and
  /// integrator (one undo step), tells the engine, and restarts convergence.
  void setModelTier(PhotonModelTier tier) {
    _recordUndo(Object());
    _modelTier = tier;
    _writeParam('samples_per_pixel', tier.defaultSpp.toDouble());
    _writeParam('max_bounces', tier.defaultBounces.toDouble());
    if (_integrator != tier.defaultIntegrator) {
      _integrator = tier.defaultIntegrator;
      socket.send({'integrator': _integrator.name});
    }
    _syncActiveProject();
    socket.send({'model': PhotonModelTier.modelId, 'tier': tier.id});
    _restartConvergence();
    _modelPopoverOpen = false;
    showToast('MODEL · ${tier.name}');
    notifyListeners();
  }

  /// Drops the engine link and opens a new one. A studio that was built not to
  /// connect (tests) only reports the address.
  void reconnectEngine() {
    if (_autoConnect) {
      socket.disconnect();
      socket.connect();
    }
    showToast('RECONNECTING · ${socket.uri}');
  }

  // --- Optical probe ---------------------------------------------------

  bool _probeVisible = true;

  /// Whether the focus probe (the ring and the wavelength readout) is drawn on
  /// the stage.
  bool get probeVisible => _probeVisible;

  void setProbeVisible(bool value) {
    if (_probeVisible == value) return;
    _probeVisible = value;
    notifyListeners();
  }

  void toggleProbeVisible() => setProbeVisible(!_probeVisible);

  // --- Local file picker -----------------------------------------------

  /// Replaces the native file dialog (tests).
  Future<String?> Function()? filePickerOverride;

  /// Asks the user for a file on disk: the native dialog on Windows, null
  /// anywhere it cannot be shown (cancelled, headless, other platforms).
  Future<String?> pickLocalFile() {
    final override = filePickerOverride;
    return override != null ? override() : pickLocalFileNative();
  }

  // --- Export ----------------------------------------------------------

  bool _exportModalOpen = false;
  String? _lastExportSummary;
  String? _stagedManifest;

  bool get exportModalOpen => _exportModalOpen;

  /// The path of the last file the export sheet wrote.
  String? get lastExportSummary => _lastExportSummary;

  /// The scene manifest staged by the last [exportExr].
  String? get stagedManifest => _stagedManifest;

  /// The viewport stage's repaint boundary, so a frame can be captured from it.
  final GlobalKey viewportCaptureKey = GlobalKey(debugLabel: 'viewport-capture');

  /// Where exports are written. The system temp directory unless overridden.
  Directory? exportDirectoryOverride;
  Directory get exportDirectory => exportDirectoryOverride ?? Directory.systemTemp;

  void setExportModalOpen(bool open) {
    if (_exportModalOpen == open) return;
    if (open) _closeOverlays();
    _exportModalOpen = open;
    notifyListeners();
  }

  /// Everything needed to reopen this scene: project, model tier, integrator,
  /// the six optics parameters, probe wavelength, camera, and the takes.
  Map<String, Object?> buildSceneManifest() {
    final project = activeProject;
    return {
      'schema': 'photon.scene/1',
      'exported_at': _now().toUtc().toIso8601String(),
      'project': {
        'id': _activeProjectId,
        'name': project?.name ?? 'UNSAVED',
        'code': project?.code,
        'scene_type': project?.sceneType,
        'scene_kind': project?.sceneKind.name,
        'dynamic': project?.isDynamic ?? false,
        'preview_asset': project?.previewAsset,
        'local_file': project?.localFilePath,
        'url': project?.externalUrl,
      },
      'model': {'id': PhotonModelTier.modelId, 'tier': _modelTier.id, 'name': _modelTier.name},
      'integrator': _integrator.name,
      'optics': {for (final p in kOpticsParams) p.id: _params[p.id]},
      'probe': {'wavelength_nm': _wavelengthNm, 'visible': _probeVisible},
      'camera': {
        'zoom': cameraZoom.value,
        'focus': {'x': focusPoint.value.dx, 'y': focusPoint.value.dy},
        'orbit': {'x': orbit.value.dx, 'y': orbit.value.dy},
      },
      'snapshots': [
        for (final s in _snapshots)
          {
            'id': s.id,
            'label': s.label,
            'project': s.projectId,
            'integrator': s.integrator.name,
            'params': s.params,
            'timestamp': s.timestamp.toUtc().toIso8601String(),
          },
      ],
    };
  }

  String get _manifestJson => const JsonEncoder.withIndent('  ').convert(buildSceneManifest());

  /// `EXPORT EXR`: asks the engine for the pass, stages the scene manifest, and
  /// opens the export sheet. It works with the engine offline too: the sheet
  /// can write the viewport frame and the manifest itself.
  void exportExr() {
    final name = activeProject?.name ?? 'SCENE';
    _stagedManifest = _manifestJson;
    final sent = socket.send({
      'action': 'export_exr',
      'project': _activeProjectId,
      'model_tier': _modelTier.id,
      'params': Map<String, double>.of(_params),
    });
    _closeOverlays();
    _exportModalOpen = true;
    showToast(sent ? 'EXR EXPORT REQUESTED · STUDIO MANIFEST READY' : 'EXPORT READY · $name.exr');
    notifyListeners();
  }

  static String _safeFileName(String name) => name.replaceAll(RegExp(r'[^A-Za-z0-9._\- ]+'), '_');

  String _exportPath(String fileName) => '${exportDirectory.path}${Platform.pathSeparator}$fileName';

  /// The picture to export when the stage cannot be captured: the active
  /// project's own image, re-encoded as PNG.
  Future<Uint8List> _projectImagePng() async {
    final project = activeProject;
    final Uint8List source;
    if (project?.customBytes != null) {
      source = project!.customBytes!;
    } else if (project?.localFilePath != null && File(project!.localFilePath!).existsSync()) {
      source = await File(project.localFilePath!).readAsBytes();
    } else {
      final data = await rootBundle.load(project?.previewAsset ?? 'assets/images/caustic_wave.jpg');
      source = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    }
    final codec = await ui.instantiateImageCodec(source);
    final frame = await codec.getNextFrame();
    final png = await frame.image.toByteData(format: ui.ImageByteFormat.png);
    frame.image.dispose();
    codec.dispose();
    return png!.buffer.asUint8List();
  }

  /// Writes the viewport frame as `<PROJECT>_4K_ACEScg.png`: the live stage,
  /// captured at up to 3840px wide, or the project's own image when the stage
  /// is not on screen. Returns the path, or null if it could not be written.
  Future<String?> exportFrame() async {
    final fileName = '${_safeFileName(activeProject?.name ?? 'SCENE')}_4K_ACEScg.png';
    try {
      Uint8List? png;
      final boundary = viewportCaptureKey.currentContext?.findRenderObject();
      if (boundary is RenderRepaintBoundary && boundary.hasSize && !boundary.size.isEmpty) {
        try {
          final image = await boundary.toImage(pixelRatio: (3840 / boundary.size.width).clamp(1.0, 4.0).toDouble());
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          image.dispose();
          png = data?.buffer.asUint8List();
        } catch (e) {
          debugPrint('StudioController: stage capture failed ($e); exporting the project image');
        }
      }
      png ??= await _projectImagePng();
      final path = _exportPath(fileName);
      await File(path).writeAsBytes(png);
      _lastExportSummary = path;
      showToast('EXPORTED · $fileName');
      notifyListeners();
      return path;
    } catch (e) {
      showToast('EXPORT FAILED · $e');
      return null;
    }
  }

  /// Writes `<PROJECT>.pht.json` and copies the manifest to the clipboard.
  /// Returns the path, or null if it could not be written.
  Future<String?> exportSceneManifest() async {
    final fileName = '${_safeFileName(activeProject?.name ?? 'SCENE')}.pht.json';
    final json = _manifestJson;
    final String path;
    try {
      path = _exportPath(fileName);
      await File(path).writeAsString(json);
    } catch (e) {
      showToast('EXPORT FAILED · $e');
      return null;
    }
    _stagedManifest = json;
    _lastExportSummary = path;
    try {
      await Clipboard.setData(ClipboardData(text: json));
      showToast('SCENE MANIFEST COPIED & SAVED');
    } catch (_) {
      showToast('MANIFEST SAVED · CLIPBOARD UNAVAILABLE');
    }
    notifyListeners();
    return path;
  }

  // --- Sidebar deck ----------------------------------------------------

  bool _deckView;

  /// True when the projects sidebar shows the stacked deck; false for the list.
  bool get deckView => _deckView;

  void setDeckView(bool value) {
    if (_deckView == value) return;
    _deckView = value;
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
    _uploadLingerTimer?.cancel();
    _messageSub.cancel();
    socket.link.removeListener(_onLinkChanged);
    socket.dispose();
    frame.dispose();
    rawFrame.dispose();
    fps.dispose();
    samples.dispose();
    orbit.dispose();
    cameraZoom.dispose();
    focusPoint.dispose();
    abSplit.dispose();
    probePosition.dispose();
    uploadProgressNotifier.dispose();
    uploadPhaseNotifier.dispose();
    toast.dispose();
    super.dispose();
  }
}

/// Everything an undo step restores: the optics, the integrator, the model
/// tier that set them, and which project they belong to.
@immutable
class _StudioState {
  const _StudioState({required this.params, required this.projectId, required this.integrator, this.modelTier});

  final Map<String, double> params;
  final String projectId;
  final IntegratorMode integrator;

  /// Null leaves the tier as it is (restoring a take does not change it).
  final PhotonModelTier? modelTier;
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
