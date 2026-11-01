import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../state/studio_controller.dart';
import '../theme/photon_theme.dart';

/// One runnable palette entry.
@immutable
class PaletteAction {
  const PaletteAction({
    required this.id,
    required this.label,
    required this.hint,
    required this.icon,
    required this.run,
  });

  final String id;
  final String label;

  /// Right-aligned detail: a shortcut or the current state.
  final String hint;
  final IconData icon;
  final VoidCallback run;
}

/// Every action the palette offers, built from the studio's current state.
List<PaletteAction> buildPaletteActions(StudioController studio) {
  String state(bool on) => on ? 'ON' : 'OFF';
  return [
    for (final p in studio.projects)
      PaletteAction(
        id: 'load-${p.id}',
        label: 'Load Project: ${p.name}',
        hint: p.id == studio.activeProjectId ? 'ACTIVE' : p.code,
        icon: Icons.folder_open,
        run: () => studio.selectProject(p.id),
      ),
    PaletteAction(
      id: 'theme',
      label: 'Toggle Theme: ${studio.darkGrading ? 'Daylight Lab' : 'Dark Studio'}',
      hint: studio.darkGrading ? 'DARK' : 'DAYLIGHT',
      icon: Icons.contrast,
      run: () => studio.setDarkGrading(!studio.darkGrading),
    ),
    PaletteAction(
      id: 'live-shader',
      label: 'Toggle Live Procedural Shader',
      hint: state(studio.liveShaderEnabled),
      icon: Icons.bolt,
      run: studio.toggleLiveShader,
    ),
    PaletteAction(
      id: 'bvh',
      label: 'Toggle BVH / Ray Wireframe',
      hint: state(studio.bvhOverlayEnabled),
      icon: Icons.account_tree_outlined,
      run: studio.toggleBvhOverlay,
    ),
    PaletteAction(
      id: 'ab-wipe',
      label: 'Toggle A/B Render Wipe',
      hint: state(studio.abWipeEnabled),
      icon: Icons.compare,
      run: () => studio.setAbWipeEnabled(!studio.abWipeEnabled),
    ),
    PaletteAction(
      id: 'loupe',
      label: 'Toggle Pixel Loupe',
      hint: state(studio.loupeEnabled),
      icon: Icons.search,
      run: studio.toggleLoupe,
    ),
    PaletteAction(
      id: 'false-color',
      label: 'Toggle False Color Exposure',
      hint: state(studio.falseColorEnabled),
      icon: Icons.gradient,
      run: studio.toggleFalseColor,
    ),
    PaletteAction(
      id: 'snapshot',
      label: 'Capture Render Snapshot',
      hint: 'TAKE',
      icon: Icons.photo_camera_outlined,
      run: studio.captureSnapshot,
    ),
    PaletteAction(
      id: 'account',
      label: 'Open Account & Authentication Settings',
      hint: studio.account.tier.tag,
      icon: Icons.account_circle_outlined,
      run: () => studio.setAccountModalOpen(true),
    ),
    PaletteAction(
      id: 'undo',
      label: 'Undo',
      hint: 'CTRL Z',
      icon: Icons.undo,
      run: studio.undo,
    ),
    PaletteAction(
      id: 'redo',
      label: 'Redo',
      hint: 'CTRL Y',
      icon: Icons.redo,
      run: studio.redo,
    ),
    PaletteAction(
      id: 'reset-optics',
      label: 'Reset All Optics Parameters',
      hint: 'DEFAULTS',
      icon: Icons.restart_alt,
      run: studio.resetAllParams,
    ),
    PaletteAction(
      id: 'recenter',
      label: 'Recenter Camera Orbit',
      hint: 'HOME',
      icon: Icons.center_focus_strong_outlined,
      run: studio.resetOrbit,
    ),
  ];
}

/// `Ctrl+P` command palette: type to filter, arrow keys to move, Enter to run,
/// Escape (or a backdrop click) to dismiss.
class CommandPalette extends StatefulWidget {
  const CommandPalette({super.key});

  @override
  State<CommandPalette> createState() => _CommandPaletteState();
}

class _CommandPaletteState extends State<CommandPalette> {
  static const double _rowHeight = 36;

  final TextEditingController _query = TextEditingController();
  final ScrollController _scroll = ScrollController();
  int _selected = 0;

  @override
  void dispose() {
    _query.dispose();
    _scroll.dispose();
    super.dispose();
  }

  List<PaletteAction> _filtered(StudioController studio) {
    final q = _query.text.trim().toLowerCase();
    final all = buildPaletteActions(studio);
    if (q.isEmpty) return all;
    return all.where((a) => a.label.toLowerCase().contains(q) || a.hint.toLowerCase().contains(q)).toList();
  }

  void _close() => StudioScope.read(context).setCommandPaletteOpen(false);

  void _run(PaletteAction action) {
    final studio = StudioScope.read(context);
    // Close first: an action may open another overlay (the account modal).
    studio.setCommandPaletteOpen(false);
    action.run();
  }

  void _move(int delta, int count) {
    if (count == 0) return;
    setState(() => _selected = (_selected + delta) % count);
    if (_selected < 0) _selected += count;
    // Keep the selection in view.
    if (_scroll.hasClients) {
      final top = _selected * _rowHeight;
      final view = _scroll.position.viewportDimension;
      if (top < _scroll.offset) {
        _scroll.jumpTo(top);
      } else if (top + _rowHeight > _scroll.offset + view) {
        _scroll.jumpTo(top + _rowHeight - view);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final studio = StudioScope.of(context);
    final t = context.photon;
    final c = t.colors;
    final items = _filtered(studio);
    final selected = items.isEmpty ? 0 : math.min(_selected, items.length - 1);

    return Focus(
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.escape) {
          _close();
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
          _move(1, items.length);
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
          _move(-1, items.length);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          GestureDetector(
            key: const Key('command-palette-backdrop'),
            behavior: HitTestBehavior.opaque,
            onTap: _close,
            child: ColoredBox(color: Colors.black.withValues(alpha: 0.4)),
          ),
          Align(
            alignment: const Alignment(0, -0.55),
            child: Padding(
              padding: const EdgeInsets.all(PhotonSpace.lg),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 580, maxHeight: 460),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {},
                  child: Container(
                    key: const Key('command-palette-modal'),
                    decoration: BoxDecoration(
                      color: c.substrate,
                      borderRadius: BorderRadius.circular(PhotonRadius.window + 2),
                      border: Border.all(color: c.border),
                      boxShadow: t.causticGlow,
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _SearchRow(
                          controller: _query,
                          onChanged: (_) => setState(() => _selected = 0),
                          onSubmitted: () {
                            if (items.isNotEmpty) _run(items[selected]);
                          },
                        ),
                        Divider(height: 1, thickness: 1, color: c.border),
                        Flexible(
                          child: items.isEmpty
                              ? Padding(
                                  padding: const EdgeInsets.all(PhotonSpace.xl),
                                  child: Center(
                                    child: Text('NO MATCHING COMMANDS', style: t.text.labelCaps.copyWith(color: c.ghost)),
                                  ),
                                )
                              // Eager: about twenty fixed-height rows, and every
                              // action should exist for accessibility.
                              : SingleChildScrollView(
                                  controller: _scroll,
                                  padding: const EdgeInsets.symmetric(vertical: PhotonSpace.xs),
                                  child: Column(
                                    children: [
                                      for (var i = 0; i < items.length; i++)
                                        SizedBox(
                                          height: _rowHeight,
                                          child: _ActionRow(
                                            action: items[i],
                                            selected: i == selected,
                                            onHover: () => setState(() => _selected = i),
                                            onTap: () => _run(items[i]),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                        ),
                        Container(
                          height: 26,
                          padding: const EdgeInsets.symmetric(horizontal: PhotonSpace.md),
                          decoration: BoxDecoration(border: Border(top: BorderSide(color: c.border))),
                          alignment: Alignment.centerLeft,
                          child: Text(
                            '↑↓ NAVIGATE   ↵ RUN   ESC CLOSE',
                            style: t.text.labelCaps.copyWith(fontSize: 8, color: c.ghost),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchRow extends StatelessWidget {
  const _SearchRow({required this.controller, required this.onChanged, required this.onSubmitted});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onSubmitted;

  @override
  Widget build(BuildContext context) {
    final t = context.photon;
    final c = t.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: PhotonSpace.md, vertical: PhotonSpace.sm),
      child: Row(
        children: [
          Icon(Icons.keyboard_command_key, size: 15, color: c.violetInk),
          const SizedBox(width: PhotonSpace.sm),
          Expanded(
            child: TextField(
              key: const Key('command-palette-input'),
              controller: controller,
              autofocus: true,
              maxLines: 1,
              cursorColor: c.violetInk,
              onChanged: onChanged,
              onSubmitted: (_) => onSubmitted(),
              style: t.text.ui(size: 14, height: 1.3, color: c.carbon),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: 'Type a command or project…',
                hintStyle: t.text.ui(size: 14, height: 1.3, color: c.ghost),
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: c.hoverFill,
              borderRadius: BorderRadius.circular(PhotonRadius.control),
              border: Border.all(color: c.border),
            ),
            child: Text('CTRL P', style: t.text.labelCaps.copyWith(fontSize: 8)),
          ),
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({required this.action, required this.selected, required this.onHover, required this.onTap});

  final PaletteAction action;
  final bool selected;
  final VoidCallback onHover;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.photon;
    final c = t.colors;
    return Semantics(
      button: true,
      selected: selected,
      label: action.label,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => onHover(),
        child: GestureDetector(
          key: Key('palette-action-${action.id}'),
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: PhotonSpace.xs + 2),
            padding: const EdgeInsets.symmetric(horizontal: PhotonSpace.sm + 2),
            decoration: BoxDecoration(
              color: selected ? c.violet.withValues(alpha: 0.14) : Colors.transparent,
              borderRadius: BorderRadius.circular(PhotonRadius.control + 1),
              border: Border.all(color: selected ? c.violet.withValues(alpha: 0.5) : Colors.transparent),
            ),
            child: Row(
              children: [
                Icon(action.icon, size: 14, color: selected ? c.violetInk : c.textMuted),
                const SizedBox(width: PhotonSpace.md - 2),
                Expanded(
                  child: Text(
                    action.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.text.ui(size: 12.5, height: 1.3, color: c.carbon),
                  ),
                ),
                const SizedBox(width: PhotonSpace.sm),
                Text(action.hint, style: t.text.labelCaps.copyWith(fontSize: 8, color: c.ghost)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
