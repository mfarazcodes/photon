import 'package:flutter/material.dart';

import '../models/desktop_node.dart';
import '../models/vfx_dna.dart';
import '../state/workspace_controller.dart';
import '../theme/photon_theme.dart';
import '../widgets/desktop_icon.dart';
import '../widgets/sim_view.dart';

const _presets = [
  ('Iridescent_Bloom.preset', SimKind.liquid),
  ('Nano_Dissolve.preset', SimKind.swarm),
  ('Liquid_Chrome.preset', SimKind.chrome),
  ('God_Rays_Haze.preset', SimKind.fog),
  ('Topology_Scan.preset', SimKind.wireframe),
  ('Shrink_Wrap.preset', SimKind.cloth),
  ('Pool_Caustics.preset', SimKind.caustics),
  ('Carrara_Flow.preset', SimKind.marble),
  ('Core_Pulse.preset', SimKind.core),
  ('Rose_Goo.preset', SimKind.liquid),
  ('Ember_Swarm.preset', SimKind.swarm),
  ('Prism_Knot.preset', SimKind.chrome),
];

const _renders = [
  ('Volumetric Shockwave_v4', 'Froxel Raymarcher', '10.30.2026', 'EXR', SimKind.fog),
  ('Liquid Chrome Bloom_v2', 'GLSL PBR', '10.29.2026', 'EXR', SimKind.chrome),
  ('Nanobot Dissolve_v7', 'Boids / Curl', '10.28.2026', 'MP4', SimKind.swarm),
  ('Caustic Pool Loop_v1', 'Photon Mapping', '10.27.2026', 'EXR', SimKind.caustics),
  ('Marble Storm_v3', 'FBM Domain Warp', '10.25.2026', 'MP4', SimKind.marble),
  ('Vacuum Seal Hero_v5', 'Shrink-Wrap', '10.24.2026', 'EXR', SimKind.cloth),
  ('Pink Goo Title_v2', 'SPH Metaball', '10.22.2026', 'MP4', SimKind.liquid),
  ('Core Breach_v9', 'NeRF Particle', '10.20.2026', 'EXR', SimKind.core),
  ('Topology Sweep_v1', 'Mesh Viewer', '10.18.2026', 'MP4', SimKind.wireframe),
];

const _prompts = [
  ('Volumetric shockwave through iridescent chrome nanobots', '2 min ago'),
  ('Pink liquid metal spelling PHOTON, macro lens, droplets', '18 min ago'),
  ('Marble statue dissolving into turbulent smoke, studio light', '1 h ago'),
  ('Underwater caustics on a white tiled pool, overhead', '3 h ago'),
  ('Vacuum-sealed product hero shot, crinkled plastic, rim light', 'Yesterday'),
  ('Orange wireframe terrain scan, black void, CRT glow', '2 days ago'),
];

/// Wraps a built-in preset/render so it opens in the live viewport window.
DesktopNode _adhoc(String name, SimKind sim, String solver) => DesktopNode(
      id: 'asset:$name',
      label: name,
      kind: NodeKind.vfx,
      home: Offset.zero,
      sim: sim,
      solver: solver,
    );

/// macOS Finder-style browser with a favourites sidebar.
class AssetBrowserContent extends StatelessWidget {
  const AssetBrowserContent({super.key, required this.view});

  final FinderView view;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _Sidebar(active: view),
        Container(width: 1, color: PC.hairline),
        Expanded(
          child: Column(
            children: [
              _Toolbar(view: view),
              Container(height: 1, color: PC.hairline),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 240),
                  child: KeyedSubtree(key: ValueKey(view), child: _body(context)),
                ),
              ),
              Container(height: 1, color: PC.hairline),
              Container(
                height: 34,
                alignment: Alignment.center,
                child: Text(_status, style: PT.mono(size: 11.5, color: PC.muted)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String get _status => switch (view) {
        FinderView.presetVault => '${_presets.length} presets · 3.1 GB on Local GPU Node',
        FinderView.renderLibrary => '${_renders.length} renders · 214 GB in library',
        FinderView.workspace => '${kDesktopNodes.length} items on desktop',
        FinderView.recentPrompts => '${_prompts.length} prompts · synced',
        FinderView.localGpu => '1 node online',
        FinderView.cloudCluster => '3 nodes online · us-east / eu-west',
      };

  Widget _body(BuildContext context) => switch (view) {
        FinderView.presetVault => const _PresetGrid(),
        FinderView.renderLibrary => const _RenderTable(),
        FinderView.workspace => const _WorkspaceGrid(),
        FinderView.recentPrompts => const _PromptList(),
        FinderView.localGpu => const _GpuList(cloud: false),
        FinderView.cloudCluster => const _GpuList(cloud: true),
      };
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.active});

  final FinderView active;

  static const _icons = {
    FinderView.workspace: Icons.dashboard_outlined,
    FinderView.presetVault: Icons.inventory_2_outlined,
    FinderView.renderLibrary: Icons.video_library_outlined,
    FinderView.recentPrompts: Icons.history_rounded,
    FinderView.localGpu: Icons.memory_rounded,
    FinderView.cloudCluster: Icons.cloud_outlined,
  };

  @override
  Widget build(BuildContext context) {
    Widget header(String text) => Padding(
          padding: const EdgeInsets.fromLTRB(14, 18, 14, 8),
          child: Text(text, style: PT.mono(size: 11, color: PC.muted, weight: FontWeight.w700)),
        );
    return Container(
      width: 220,
      color: const Color(0xFFF1F1F1),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          header('FAVORITES'),
          for (final v in [
            FinderView.workspace,
            FinderView.presetVault,
            FinderView.renderLibrary,
            FinderView.recentPrompts,
          ])
            _SidebarItem(view: v, icon: _icons[v]!, active: v == active),
          header('LOCATIONS'),
          for (final v in [FinderView.localGpu, FinderView.cloudCluster])
            _SidebarItem(view: v, icon: _icons[v]!, active: v == active),
        ],
      ),
    );
  }
}

class _SidebarItem extends StatefulWidget {
  const _SidebarItem({required this.view, required this.icon, required this.active});

  final FinderView view;
  final IconData icon;
  final bool active;

  @override
  State<_SidebarItem> createState() => _SidebarItemState();
}

class _SidebarItemState extends State<_SidebarItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.active;
    final fg = active ? PC.white : PC.ink;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: () => WorkspaceScope.read(context).setFinderView(widget.view),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          margin: const EdgeInsets.only(bottom: 2),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: active ? PC.blue : (_hover ? const Color(0x0F000000) : Colors.transparent),
            borderRadius: BorderRadius.circular(100),
          ),
          child: Row(
            children: [
              Icon(widget.icon, size: 18, color: active ? PC.white : PC.blue),
              const SizedBox(width: 10),
              Text(widget.view.title, style: PT.label(size: 14.5, color: fg)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({required this.view});

  final FinderView view;

  @override
  Widget build(BuildContext context) {
    final grid = view == FinderView.presetVault || view == FinderView.workspace;
    return SizedBox(
      height: 58,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        child: Row(
          children: [
            const Icon(Icons.chevron_left_rounded, color: PC.muted),
            const Icon(Icons.chevron_right_rounded, color: Color(0xFFCFCFCF)),
            const SizedBox(width: 10),
            Text(view.title, style: PT.label(size: 19, weight: FontWeight.w700)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: const Color(0xFFEDEDED),
                borderRadius: BorderRadius.circular(100),
              ),
              child: Row(
                children: [
                  _seg(Icons.grid_view_rounded, grid),
                  _seg(Icons.view_list_rounded, !grid),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Container(
              width: 190,
              height: 34,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFEDEDED),
                borderRadius: BorderRadius.circular(100),
              ),
              child: Row(
                children: [
                  const Icon(Icons.search_rounded, size: 18, color: PC.muted),
                  const SizedBox(width: 6),
                  Expanded(
                    child: TextField(
                      style: PT.label(size: 14),
                      cursorHeight: 16,
                      decoration: InputDecoration(
                        isCollapsed: true,
                        border: InputBorder.none,
                        hintText: 'Search',
                        hintStyle: PT.label(size: 14, color: PC.muted),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _seg(IconData icon, bool on) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: on ? PC.white : Colors.transparent,
          borderRadius: BorderRadius.circular(100),
        ),
        child: Icon(icon, size: 18, color: on ? PC.ink : PC.muted),
      );
}

class _PresetGrid extends StatefulWidget {
  const _PresetGrid();

  @override
  State<_PresetGrid> createState() => _PresetGridState();
}

class _PresetGridState extends State<_PresetGrid> {
  @override
  Widget build(BuildContext context) {
    final ws = WorkspaceScope.of(context);
    // Presets plus every .vfx node generated from the Prompt Drawer.
    final items = [
      for (final p in _presets) _adhoc(p.$1, p.$2, 'Preset'),
      ...ws.nodes.where((n) => n.generated),
    ];
    return GridView.builder(
      padding: const EdgeInsets.all(22),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisSpacing: 18,
        crossAxisSpacing: 18,
        childAspectRatio: 0.86,
      ),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final node = items[i];
        final name = node.label;
        final kind = node.sim ?? SimKind.core;
        final sel = ws.selectedId == node.id;
        return GestureDetector(
          onTap: () => ws.openNode(node),
          onDoubleTap: () => ws.openNode(node),
          child: Column(
            children: [
              Expanded(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    color: sel ? const Color(0x142563EB) : Colors.transparent,
                    border: Border.all(color: sel ? PC.blue : Colors.transparent, width: 2),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SimView(kind: kind, dna: node.dna, thumb: true, speed: 0.7),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              FileLabel(text: name, selected: sel, size: 13),
            ],
          ),
        );
      },
    );
  }
}

class _WorkspaceGrid extends StatelessWidget {
  const _WorkspaceGrid();

  @override
  Widget build(BuildContext context) {
    final ws = WorkspaceScope.of(context);
    return GridView.builder(
      padding: const EdgeInsets.all(22),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 150,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: 0.82,
      ),
      itemCount: kDesktopNodes.length,
      itemBuilder: (context, i) {
        final node = kDesktopNodes[i];
        return MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: () => ws.openNode(node),
            child: Column(
              children: [
                Expanded(child: IconThumb(node: node)),
                const SizedBox(height: 8),
                FileLabel(text: node.label, selected: ws.selectedId == node.id, size: 12),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _RenderTable extends StatelessWidget {
  const _RenderTable();

  @override
  Widget build(BuildContext context) {
    final head = PT.mono(size: 11, color: PC.muted, weight: FontWeight.w700);
    final ws = WorkspaceScope.of(context);
    // Newest generated renders first, then the built-in library.
    final rows = <(DesktopNode, (String, String, String, String, SimKind))>[
      for (final n in ws.nodes.where((n) => n.generated).toList().reversed)
        (
          n,
          (n.label.replaceAll('.vfx', ''), n.solver, 'Today', 'EXR', n.sim ?? SimKind.core),
        ),
      for (final r in _renders) (_adhoc(r.$1, r.$5, r.$2), r),
    ];
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 14, 24, 10),
          child: Row(
            children: [
              Expanded(flex: 5, child: Text('RENDER JOB', style: head)),
              Expanded(flex: 3, child: Text('SHADER ENGINE', style: head)),
              Expanded(flex: 2, child: Text('DATE', style: head)),
              SizedBox(width: 70, child: Text('FORMAT', style: head)),
            ],
          ),
        ),
        Container(height: 1, color: PC.hairline, margin: const EdgeInsets.symmetric(horizontal: 18)),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            itemCount: rows.length,
            itemBuilder: (context, i) {
              final (node, data) = rows[i];
              final sel = ws.selectedId == node.id;
              return MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => ws.openNode(node),
                  onDoubleTap: () => ws.openNode(node),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: sel ? const Color(0x142563EB) : null,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: sel ? PC.blue : Colors.transparent, width: 2),
                    ),
                    child: _RenderRow(data: data, dna: node.dna),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _RenderRow extends StatefulWidget {
  const _RenderRow({required this.data, this.dna});

  final (String, String, String, String, SimKind) data;

  /// Set for rows backed by a generated render.
  final VfxDna? dna;

  @override
  State<_RenderRow> createState() => _RenderRowState();
}

class _RenderRowState extends State<_RenderRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final (name, engine, date, format, kind) = widget.data;
    final exr = format == 'EXR';
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: _hover ? PC.white : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Expanded(
              flex: 5,
              child: Row(
                children: [
                  ClipOval(
                    child: SizedBox(
                      width: 38,
                      height: 38,
                      child: SimView(kind: kind, dna: widget.dna, thumb: true),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(name,
                        overflow: TextOverflow.ellipsis,
                        style: PT.label(size: 15, weight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
            Expanded(flex: 3, child: Text(engine, style: PT.label(size: 14, color: PC.inkSoft, weight: FontWeight.w400))),
            Expanded(flex: 2, child: Text(date, style: PT.mono(size: 13, color: PC.inkSoft))),
            SizedBox(
              width: 70,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: exr ? PC.blue : const Color(0xFFFF4FA3),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text('.$format',
                      style: PT.mono(size: 11, color: PC.white, weight: FontWeight.w700)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PromptList extends StatelessWidget {
  const _PromptList();

  @override
  Widget build(BuildContext context) {
    final ws = WorkspaceScope.of(context);
    return ListView.separated(
      padding: const EdgeInsets.all(18),
      itemCount: _prompts.length,
      separatorBuilder: (_, _) => Container(height: 1, color: PC.hairline),
      itemBuilder: (context, i) {
        final (text, ago) = _prompts[i];
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
          child: Row(
            children: [
              const Icon(Icons.notes_rounded, color: PC.blue, size: 20),
              const SizedBox(width: 14),
              Expanded(child: Text(text, style: PT.label(size: 15, weight: FontWeight.w400))),
              Text(ago, style: PT.mono(size: 12, color: PC.muted)),
              const SizedBox(width: 16),
              TextButton(
                onPressed: () => ws.openOverlay(StudioOverlay.promptDrawer),
                child: Text('Re-run ↗', style: PT.label(size: 14, color: PC.blue)),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _GpuList extends StatelessWidget {
  const _GpuList({required this.cloud});

  final bool cloud;

  @override
  Widget build(BuildContext context) {
    final nodes = cloud
        ? const [
            ('H200 ×8 · us-east-1', 0.87, 61, 'RENDERING'),
            ('H200 ×8 · eu-west-2', 0.42, 54, 'IDLE'),
            ('B300 ×4 · us-west-2', 0.95, 68, 'RENDERING'),
          ]
        : const [('RTX 6090 · 32 GB · Local', 0.78, 66, 'RENDERING')];
    return ListView(
      padding: const EdgeInsets.all(22),
      children: [
        for (final (name, util, temp, status) in nodes)
          Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: PC.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: PC.hairline),
            ),
            child: Row(
              children: [
                Icon(cloud ? Icons.cloud_rounded : Icons.memory_rounded, color: PC.blue, size: 28),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: PT.label(size: 16, weight: FontWeight.w700)),
                      const SizedBox(height: 10),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: util,
                          minHeight: 6,
                          color: PC.blue,
                          backgroundColor: const Color(0xFFEDEDED),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text('${(util * 100).round()}% UTIL · $temp°C',
                          style: PT.mono(size: 11.5, color: PC.muted)),
                    ],
                  ),
                ),
                const SizedBox(width: 18),
                Text(status,
                    style: PT.mono(
                        size: 11.5,
                        color: status == 'IDLE' ? PC.muted : PC.green,
                        weight: FontWeight.w700)),
              ],
            ),
          ),
      ],
    );
  }
}
