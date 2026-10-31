// Photon VFX Studio: a spatial desktop for the Photon Text-to-VFX engine.
//
// Layer order (bottom to top):
//   desktop canvas (studio floor, wordmark, floaters, file nodes)
//   floating windows
//   top pill bar + render dropdown
//   bottom explore dock
//   overlays (prompt drawer, about, kinetic archive)
//
// Global shortcuts (Space, Ctrl+N, Escape) live in the desktop canvas.
//
// Run with: flutter run -d windows

import 'package:flutter/material.dart';

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
  const PhotonApp({super.key, this.connectEngine = true});

  /// Whether to connect to the Python render server. Widget tests pass false:
  /// flutter_test mocks all HTTP, and a WebSocket handshake can't survive it.
  final bool connectEngine;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Photon VFX Studio',
      theme: photonTheme(),
      home: PhotonStudio(connectEngine: connectEngine),
    );
  }
}

class PhotonStudio extends StatefulWidget {
  const PhotonStudio({super.key, this.connectEngine = true});

  final bool connectEngine;

  @override
  State<PhotonStudio> createState() => _PhotonStudioState();
}

class _PhotonStudioState extends State<PhotonStudio> {
  late final WorkspaceController _ws = WorkspaceController(connectEngine: widget.connectEngine);

  @override
  void dispose() {
    _ws.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return WorkspaceScope(
      controller: _ws,
      child: Material(
        color: PC.canvasTop,
        child: ListenableBuilder(
          listenable: _ws,
          builder: (context, _) {
            final transient = _ws.exploreOpen || _ws.renderDropdownOpen;
            // The full-screen archive hides everything beneath it, so freeze
            // the desktop's tickers (physics, sims, floaters) while it is up.
            final covered = _ws.overlay == StudioOverlay.archive;
            return Stack(
              children: [
                Positioned.fill(
                  child: TickerMode(enabled: !covered, child: const DesktopCanvas()),
                ),
                Positioned.fill(
                  child: TickerMode(enabled: !covered, child: const WindowLayer()),
                ),
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
    );
  }
}
