import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/scene_asset.dart';
import '../services/render_socket.dart';
import '../theme/photon_theme.dart';

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
  StudioController({RenderSocket? socket, bool autoConnect = true})
    : socket = socket ?? RenderSocket() {
    for (final p in kOpticsParams) {
      _params[p.id] = p.initial;
    }
    this.socket.link.addListener(_onLinkChanged);
    _messageSub = this.socket.messages.listen(_onMessage);
    _ticker = Timer.periodic(const Duration(milliseconds: 100), (_) => _tick());
    if (autoConnect) this.socket.connect();
  }

  final RenderSocket socket;
  late final StreamSubscription<Map<String, dynamic>> _messageSub;
  late final Timer _ticker;

  // --- Theme -----------------------------------------------------------

  bool _darkGrading = false;
  bool get darkGrading => _darkGrading;
  PhotonPalette get palette => _darkGrading ? PhotonPalette.grading : PhotonPalette.daylight;

  void setDarkGrading(bool value) {
    if (_darkGrading == value) return;
    _darkGrading = value;
    notifyListeners();
  }

  // --- Link & frames ---------------------------------------------------

  RenderLink get link => socket.link.value;

  /// Latest decoded engine frame, or null when offline or idle.
  final ValueNotifier<Uint8List?> frame = ValueNotifier(null);

  /// Measured arrival rate of engine frames.
  final ValueNotifier<double> fps = ValueNotifier(0);

  DateTime? _lastFrameAt;
  static const _idleAfter = Duration(seconds: 3);

  void _onLinkChanged() {
    if (socket.link.value != RenderLink.live) _clearFrame();
    notifyListeners();
  }

  void _clearFrame() {
    frame.value = null;
    fps.value = 0;
    _lastFrameAt = null;
  }

  void _onMessage(Map<String, dynamic> data) {
    final raw = data['frame'];
    if (raw is! String) return;
    final Uint8List bytes;
    try {
      bytes = base64Decode(raw);
    } on FormatException catch (e) {
      debugPrint('StudioController: dropped undecodable frame ($e)');
      return;
    }
    final now = DateTime.now();
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
  }

  // --- Parameters ------------------------------------------------------

  final Map<String, double> _params = {};
  double param(String id) => _params[id]!;

  OpticsParam _def(String id) => kOpticsParams.firstWhere((p) => p.id == id);

  void setParam(String id, double value) {
    final v = _def(id).clamp(value);
    if (_params[id] == v) return;
    _params[id] = v;
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
    if (last != null && DateTime.now().difference(last) > _idleAfter) _clearFrame();
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
    _ticker.cancel();
    _toastTimer?.cancel();
    _messageSub.cancel();
    socket.link.removeListener(_onLinkChanged);
    socket.dispose();
    frame.dispose();
    fps.dispose();
    samples.dispose();
    orbit.dispose();
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
