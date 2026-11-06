import 'dart:io';

/// The file types the open dialog lists first: scene and image files, then
/// everything else.
const String kIngestFileFilter =
    'Scene and image files|*.png;*.jpg;*.jpeg;*.webp;*.bmp;*.gif;*.usd;*.usda;*.usdc;*.exr;*.hdr;*.obj;*.bsdf;*.ior'
    '|All files|*.*';

/// Shows the Windows open-file dialog and returns the chosen path.
///
/// It runs PowerShell's `System.Windows.Forms.OpenFileDialog` in a single-
/// threaded apartment and reads the path from its output. It returns null when
/// the user cancels, on any platform but Windows, when PowerShell cannot be
/// started, and under `flutter test` (a dialog must never open from a test).
/// The caller falls back to typing a path.
Future<String?> pickLocalFileNative() async {
  if (!Platform.isWindows) return null;
  if (Platform.environment.containsKey('FLUTTER_TEST')) return null;
  const script = '''
Add-Type -AssemblyName System.Windows.Forms
\$dialog = New-Object System.Windows.Forms.OpenFileDialog
\$dialog.Title = 'Bring a file into Photon'
\$dialog.Filter = '$kIngestFileFilter'
\$dialog.CheckFileExists = \$true
if (\$dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { [Console]::Out.Write(\$dialog.FileName) }
''';
  try {
    final result = await Process.run('powershell.exe', ['-NoProfile', '-STA', '-Command', script]);
    if (result.exitCode != 0) return null;
    final path = (result.stdout as String).trim();
    return path.isEmpty ? null : path;
  } on ProcessException {
    return null;
  }
}
