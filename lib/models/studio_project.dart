import 'package:flutter/foundation.dart';

/// Path-tracing integrator, cycled from the viewport HUD.
enum IntegratorMode {
  unidirectional('UNIDIRECTIONAL PT', 'Cauchy'),
  bidirectional('BIDIRECTIONAL PT', 'BiDir MIS'),
  sppm('SPPM CAUSTICS', 'Photon Map'),
  restir('ReSTIR PT', 'Spatiotemporal');

  const IntegratorMode(this.label, this.solverCaption);

  /// HUD pill text.
  final String label;

  /// Caustics solver read-out on the optics deck.
  final String solverCaption;

  IntegratorMode get next => values[(index + 1) % values.length];
}

enum ProjectStatus {
  active('ACTIVE'),
  rendered('RENDERED'),
  draft('DRAFT');

  const ProjectStatus(this.label);

  final String label;
}

/// The real-time procedural optical simulations behind a project's live mode.
enum ProceduralSceneKind {
  causticWave,
  spectralPrism,
  liquidChrome,
  blackHoleLensing,
  emeraldSubsurface,
  soapFilmIridescence,
}

/// A saved scene: optical parameters plus the integrator that renders them.
@immutable
class StudioProject {
  const StudioProject({
    required this.id,
    required this.name,
    required this.code,
    required this.sceneType,
    required this.subtitle,
    required this.updatedAt,
    required this.status,
    required this.previewAsset,
    required this.params,
    this.integrator = IntegratorMode.unidirectional,
    this.sceneKind = ProceduralSceneKind.causticWave,
    this.isDynamic = false,
    this.localFilePath,
    this.externalUrl,
    this.customBytes,
  });

  /// Stable identifier; also the payload of a dragged project card.
  final String id;
  final String name;

  /// Shot code, e.g. `PRJ-01`.
  final String code;
  final String sceneType;

  /// Card second line, e.g. `.pht · Dispersion Rig`.
  final String subtitle;

  /// Human-readable age, e.g. `2m ago`.
  final String updatedAt;
  final ProjectStatus status;

  /// The static reference render.
  final String previewAsset;

  /// Optical parameters by `OpticsParam.id`.
  final Map<String, double> params;
  final IntegratorMode integrator;

  /// The procedural simulation this project runs when live.
  final ProceduralSceneKind sceneKind;

  /// Opens with the live procedural simulation instead of the still render.
  /// Every project can still be switched either way from the viewport.
  final bool isDynamic;

  /// A file the user brought in from disk. When it is an image the viewport
  /// shows it.
  final String? localFilePath;

  /// A direct URL the user embedded. The viewport loads it when it is an image.
  final String? externalUrl;

  /// The bytes of an uploaded image, held so it shows without touching the
  /// disk again. Takes priority over [localFilePath] and [externalUrl].
  final Uint8List? customBytes;

  double get ior => params['ior'] ?? 1.0;
  int get spp => (params['samples_per_pixel'] ?? 0).round();

  StudioProject copyWith({
    String? id,
    String? name,
    String? code,
    String? sceneType,
    String? subtitle,
    String? updatedAt,
    ProjectStatus? status,
    String? previewAsset,
    Map<String, double>? params,
    IntegratorMode? integrator,
    ProceduralSceneKind? sceneKind,
    bool? isDynamic,
    String? localFilePath,
    String? externalUrl,
    Uint8List? customBytes,
  }) => StudioProject(
    id: id ?? this.id,
    name: name ?? this.name,
    code: code ?? this.code,
    sceneType: sceneType ?? this.sceneType,
    subtitle: subtitle ?? this.subtitle,
    updatedAt: updatedAt ?? this.updatedAt,
    status: status ?? this.status,
    previewAsset: previewAsset ?? this.previewAsset,
    params: params ?? this.params,
    integrator: integrator ?? this.integrator,
    sceneKind: sceneKind ?? this.sceneKind,
    isDynamic: isDynamic ?? this.isDynamic,
    localFilePath: localFilePath ?? this.localFilePath,
    externalUrl: externalUrl ?? this.externalUrl,
    customBytes: customBytes ?? this.customBytes,
  );
}

const String _wave = 'assets/images/caustic_wave.jpg';
const String _gold = 'assets/images/gold_bsdf_sphere.jpg';
const String _prism = 'assets/images/volumetric_prism.png';
const String _emerald = 'assets/images/emerald_subsurface.png';
const String _kerr = 'assets/images/blackhole_lensing.png';

/// Shipped starter projects. The first is active on launch.
const List<StudioProject> kDefaultProjects = [
  StudioProject(
    id: 'caustic_study_04',
    name: 'CAUSTIC_STUDY_04',
    code: 'PRJ-01',
    sceneType: 'Caustic Dispersion',
    subtitle: '.pht · Dispersion Rig',
    updatedAt: '2m ago',
    status: ProjectStatus.active,
    previewAsset: _wave,
    integrator: IntegratorMode.unidirectional,
    sceneKind: ProceduralSceneKind.causticWave,
    isDynamic: true,
    params: {
      'aperture': 1.4,
      'focal_distance': 1.82,
      'ior': 2.253,
      'max_bounces': 12,
      'samples_per_pixel': 256,
      'caustics_energy': 1.35,
    },
  ),
  StudioProject(
    id: 'gold_atelier_bsdf',
    name: 'GOLD_ATELIER_BSDF',
    code: 'PRJ-02',
    sceneType: 'Gold Atelier BSDF',
    subtitle: '.pht · Microfacet GGX',
    updatedAt: '1h ago',
    status: ProjectStatus.rendered,
    previewAsset: _gold,
    integrator: IntegratorMode.unidirectional,
    sceneKind: ProceduralSceneKind.liquidChrome,
    isDynamic: false,
    params: {
      'aperture': 2.8,
      'focal_distance': 1.2,
      'ior': 1.45,
      'max_bounces': 8,
      'samples_per_pixel': 512,
      'caustics_energy': 0.4,
    },
  ),
  StudioProject(
    id: 'volumetric_prism',
    name: 'VOLUMETRIC_PRISM',
    code: 'PRJ-03',
    sceneType: 'Volumetric Prism',
    subtitle: '.pht · Spectral Cauchy',
    updatedAt: '3h ago',
    status: ProjectStatus.active,
    previewAsset: _prism,
    integrator: IntegratorMode.sppm,
    sceneKind: ProceduralSceneKind.spectralPrism,
    isDynamic: true,
    params: {
      'aperture': 4.0,
      'focal_distance': 2.4,
      'ior': 1.78,
      'max_bounces': 16,
      'samples_per_pixel': 1024,
      'caustics_energy': 1.8,
    },
  ),
  StudioProject(
    id: 'acrylic_lens_array',
    name: 'ACRYLIC_LENS_ARRAY',
    code: 'PRJ-04',
    sceneType: 'Liquid Mercury',
    subtitle: '.pht · DoF f/1.2',
    updatedAt: '2d ago',
    status: ProjectStatus.rendered,
    previewAsset: _emerald,
    integrator: IntegratorMode.restir,
    sceneKind: ProceduralSceneKind.emeraldSubsurface,
    isDynamic: false,
    params: {
      'aperture': 1.2,
      'focal_distance': 0.9,
      'ior': 1.492,
      'max_bounces': 8,
      'samples_per_pixel': 128,
      'caustics_energy': 0.85,
    },
  ),
  StudioProject(
    id: 'kerr_photon_ring',
    name: 'KERR_PHOTON_RING',
    code: 'PRJ-05',
    sceneType: 'Relativistic Lensing',
    subtitle: '.pht · GR Ray Marcher',
    updatedAt: '5h ago',
    status: ProjectStatus.active,
    previewAsset: _kerr,
    integrator: IntegratorMode.unidirectional,
    sceneKind: ProceduralSceneKind.blackHoleLensing,
    isDynamic: true,
    params: {
      'aperture': 2.0,
      'focal_distance': 4.5,
      'ior': 2.0,
      'max_bounces': 24,
      'samples_per_pixel': 512,
      'caustics_energy': 1.6,
    },
  ),
];
