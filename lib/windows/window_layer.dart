import 'dart:math' as math;

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

  static const double _top = 82;
  static const double _bottomDock = 104;

  @override
  Widget build(BuildContext context) {
    final ws = WorkspaceScope.of(context);
    return LayoutBuilder(builder: (context, c) {
      final W = c.maxWidth, H = c.maxHeight;
      return Stack(
        children: [
          for (final w in ws.windows) _placed(ws, w, W, H),
        ],
      );
    });
  }

  Widget _placed(WorkspaceController ws, OpenWindow w, double W, double H) {
    late double left, top, width, height;
    if (w.maximized) {
      left = 16;
      top = _top;
      width = W - 32;
      height = H - _top - _bottomDock;
    } else {
      width = math.min(w.size.width, W - 32);
      height = math.min(w.size.height, H - _top - 16);
      left = (W - width) / 2 + w.offset.dx;
      top = _top + (H - _top - 16 - height) / 2 + w.offset.dy;
      left = left.clamp(-width + 140, math.max(-width + 140, W - 140));
      top = top.clamp(64.0, math.max(64.0, H - 70));
    }
    width = math.max(width, 280);
    height = math.max(height, 220);

    return AnimatedPositioned(
      key: ValueKey(w.id),
      duration: w.dragging ? Duration.zero : const Duration(milliseconds: 360),
      curve: Curves.easeOutCubic,
      left: left,
      top: top,
      width: width,
      height: height,
      child: IgnorePointer(
        ignoring: w.minimized,
        child: AnimatedScale(
          scale: w.minimized ? 0.15 : 1,
          alignment: Alignment.bottomCenter,
          duration: const Duration(milliseconds: 380),
          curve: Curves.easeInOutCubic,
          child: AnimatedOpacity(
            opacity: w.minimized ? 0 : 1,
            duration: const Duration(milliseconds: 300),
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
    );
  }

  Widget _content(OpenWindow w) => switch (w.type) {
        WindowType.viewport => VfxViewportContent(node: w.node!),
        WindowType.compositor => const CompositorContent(),
        WindowType.inspector => const EngineInspectorContent(),
        WindowType.finder => AssetBrowserContent(view: w.finderView),
      };

  Widget? _footer(WorkspaceController ws, OpenWindow w) => switch (w.type) {
        WindowType.viewport => WindowFooter(
            caption: '${w.node!.solver}  ·  ${w.node!.blurb}',
            action: 'Remix prompt',
            onAction: () => ws.openOverlay(StudioOverlay.promptDrawer),
          ),
        WindowType.compositor => WindowFooter(
            caption: 'Hover a pass to expand · click to focus it full-frame.',
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
