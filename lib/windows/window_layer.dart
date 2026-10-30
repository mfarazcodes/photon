import 'package:flutter/material.dart';

import '../models/desktop_node.dart';
import '../state/workspace_controller.dart';
import 'asset_browser_window.dart';
import 'compositor_window.dart';
import 'engine_inspector_window.dart';
import 'mac_window.dart';
import 'vfx_viewport_window.dart';

/// Lays out every open window in z-order above the desktop.
class WindowLayer extends StatelessWidget {
  const WindowLayer({super.key});

  @override
  Widget build(BuildContext context) {
    final ws = WorkspaceScope.of(context);
    return LayoutBuilder(builder: (context, c) {
      final vp = c.biggest;
      // Drag clamping lives in the controller and needs the live window area.
      ws.setViewport(vp);
      return Stack(
        children: [
          for (final w in ws.windows) _placed(ws, w, vp),
        ],
      );
    });
  }

  /// Where a minimized window shrinks to: the desktop node it came from.
  Offset _minimizeTarget(WorkspaceController ws, OpenWindow w, Size vp) {
    final node = w.node;
    if (node != null) {
      return Offset(node.home.dx * vp.width, node.home.dy * vp.height);
    }
    return switch (w.type) {
      WindowType.inspector => Offset(vp.width * 0.5, vp.height * 0.49),
      _ => Offset(vp.width / 2, vp.height - 56),
    };
  }

  Widget _placed(WorkspaceController ws, OpenWindow w, Size vp) {
    final rect = w.rectIn(vp);
    final target = _minimizeTarget(ws, w, vp);
    final anchor = Alignment(
      ((target.dx - rect.left) / rect.width * 2 - 1).clamp(-6.0, 6.0),
      ((target.dy - rect.top) / rect.height * 2 - 1).clamp(-6.0, 6.0),
    );

    return AnimatedPositioned(
      key: ValueKey(w.id),
      duration: w.dragging ? Duration.zero : const Duration(milliseconds: 360),
      curve: Curves.easeOutCubic,
      left: rect.left,
      top: rect.top,
      width: rect.width,
      height: rect.height,
      child: IgnorePointer(
        ignoring: w.minimized,
        // A minimized window is invisible; stop its animations too.
        child: TickerMode(
          enabled: !w.minimized,
          child: AnimatedScale(
            scale: w.minimized ? 0.06 : 1,
            alignment: anchor,
            duration: const Duration(milliseconds: 420),
            curve: Curves.easeInOutCubic,
            child: AnimatedOpacity(
              opacity: w.minimized ? 0 : 1,
              duration: const Duration(milliseconds: 320),
              child: RepaintBoundary(
                child: MacWindow(
                  title: w.title,
                  onClose: () => ws.close(w.id),
                  onMinimize: () => ws.minimize(w.id),
                  onMaximize: () => ws.toggleMaximize(w.id),
                  onDrag: (d) => ws.dragWindow(w.id, d),
                  onDragEnd: () => ws.endDragWindow(w.id),
                  onFocus: () => ws.focus(w.id),
                  footer: _footer(ws, w),
                  child: _content(w),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _content(OpenWindow w) => switch (w.type) {
        WindowType.viewport => VfxViewportContent(key: ValueKey('vp:${w.id}'), node: w.node!),
        WindowType.compositor => const CompositorContent(),
        WindowType.inspector => const EngineInspectorContent(),
        WindowType.finder => AssetBrowserContent(view: w.finderView),
      };

  Widget? _footer(WorkspaceController ws, OpenWindow w) => switch (w.type) {
        WindowType.viewport => WindowFooter(
            caption: w.node!.generated
                ? '${w.node!.solver}  ·  seeded from your prompt'
                : '${w.node!.solver}  ·  ${w.node!.blurb}',
            action: 'Remix prompt',
            onAction: () => ws.openOverlay(StudioOverlay.promptDrawer),
          ),
        WindowType.compositor => WindowFooter(
            caption: 'Hover a pass to expand · click to compare it split-screen.',
            action: 'Export EXR',
            onAction: () => ws.openFinder(FinderView.renderLibrary),
          ),
        WindowType.inspector => WindowFooter(
            caption: 'Queue a render with the current core settings.',
            action: 'Launch render',
            onAction: () => ws.openOverlay(StudioOverlay.promptDrawer),
          ),
        WindowType.finder => null,
      };
}
