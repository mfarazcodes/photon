import 'package:flutter/foundation.dart';

import 'studio_project.dart';

/// A captured "take": enough of the studio state to restore it exactly.
@immutable
class RenderSnapshot {
  const RenderSnapshot({
    required this.id,
    required this.label,
    required this.projectId,
    required this.projectName,
    required this.params,
    required this.integrator,
    required this.timestamp,
  });

  final String id;

  /// `TAKE 01`, `TAKE 02`, ...
  final String label;
  final String projectId;
  final String projectName;

  /// Every optical parameter, by `OpticsParam.id`.
  final Map<String, double> params;
  final IntegratorMode integrator;
  final DateTime timestamp;

  double get ior => params['ior'] ?? 1.0;
  int get spp => (params['samples_per_pixel'] ?? 0).round();
  double get aperture => params['aperture'] ?? 0;
}
