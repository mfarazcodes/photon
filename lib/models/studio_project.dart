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
  final String previewAsset;

  /// Optical parameters by `OpticsParam.id`.
  final Map<String, double> params;
  final IntegratorMode integrator;

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
  );
}

const String _wave = 'assets/images/caustic_wave.jpg';
const String _gold = 'assets/images/gold_bsdf_sphere.jpg';

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
    previewAsset: _wave,
    integrator: IntegratorMode.sppm,
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
    id: 'chrome_caustics',
    name: 'CHROME_CAUSTICS',
    code: 'PRJ-04',
    sceneType: 'Anisotropic Chrome',
    subtitle: '.pht · BiDir Solver',
    updatedAt: 'Yesterday',
    status: ProjectStatus.draft,
    previewAsset: _wave,
    integrator: IntegratorMode.bidirectional,
    params: {
      'aperture': 5.6,
      'focal_distance': 3.1,
      'ior': 2.65,
      'max_bounces': 24,
      'samples_per_pixel': 256,
      'caustics_energy': 1.1,
    },
  ),
  StudioProject(
    id: 'acrylic_lens_array',
    name: 'ACRYLIC_LENS_ARRAY',
    code: 'PRJ-05',
    sceneType: 'Liquid Mercury',
    subtitle: '.pht · DoF f/1.2',
    updatedAt: '2d ago',
    status: ProjectStatus.rendered,
    previewAsset: _gold,
    integrator: IntegratorMode.restir,
    params: {
      'aperture': 1.2,
      'focal_distance': 0.9,
      'ior': 1.492,
      'max_bounces': 8,
      'samples_per_pixel': 128,
      'caustics_energy': 0.85,
    },
  ),
];
