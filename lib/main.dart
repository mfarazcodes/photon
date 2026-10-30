// Photon VFX Studio: a spatial desktop for the Photon Text-to-VFX engine.
//
// Layer order (bottom to top):
//   desktop canvas (studio floor, Photon Core, file nodes)
//   floating windows
//   top pill bar + render dropdown
//   bottom explore dock
//   overlays (prompt drawer, about, kinetic archive)
//
// Run with: flutter run -d windows

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'state/workspace_controller.dart';
import 'theme/photon_theme.dart';
import 'widgets/bottom_explore_dock.dart';
import 'widgets/desktop_canvas.dart';
import 'widgets/top_pill_bar.dart';
import 'windows/about_window.dart';
import 'windows/kinetic_archive.dart';
import 'windows/prompt_drawer.dart';
import 'windows/window_layer.dart';

void main() => runApp(const PhotonApp());

class PhotonApp extends StatelessWidget {
  const PhotonApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Photon VFX Studio',
      theme: photonTheme(),
      home: const PhotonStudio(),
    );
  }
}

class PhotonStudio extends StatefulWidget {
  const PhotonStudio({super.key});

  @override
  State<PhotonStudio> createState() => _PhotonStudioState();
}

class _PhotonStudioState extends State<PhotonStudio> {
  final WorkspaceController _ws = WorkspaceController();

  @override
  void dispose() {
    _ws.dispose();
    super.dispose();
  }

  void _escape() {
    if (_ws.overlay != StudioOverlay.none) {
      _ws.closeOverlay();
    } else if (_ws.exploreOpen || _ws.renderDropdownOpen) {
      _ws.closeTransient();
    } else if (_ws.topWindow != null) {
      _ws.close(_ws.topWindow!.id);
    } else {
      _ws.select(null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return WorkspaceScope(
      controller: _ws,
      child: CallbackShortcuts(
        bindings: {const SingleActivator(LogicalKeyboardKey.escape): _escape},
        child: Focus(
          autofocus: true,
          child: Material(
            color: PC.canvasTop,
            child: ListenableBuilder(
              listenable: _ws,
              builder: (context, _) {
                final transient = _ws.exploreOpen || _ws.renderDropdownOpen;
                return Stack(
                  children: [
                    const Positioned.fill(child: DesktopCanvas()),
                    const Positioned.fill(child: WindowLayer()),
                    if (transient)
                      Positioned.fill(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: _ws.closeTransient,
                        ),
                      ),
                    const Positioned(top: 0, left: 0, right: 0, child: TopPillBar()),
                    const RenderDropdownLayer(),
                    const Positioned(
                      left: 0,
                      right: 0,
                      bottom: 18,
                      child: Center(child: BottomExploreDock()),
                    ),
                    const Positioned.fill(child: AboutWindow()),
                    const Positioned.fill(child: PromptDrawer()),
                    const Positioned.fill(child: KineticArchive()),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
