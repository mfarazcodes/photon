// VeriTrust – scroll-style marketing frontend in Flutter.
// Structure mirrors the reference site: entry gate -> sticky nav -> hero ->
// four feature sections -> numbered skills -> ROI calculator -> closing CTA.
// Replace lib/main.dart with this file and run: flutter run -d chrome

import 'package:flutter/material.dart';

void main() => runApp(const VeriTrustApp());

// ---------------------------------------------------------------------------
// Colors. Change these in one place to restyle the whole app.
// (These are my guesses: I could not see the reference site's real colors.)
// ---------------------------------------------------------------------------
class Palette {
  static const bg = Color(0xFF05121C);
  static const surface = Color(0xFF0C2233);
  static const accent = Color(0xFF3DDBD9);
  static const text = Color(0xFFEAF4F8);
  static const muted = Color(0xFF8CA6B5);
  static const line = Color(0x33FFFFFF);
  static const barBg = Color(0xE605121C);
}

class VeriTrustApp extends StatelessWidget {
  const VeriTrustApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'VeriTrust',
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Palette.bg,
        colorScheme: const ColorScheme.dark(primary: Palette.accent),
      ),
      home: const EntryGate(),
    );
  }
}

// ---------------------------------------------------------------------------
// 1. Entry gate: "Enter with sound / Enter without sound"
// ---------------------------------------------------------------------------
class EntryGate extends StatefulWidget {
  const EntryGate({super.key});

  @override
  State<EntryGate> createState() => _EntryGateState();
}

class _EntryGateState extends State<EntryGate> {
  bool? _soundOn; // null = not entered yet

  @override
  Widget build(BuildContext context) {
    if (_soundOn != null) return HomePage(soundOn: _soundOn!);

    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('VeriTrust',
                style: TextStyle(fontSize: 40, fontWeight: FontWeight.w700)),
            const SizedBox(height: 32),
            FilledButton(
              onPressed: () => setState(() => _soundOn = true),
              child: const Text('Enter with sound'),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => setState(() => _soundOn = false),
              child: const Text('Enter without sound'),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 2. Home page: scrolling sections + sticky top bar
// ---------------------------------------------------------------------------
const _navItems = [
  'Intro',
  'Live Data',
  'Governance',
  'Security',
  'Adapt',
  'Skills',
  'Calculator',
];

class Feature {
  final String nav, title, teaser, detail;
  const Feature(this.nav, this.title, this.teaser, this.detail);
}

// Placeholder copy: replace with your real VeriTrust text.
const _features = [
  Feature(
    'Live Data',
    'Live Data',
    'Threat signals are read the moment they arrive, so decisions never wait for yesterday\'s report.',
    'Describe how VeriTrust ingests and analyzes data in real time.',
  ),
  Feature(
    'Governance',
    'Governance',
    'Every check follows clear rules, and every action can be traced back to who or what made it.',
    'Describe your policies, audit trail and access controls here.',
  ),
  Feature(
    'Security',
    'Security',
    'Verification runs inside your own environment, so sensitive data stays where it already lives.',
    'Describe encryption, data residency and how you verify trust.',
  ),
  Feature(
    'Adapt',
    'Adapt',
    'New threats do not need a new system. VeriTrust applies what it has already learned.',
    'Describe how the model learns from new attack patterns.',
  ),
];

const _skills = [
  'Collect',
  'Verify',
  'Analyze',
  'Score',
  'Alert',
  'Contain',
  'Report',
  'Learn',
];

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.soundOn});
  final bool soundOn; // use this later if you add background audio

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // One key per section so the nav bar can scroll to it.
  final Map<String, GlobalKey> _keys = {
    for (final name in _navItems) name: GlobalKey(),
  };

  void _goTo(String name) {
    final ctx = _keys[name]!.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          SingleChildScrollView(
            child: Column(
              children: [
                LandingHeroSection(key: _keys['Intro']),
                for (final f in _features)
                  FeatureSection(key: _keys[f.nav], feature: f),
                SkillsSection(key: _keys['Skills']),
                RoiCalculator(key: _keys['Calculator']),
                const Footer(),
              ],
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: TopBar(onNav: _goTo),
          ),
        ],
      ),
    );
  }
}

class TopBar extends StatelessWidget {
  const TopBar({super.key, required this.onNav});
  final void Function(String) onNav;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width >= 900;
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: const BoxDecoration(
        color: Palette.barBg,
        border: Border(bottom: BorderSide(color: Palette.line)),
      ),
      child: Row(
        children: [
          const Text('VeriTrust',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          const Spacer(),
          if (wide)
            for (final item in _navItems)
              TextButton(
                onPressed: () => onNav(item),
                child: Text(item,
                    style: const TextStyle(color: Palette.muted)),
              )
          else
            PopupMenuButton<String>(
              icon: const Icon(Icons.menu),
              onSelected: onNav,
              itemBuilder: (_) => [
                for (final item in _navItems)
                  PopupMenuItem(value: item, child: Text(item)),
              ],
            ),
          const SizedBox(width: 12),
          OutlinedButton(
            onPressed: () {}, // TODO: open your contact page / form
            child: const Text('Talk to an expert'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared layout helper: centers content and caps its width
// ---------------------------------------------------------------------------
class Section extends StatelessWidget {
  const Section({super.key, required this.child, this.minHeight = 0});
  final Widget child;
  final double minHeight;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      constraints: BoxConstraints(minHeight: minHeight),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 72),
      alignment: Alignment.center,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1000),
        child: child,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 3. Hero
// ---------------------------------------------------------------------------
// Named Hero_ because Flutter already has a widget called Hero.
class LandingHeroSection extends StatelessWidget {
  const LandingHeroSection({super.key});

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final h = MediaQuery.of(context).size.height;
    return Section(
      minHeight: h,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'Smarter Security.\nEmbedded AI.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: w < 600 ? 40 : 72,
              fontWeight: FontWeight.w800,
              height: 1.05,
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'See how VeriTrust verifies trust inside your own environment.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 18, color: Palette.muted),
          ),
          const SizedBox(height: 48),
          const Text('Scroll', style: TextStyle(color: Palette.muted)),
          const Icon(Icons.keyboard_arrow_down, color: Palette.muted),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 4. Feature sections with an expandable "In Practice" area
// ---------------------------------------------------------------------------
class FeatureSection extends StatefulWidget {
  const FeatureSection({super.key, required this.feature});
  final Feature feature;

  @override
  State<FeatureSection> createState() => _FeatureSectionState();
}

class _FeatureSectionState extends State<FeatureSection> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final f = widget.feature;
    return Section(
      minHeight: MediaQuery.of(context).size.height * 0.7,
      child: Align(
        alignment: Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(f.title,
                  style: const TextStyle(
                      fontSize: 48, fontWeight: FontWeight.w700)),
              const SizedBox(height: 16),
              Text(f.teaser,
                  style: const TextStyle(
                      fontSize: 18, height: 1.5, color: Palette.muted)),
              const SizedBox(height: 24),
              TextButton.icon(
                onPressed: () => setState(() => _open = !_open),
                icon: Icon(_open ? Icons.remove : Icons.add),
                label: const Text('In Practice'),
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 250),
                alignment: Alignment.topLeft,
                child: _open
                    ? Container(
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Palette.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Palette.line),
                  ),
                  child: Text(f.detail,
                      style: const TextStyle(height: 1.5)),
                )
                    : const SizedBox(width: double.infinity),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 5. Skills: a real sequence, so numbering makes sense here
// ---------------------------------------------------------------------------
class SkillsSection extends StatelessWidget {
  const SkillsSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Section(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Discover VeriTrust\'s Skills',
              style: TextStyle(fontSize: 40, fontWeight: FontWeight.w700)),
          const SizedBox(height: 32),
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              for (var i = 0; i < _skills.length; i++)
                Container(
                  width: 220,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Palette.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Palette.line),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 14,
                        backgroundColor: Palette.accent,
                        child: Text('${i + 1}',
                            style: const TextStyle(
                                color: Palette.bg,
                                fontWeight: FontWeight.w700)),
                      ),
                      const SizedBox(width: 12),
                      Text(_skills[i],
                          style: const TextStyle(fontSize: 18)),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 6. Impact calculator (placeholder formula: replace with your own)
// ---------------------------------------------------------------------------
String _fmt(num n) => n
    .round()
    .toString()
    .replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');

class RoiCalculator extends StatefulWidget {
  const RoiCalculator({super.key});

  @override
  State<RoiCalculator> createState() => _RoiCalculatorState();
}

class _RoiCalculatorState extends State<RoiCalculator> {
  String _symbol = '\$';
  double _analysts = 50;
  double _manualPct = 45;
  double _salary = 85000;

  Widget _slider(String label, double value, double min, double max,
      String shown, ValueChanged<double> onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(child: Text(label)),
              Text(shown,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ],
          ),
          Slider(value: value, min: min, max: max, onChanged: onChanged),
        ],
      ),
    );
  }

  Widget _result(String label, String value) {
    return Container(
      width: 260,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Palette.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Palette.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Palette.muted)),
          const SizedBox(height: 8),
          Text(value,
              style:
              const TextStyle(fontSize: 32, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Placeholder math: 2,080 working hours a year, 40% of manual work automated.
    final hoursSaved = _analysts * 2080 * (_manualPct / 100) * 0.4;
    final costSaved = hoursSaved * (_salary / 2080);

    return Section(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('See what this could mean for your team',
              style: TextStyle(fontSize: 40, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          const Text('Calculate your potential impact in under a minute.',
              style: TextStyle(color: Palette.muted, fontSize: 18)),
          const SizedBox(height: 24),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: '€', label: Text('EUR')),
              ButtonSegment(value: '\$', label: Text('USD')),
              ButtonSegment(value: '£', label: Text('GBP')),
            ],
            selected: {_symbol},
            onSelectionChanged: (s) => setState(() => _symbol = s.first),
          ),
          const SizedBox(height: 24),
          _slider('Number of analysts', _analysts, 5, 200,
              _fmt(_analysts), (v) => setState(() => _analysts = v)),
          _slider('% of time on manual review', _manualPct, 10, 70,
              '${_manualPct.round()}%', (v) => setState(() => _manualPct = v)),
          _slider('Average annual salary', _salary, 20000, 175000,
              '$_symbol${_fmt(_salary)}', (v) => setState(() => _salary = v)),
          const SizedBox(height: 16),
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              _result('Hours saved per year', '${_fmt(hoursSaved)} hrs'),
              _result('Estimated savings per year',
                  '$_symbol${_fmt(costSaved)}'),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 7. Closing call to action + footer
// ---------------------------------------------------------------------------
class Footer extends StatelessWidget {
  const Footer({super.key});

  @override
  Widget build(BuildContext context) {
    return Section(
      child: Column(
        children: [
          const Text(
            'Ready to see how VeriTrust can work for you?',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 40, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () {}, // TODO: link to your demo request
            child: const Text('Request a demo'),
          ),
          const SizedBox(height: 48),
          const Divider(color: Palette.line),
          const SizedBox(height: 16),
          const Text('Privacy Policy  |  Made by your team name',
              style: TextStyle(color: Palette.muted)),
        ],
      ),
    );
  }
}