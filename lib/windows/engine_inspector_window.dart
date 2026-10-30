import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/desktop_node.dart';
import '../painters/glyph_painters.dart';
import '../painters/pass_painter.dart';
import '../state/workspace_controller.dart';
import '../theme/photon_theme.dart';
import '../widgets/sim_view.dart';

/// Inspector opened from the central PHOTON_ENGINE_V3.4 card.
class EngineInspectorContent extends StatefulWidget {
  const EngineInspectorContent({super.key});

  @override
  State<EngineInspectorContent> createState() => _EngineInspectorContentState();
}

class _EngineInspectorContentState extends State<EngineInspectorContent> {
  final _rng = math.Random();
  int _seed = 884213;
  String _build = 'Stable 3.4.2';

  @override
  Widget build(BuildContext context) {
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: true),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
        children: [
          _header(),
          const SizedBox(height: 22),
          InspectorSection(
            title: 'Prompt & Seed',
            initiallyOpen: true,
            child: _promptSection(),
          ),
          InspectorSection(title: 'Field Dynamics & Sliders', child: _fieldsSection()),
          InspectorSection(title: 'Render Telemetry', child: _telemetrySection()),
          InspectorSection(
            title: 'Output Pass Gallery',
            initiallyOpen: true,
            child: _gallery(),
          ),
        ],
      ),
    );
  }

  Widget _header() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: const SizedBox(width: 150, height: 150, child: SimView(kind: SimKind.core)),
        ),
        const SizedBox(width: 20),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 34),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Photon Core v3.4',
                    style: PT.label(size: 34, weight: FontWeight.w700, spacing: -0.6)),
                const SizedBox(height: 4),
                Text('Neural Radiance & Particle Solver  ·  CUDA / Vulkan Compute',
                    style: PT.label(size: 17, color: PC.inkSoft, weight: FontWeight.w400)),
                const SizedBox(height: 12),
                const Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _Tag('NeRF'),
                    _Tag('SPH'),
                    _Tag('15K PARTICLES'),
                    _Tag('FP16'),
                    _Tag('OPTIX DENOISE'),
                  ],
                ),
              ],
            ),
          ),
        ),
        PopupMenuButton<String>(
          tooltip: 'Engine build',
          onSelected: (v) => setState(() => _build = v),
          color: PC.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          itemBuilder: (_) => [
            for (final b in ['Stable 3.4.2', 'Nightly 3.5.0-dev', 'LTS 3.2.9'])
              PopupMenuItem(value: b, child: Text(b, style: PT.label(size: 14))),
          ],
          child: Padding(
            padding: const EdgeInsets.only(top: 22),
            child: Row(
              children: [
                Text(_build, style: PT.label(size: 16, weight: FontWeight.w600)),
                const Icon(Icons.keyboard_arrow_down_rounded, size: 20),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _promptSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'A volumetric shockwave rippling through iridescent chrome nanobots, '
          'caustic light spilling across wet marble, 35mm anamorphic, 120fps slow motion.',
          style: PT.body(size: 17),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _Stat('SEED', '$_seed'),
            const _Stat('CFG', '7.5'),
            const _Stat('STEPS', '48'),
            const _Stat('SAMPLER', 'DPM++ 2M'),
            TextButton.icon(
              onPressed: () => setState(() => _seed = 100000 + _rng.nextInt(899999)),
              icon: const Icon(Icons.casino_outlined, size: 18, color: PC.blue),
              label: Text('Reroll', style: PT.label(size: 15, color: PC.blue)),
            ),
          ],
        ),
      ],
    );
  }

  Widget _fieldsSection() {
    final params = WorkspaceScope.read(context).params;
    final fields = <({String label, double min, double max, double Function() get, void Function(double) set})>[
      (label: 'Turbulence', min: 0, max: 1, get: () => params.turbulence, set: (v) => params.update(turbulence: v)),
      (label: 'Coherence', min: 0, max: 1, get: () => params.coherence, set: (v) => params.update(coherence: v)),
      (label: 'Particle Density', min: 0, max: 1, get: () => params.density, set: (v) => params.update(density: v)),
      (label: 'Chromatic Dispersion', min: 0, max: 1, get: () => params.dispersion, set: (v) => params.update(dispersion: v)),
      (label: 'Time Scale', min: 0.25, max: 2, get: () => params.timeScale, set: (v) => params.update(timeScale: v)),
    ];
    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: 2,
        activeTrackColor: PC.ink,
        inactiveTrackColor: PC.hairline,
        thumbColor: PC.ink,
        overlayShape: SliderComponentShape.noOverlay,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
      ),
      // These write straight into the workspace's shared SimParams; every
      // SimView and viewport reads them each frame, so changes are live.
      child: ListenableBuilder(
        listenable: params,
        builder: (context, _) => Column(
          children: [
            for (final f in fields)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    SizedBox(width: 170, child: Text(f.label, style: PT.label(size: 15))),
                    Expanded(
                      child: Slider(
                        value: f.get().clamp(f.min, f.max),
                        min: f.min,
                        max: f.max,
                        onChanged: f.set,
                      ),
                    ),
                    SizedBox(
                      width: 52,
                      child: Text(f.get().toStringAsFixed(2),
                          textAlign: TextAlign.right, style: PT.mono(size: 13)),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _telemetrySection() {
    List<double> walk(int seed) {
      final r = math.Random(seed);
      var v = 0.5;
      return [for (var i = 0; i < 32; i++) v = (v + (r.nextDouble() - 0.5) * 0.25).clamp(0.05, 1.0)];
    }

    const stats = [
      ('GPU UTIL', '92%', 1),
      ('VRAM', '18.4 / 24 GB', 2),
      ('FRAME TIME', '16.4 ms', 3),
      ('RAYS / SEC', '2.1 G', 4),
    ];
    return LayoutBuilder(builder: (context, c) {
      final tileW = (c.maxWidth - 12 * 3) / 4;
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (final (label, value, seed) in stats)
            Container(
              width: math.max(tileW, 160),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: PC.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: PC.hairline),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: PT.mono(size: 11, color: PC.muted)),
                  const SizedBox(height: 4),
                  Text(value, style: PT.label(size: 22, weight: FontWeight.w700)),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 34,
                    width: double.infinity,
                    child: CustomPaint(painter: SparklinePainter(values: walk(seed))),
                  ),
                ],
              ),
            ),
        ],
      );
    });
  }

  Widget _gallery() {
    final items = <(String, Widget)>[
      for (var i = 0; i < kPassNames.length; i++)
        (
          '${(i + 1).toString().padLeft(2, '0')}  ${kPassNames[i].toUpperCase()}',
          TimeBuilder(builder: (_, t) => CustomPaint(painter: PassPainter(pass: i, time: t))),
        ),
      ('06  CHROME', const SimView(kind: SimKind.chrome)),
      ('07  CAUSTICS', const SimView(kind: SimKind.caustics)),
    ];
    return SizedBox(
      height: 300,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, i) {
          final (label, child) = items[i];
          return ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: SizedBox(
              width: 420,
              child: Stack(
                children: [
                  Positioned.fill(child: child),
                  Positioned(
                    left: 12,
                    bottom: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: const Color(0x99000000),
                        borderRadius: BorderRadius.circular(100),
                      ),
                      child: Text(label,
                          style: PT.mono(size: 11.5, color: PC.white, weight: FontWeight.w700)),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Collapsible section with a rotating chevron, as in the reference modal.
class InspectorSection extends StatefulWidget {
  const InspectorSection({
    super.key,
    required this.title,
    required this.child,
    this.initiallyOpen = false,
  });

  final String title;
  final Widget child;
  final bool initiallyOpen;

  @override
  State<InspectorSection> createState() => _InspectorSectionState();
}

class _InspectorSectionState extends State<InspectorSection> {
  late bool _open = widget.initiallyOpen;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Row(
                children: [
                  Text(widget.title, style: PT.label(size: 19, weight: FontWeight.w600)),
                  const SizedBox(width: 6),
                  AnimatedRotation(
                    turns: _open ? 0 : 0.5,
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeOutCubic,
                    child: const Icon(Icons.keyboard_arrow_up_rounded, size: 22),
                  ),
                ],
              ),
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 340),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: _open
              ? Padding(
                  padding: const EdgeInsets.only(bottom: 18),
                  child: widget.child,
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: PC.blueSoft,
        borderRadius: BorderRadius.circular(100),
      ),
      child: Text(text, style: PT.mono(size: 11, color: PC.blue, weight: FontWeight.w700)),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: PC.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: PC.hairline),
      ),
      child: RichText(
        text: TextSpan(
          children: [
            TextSpan(text: '$label  ', style: PT.mono(size: 11.5, color: PC.muted)),
            TextSpan(text: value, style: PT.mono(size: 13, weight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}
