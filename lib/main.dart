import 'package:flutter/material.dart';

import 'state/studio_controller.dart';
import 'theme/photon_theme.dart';
import 'widgets/spatial_canvas.dart';

void main() {
  runApp(const PhotonApp());
}

class PhotonApp extends StatefulWidget {
  const PhotonApp({super.key, this.controller});

  /// Injected by tests; the app creates (and owns) its own when null.
  final StudioController? controller;

  @override
  State<PhotonApp> createState() => _PhotonAppState();
}

class _PhotonAppState extends State<PhotonApp> {
  // The app opens on the launch film and shows the projects as a stacked deck.
  late final StudioController _studio =
      widget.controller ?? StudioController(startInLaunchPortal: true, startInDeckView: true);
  late bool _dark = _studio.darkGrading;

  // Built once: ThemeData construction pulls in the Google Fonts text theme.
  late final ThemeData _daylight = buildPhotonTheme(PhotonPalette.daylight);
  late final ThemeData _grading = buildPhotonTheme(PhotonPalette.grading);

  @override
  void initState() {
    super.initState();
    _studio.addListener(_onStudioChanged);
  }

  /// Only the theme toggle needs an app-level rebuild; everything else is
  /// handled by the widgets that depend on [StudioScope].
  void _onStudioChanged() {
    if (_dark != _studio.darkGrading) setState(() => _dark = _studio.darkGrading);
  }

  @override
  void dispose() {
    _studio.removeListener(_onStudioChanged);
    if (widget.controller == null) _studio.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StudioScope(
      controller: _studio,
      child: MaterialApp(
        title: 'PHOTON® Spatial Studio',
        debugShowCheckedModeBanner: false,
        theme: _dark ? _grading : _daylight,
        home: const Scaffold(body: SpatialCanvas()),
      ),
    );
  }
}
