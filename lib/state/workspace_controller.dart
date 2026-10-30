import 'dart:async';

import 'package:flutter/widgets.dart';

import '../models/desktop_node.dart';

enum WindowType { viewport, compositor, inspector, finder }

enum StudioOverlay { none, promptDrawer, about, archive }

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
}

class RenderJob {
  const RenderJob(this.name, this.device, this.vram, this.frames, this.sim);

  final String name;
  final String device;
  final int vram;
  final int frames;
  final SimKind sim;
}

/// Background render queue shown in the top-right pill.
class RenderQueue extends ChangeNotifier {
  RenderQueue() {
    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) => _tick());
  }

  late final Timer _timer;

  final List<RenderJob> jobs = [
    const RenderJob('Volumetric Shockwave_v4.exr', 'CUDA GPU', 78, 240, SimKind.fog),
    const RenderJob('Liquid Chrome Bloom_v2.exr', 'Vulkan Compute', 64, 180, SimKind.chrome),
    const RenderJob('Nanobot Dissolve_v7.mp4', 'CUDA GPU', 71, 300, SimKind.swarm),
    const RenderJob('Caustic Pool Loop_v1.exr', 'Cloud Cluster', 52, 120, SimKind.caustics),
  ];

  int index = 0;
  double progress = 0.37;
  bool paused = false;

  RenderJob get current => jobs[index];
  int get frame => (progress * current.frames).floor();
  Duration get eta {
    final remaining = (1 - progress) * current.frames;
    return Duration(seconds: (remaining * 0.8).round());
  }

  void _tick() {
    if (paused) return;
    progress += 0.0011;
    if (progress >= 1) {
      progress = 0;
      index = (index + 1) % jobs.length;
    }
    notifyListeners();
  }

  void togglePause() {
    paused = !paused;
    notifyListeners();
  }

  void skip() {
    index = (index + 1) % jobs.length;
    progress = 0;
    notifyListeners();
  }

  void launch(String prompt, SimKind sim) {
    final slug = prompt.trim().isEmpty
        ? 'Untitled Prompt'
        : prompt.trim().split(RegExp(r'\s+')).take(3).join(' ');
    jobs.insert(0, RenderJob('${slug}_v1.exr', 'Cloud GPU', 69, 240, sim));
    index = 0;
    progress = 0;
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
  final RenderQueue renderQueue = RenderQueue();

  String? selectedId;
  final List<OpenWindow> windows = [];
  bool gravity = false;
  bool renderDropdownOpen = false;
  bool exploreOpen = false;
  StudioOverlay overlay = StudioOverlay.none;
  int _cascade = 0;

  OpenWindow? get topWindow => windows.isEmpty ? null : windows.last;

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
        size: compositor ? const Size(980, 600) : const Size(780, 660),
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
      if (w.id == id) {
        if (w.maximized) w.maximized = false;
        w.offset += delta;
        w.dragging = true;
      }
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

  void launchRender(String prompt, SimKind sim) {
    renderQueue.launch(prompt, sim);
    overlay = StudioOverlay.none;
    renderDropdownOpen = true;
    notifyListeners();
  }

  @override
  void dispose() {
    renderQueue.dispose();
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
