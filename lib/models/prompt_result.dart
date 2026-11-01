import 'package:flutter/foundation.dart';

import 'studio_project.dart';

/// What produced a [PromptExecutionResult].
enum PromptResultKind { prompt, ingest }

/// One drum on the roller banner: a bracketed tag over its locked value.
@immutable
class RollerCell {
  const RollerCell(this.tag, this.value);

  /// `KERNEL`, `SOLVER`, `DELTA`, `SPP`, `STATUS`.
  final String tag;
  final String value;
}

/// The outcome of one prompt dispatch or asset ingest, as the roller banner
/// reports it.
@immutable
class PromptExecutionResult {
  const PromptExecutionResult({
    required this.id,
    required this.kind,
    required this.headline,
    required this.cells,
    this.prompt = '',
    this.changes = const [],
    this.dispatched = false,
  });

  /// Increases with every result, so a new one restarts the banner animation.
  final int id;
  final PromptResultKind kind;

  /// `PROMPT APPLIED · IOR 2.417 · ROUGHNESS 0.12 · 256 SPP`.
  final String headline;
  final List<RollerCell> cells;
  final String prompt;

  /// Human-readable list of what the prompt changed (`IOR 2.417`, ...).
  final List<String> changes;

  /// True when the prompt also reached the render engine.
  final bool dispatched;
}

/// What a natural-language prompt asks for, read offline so submitting one
/// visibly updates the studio even without the render engine.
@immutable
class PromptIntent {
  const PromptIntent({
    this.projectId,
    this.params = const {},
    this.roughness,
    this.integrator,
  });

  /// A project the prompt names (`gold`, `chrome`, ...), or null.
  final String? projectId;

  /// Optics parameters by id (`aperture`, `ior`, ...).
  final Map<String, double> params;

  /// Reported only: the studio has no roughness control yet.
  final double? roughness;
  final IntegratorMode? integrator;

  bool get isEmpty => projectId == null && params.isEmpty && roughness == null && integrator == null;

  /// Keyword → project. First match wins, so more specific words come first.
  static const List<(String, String)> _projectKeywords = [
    ('black hole', 'kerr_photon_ring'),
    ('kerr', 'kerr_photon_ring'),
    ('prism', 'volumetric_prism'),
    ('acrylic', 'acrylic_lens_array'),
    ('iridescen', 'thin_film_iris'),
    ('soap', 'thin_film_iris'),
    ('thin film', 'thin_film_iris'),
    ('chrome', 'chrome_caustics'),
    ('gold', 'gold_atelier_bsdf'),
    ('caustic', 'caustic_study_04'),
  ];

  /// Index-of-refraction keywords.
  static const List<(String, double)> _materialIor = [
    ('diamond', 2.417),
    ('sapphire', 1.77),
    ('water', 1.333),
    ('glass', 1.52),
  ];

  static final RegExp _fStop = RegExp(r'\bf\s*/\s*(\d+(?:\.\d+)?)');
  static final RegExp _apertureWord = RegExp(r'\baperture\s*(?:of|at|=|:)?\s*(?:f\s*/?\s*)?(\d+(?:\.\d+)?)');
  static final RegExp _iorNumber = RegExp(r'\bior\s*(?:of|at|=|:)?\s*(\d+(?:\.\d+)?)');
  static final RegExp _sppNumber = RegExp(r'(\d+)\s*spp\b|\bsamples?\s*(?:of|at|=|:)?\s*(\d+)');
  static final RegExp _bounceNumber = RegExp(r'(\d+)\s*bounces?\b');
  static final RegExp _focusMeters = RegExp(r'\bfocus(?:\s*(?:at|distance|of))?\s*(\d+(?:\.\d+)?)\s*m\b');
  static final RegExp _roughnessNumber = RegExp(r'\broughness\s*(?:of|at|=|:)?\s*(\d*\.?\d+)');

  /// Reads [text]. Only keywords and numbers are recognised; anything else is
  /// left for the render engine.
  static PromptIntent parse(String text) {
    final s = text.toLowerCase();
    final params = <String, double>{};
    String? project;
    double? roughness;
    IntegratorMode? integrator;

    for (final (word, id) in _projectKeywords) {
      if (s.contains(word)) {
        project = id;
        break;
      }
    }

    // A named material sets IOR first; an explicit number overrides it.
    for (final (word, ior) in _materialIor) {
      if (s.contains(word)) {
        params['ior'] = ior;
        break;
      }
    }
    final ior = _iorNumber.firstMatch(s);
    if (ior != null) params['ior'] = double.parse(ior.group(1)!);

    final stop = _fStop.firstMatch(s) ?? _apertureWord.firstMatch(s);
    if (stop != null) params['aperture'] = double.parse(stop.group(1)!);

    final spp = _sppNumber.firstMatch(s);
    if (spp != null) params['samples_per_pixel'] = double.parse(spp.group(1) ?? spp.group(2)!);

    final bounces = _bounceNumber.firstMatch(s);
    if (bounces != null) params['max_bounces'] = double.parse(bounces.group(1)!);

    final focus = _focusMeters.firstMatch(s);
    if (focus != null) params['focal_distance'] = double.parse(focus.group(1)!);

    final rough = _roughnessNumber.firstMatch(s);
    if (rough != null) roughness = double.tryParse(rough.group(1)!);

    if (s.contains('bidirectional') || s.contains('bdpt')) {
      integrator = IntegratorMode.bidirectional;
    } else if (s.contains('photon map') || s.contains('sppm')) {
      integrator = IntegratorMode.sppm;
    } else if (s.contains('restir')) {
      integrator = IntegratorMode.restir;
    }

    return PromptIntent(
      projectId: project,
      params: params,
      roughness: roughness,
      integrator: integrator,
    );
  }
}
