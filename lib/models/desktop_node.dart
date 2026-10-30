import 'dart:ui';

/// Procedural shader previews. Each kind maps to a [VfxSim].
enum SimKind { liquid, swarm, chrome, fog, wireframe, cloth, caustics, marble, core }

enum NodeKind { vfx, frag, comp, obj, folder }

enum FinderView {
  workspace('Workspace'),
  presetVault('Preset Vault'),
  renderLibrary('Render Library'),
  recentPrompts('Recent Prompts'),
  localGpu('Local GPU Node'),
  cloudCluster('Cloud Cluster');

  const FinderView(this.title);
  final String title;
}

/// A file or folder that lives on the spatial desktop.
class DesktopNode {
  const DesktopNode({
    required this.id,
    required this.label,
    required this.kind,
    required this.home,
    this.sim,
    this.folderTag,
    this.tagColor,
    this.finderView,
    this.darkTile = false,
    this.solver = '',
    this.blurb = '',
  });

  final String id;
  final String label;
  final NodeKind kind;

  /// Icon centre as a fraction of the canvas size.
  final Offset home;
  final SimKind? sim;
  final String? folderTag;
  final Color? tagColor;
  final FinderView? finderView;
  final bool darkTile;
  final String solver;
  final String blurb;

  bool get isFolder => kind == NodeKind.folder;
}

/// Size of a desktop icon (thumbnail + label) and of the central engine card.
const Size kIconBox = Size(124, 134);
const double kThumbSize = 96;
const Size kCoreCardBox = Size(243, 287);
const String kCoreCardId = 'photon_engine';

const List<DesktopNode> kDesktopNodes = [
  // Left perimeter.
  DesktopNode(
    id: 'liquid_morph',
    label: 'LIQUID_MORPH.vfx',
    kind: NodeKind.vfx,
    home: Offset(0.179, 0.199),
    sim: SimKind.liquid,
    solver: 'SPH Metaball Solver',
    blurb: 'Slime metaballs. Press a blob and drag to stretch it; release to wobble.',
  ),
  DesktopNode(
    id: 'nanobot_swarm',
    label: 'NANOBOT_SWARM.vfx',
    kind: NodeKind.vfx,
    home: Offset(0.084, 0.327),
    sim: SimKind.swarm,
    darkTile: true,
    solver: 'Boids / Curl Noise',
    blurb: 'Mirrored swarm. Hover to lure it, press to cinch it, release to burst.',
  ),
  DesktopNode(
    id: 'chrome_shader',
    label: 'CHROME_SHADER.frag',
    kind: NodeKind.frag,
    home: Offset(0.270, 0.261),
    sim: SimKind.chrome,
    solver: 'GLSL Fragment / PBR',
    blurb: 'Jelly chrome knot. Press and drag to pull the tube; it snaps back.',
  ),
  DesktopNode(
    id: 'render_passes',
    label: 'RENDER_PASSES.comp',
    kind: NodeKind.comp,
    home: Offset(0.252, 0.448),
    darkTile: true,
    solver: 'Deferred Compositor',
  ),
  DesktopNode(
    id: 'preset_vault',
    label: 'PRESET_VAULT',
    kind: NodeKind.folder,
    home: Offset(0.132, 0.572),
    folderTag: '?????',
    tagColor: Color(0xFFE5243B),
    finderView: FinderView.presetVault,
  ),
  DesktopNode(
    id: 'volumetric_fog',
    label: 'VOLUMETRIC_FOG.vfx',
    kind: NodeKind.vfx,
    home: Offset(0.082, 0.780),
    sim: SimKind.fog,
    solver: 'Froxel Raymarcher',
    blurb: 'Participating media with a movable key light.',
  ),
  DesktopNode(
    id: 'wireframe_mesh',
    label: 'WIREFRAME_MESH.obj',
    kind: NodeKind.obj,
    home: Offset(0.209, 0.821),
    sim: SimKind.wireframe,
    darkTile: true,
    solver: 'Mesh Topology Viewer',
    blurb: 'Jelly mesh. Press and drag to pull vertices; it wobbles back.',
  ),
  // Right perimeter.
  DesktopNode(
    id: 'vacuum_cloth',
    label: 'VACUUM_CLOTH.vfx',
    kind: NodeKind.vfx,
    home: Offset(0.797, 0.220),
    sim: SimKind.cloth,
    darkTile: true,
    solver: 'Shrink-Wrap Membrane',
    blurb: 'Vacuum-sealed membrane. Press to push the film.',
  ),
  DesktopNode(
    id: 'node_archive',
    label: 'NODE_ARCHIVE',
    kind: NodeKind.folder,
    home: Offset(0.939, 0.183),
    folderTag: '.VFX',
    tagColor: Color(0xFFFF4FA3),
    finderView: FinderView.recentPrompts,
  ),
  DesktopNode(
    id: 'render_library',
    label: 'RENDER_LIBRARY',
    kind: NodeKind.folder,
    home: Offset(0.939, 0.364),
    folderTag: '.EXR',
    tagColor: Color(0xFF2F7BF6),
    finderView: FinderView.renderLibrary,
  ),
  DesktopNode(
    id: 'marble_turbulence',
    label: 'MARBLE_TURBULENCE.vfx',
    kind: NodeKind.vfx,
    home: Offset(0.939, 0.553),
    sim: SimKind.marble,
    solver: 'FBM Domain Warp',
    blurb: 'Turbulent marble veins. The cursor swirls the domain.',
  ),
  DesktopNode(
    id: 'caustics_loop',
    label: 'CAUSTICS_LOOP.vfx',
    kind: NodeKind.vfx,
    home: Offset(0.822, 0.609),
    sim: SimKind.caustics,
    solver: 'Photon Mapping Lite',
    blurb: 'Refracted light through a moving water surface. Hover to ripple.',
  ),
];
