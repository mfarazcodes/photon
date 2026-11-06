import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/studio_project.dart';
import '../state/studio_controller.dart';
import '../theme/photon_theme.dart';
import 'intent_file_trigger.dart';
import 'photon_primitives.dart';

/// The new-project popup: a name, what the project is about, and, if the user
/// wants one, a picture.
///
/// Nothing is pre-filled and no image is added unless one is chosen here: the
/// project starts blank. The picture can be browsed for on disk (the native
/// file dialog), or its path or a direct `https://` link typed or pasted.
/// Escape, CANCEL or a click outside closes it without creating anything.
class NewProjectSheet extends StatefulWidget {
  const NewProjectSheet({super.key});

  @override
  State<NewProjectSheet> createState() => _NewProjectSheetState();
}

class _NewProjectSheetState extends State<NewProjectSheet> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _about = TextEditingController();
  final TextEditingController _image = TextEditingController();
  final FocusNode _nameFocus = FocusNode(debugLabel: 'new-project-name');
  final FocusNode _imageFocus = FocusNode(debugLabel: 'new-project-image');

  /// What went wrong, or what to do next.
  String? _note;
  bool _browsing = false;

  @override
  void dispose() {
    _name.dispose();
    _about.dispose();
    _image.dispose();
    _nameFocus.dispose();
    _imageFocus.dispose();
    super.dispose();
  }

  Future<void> _browse() async {
    if (_browsing) return;
    final studio = StudioScope.read(context);
    setState(() => _browsing = true);
    final picked = await studio.pickLocalFile();
    if (!mounted) return;
    setState(() {
      _browsing = false;
      if (picked == null) {
        _note = 'NO FILE CHOSEN · TYPE OR PASTE A PATH OR LINK';
      } else {
        _image.text = picked;
        _note = null;
      }
    });
    if (picked == null) _imageFocus.requestFocus();
  }

  void _create() {
    final studio = StudioScope.read(context);
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _note = 'NAME YOUR PROJECT');
      _nameFocus.requestFocus();
      return;
    }
    var source = _image.text.trim();
    if (source.length > 1 && source.startsWith('"') && source.endsWith('"')) {
      source = source.substring(1, source.length - 1).trim();
    }

    Uint8List? bytes;
    String? path;
    String? url;
    if (source.isNotEmpty) {
      final uri = Uri.tryParse(source);
      final isLink = uri != null && (uri.scheme == 'http' || uri.scheme == 'https') && uri.host.isNotEmpty;
      if (isLink) {
        url = source;
      } else {
        final file = File(source);
        if (!file.existsSync()) {
          setState(() => _note = 'IMAGE NOT FOUND · CHECK THE PATH OR LINK');
          _imageFocus.requestFocus();
          return;
        }
        final dot = source.lastIndexOf('.');
        final ext = dot > 0 ? source.substring(dot + 1).toLowerCase() : '';
        if (!kImageExtensions.contains(ext)) {
          setState(() => _note = 'NOT AN IMAGE · USE .PNG .JPG .WEBP .BMP OR .GIF');
          _imageFocus.requestFocus();
          return;
        }
        path = source;
        if (file.lengthSync() <= FileIngestSheet.maxInlineImageBytes) bytes = file.readAsBytesSync();
      }
    }
    studio.createNewProject(name, _about.text, bytes, path, url);
  }

  @override
  Widget build(BuildContext context) {
    final studio = StudioScope.of(context);
    final t = context.photon;
    final c = t.colors;
    void close() => studio.setNewProjectSheetOpen(false);

    InputDecoration decoration(String hint, {Widget? suffix}) {
      OutlineInputBorder border(Color color) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(PhotonRadius.control + 2),
        borderSide: BorderSide(color: color),
      );
      return InputDecoration(
        isDense: true,
        filled: true,
        fillColor: c.canvas,
        hintText: hint,
        hintStyle: t.text.ui(size: 12, color: c.ghost),
        contentPadding: const EdgeInsets.symmetric(horizontal: PhotonSpace.sm + 2, vertical: PhotonSpace.sm + 1),
        border: border(c.border),
        enabledBorder: border(c.border),
        focusedBorder: border(c.violet),
        suffixIcon: suffix,
      );
    }

    Widget label(String text) => Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(text, style: t.text.labelCaps.copyWith(fontSize: 8, color: c.ghost)),
    );

    return Focus(
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
          close();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          GestureDetector(
            key: const Key('new-project-backdrop'),
            behavior: HitTestBehavior.opaque,
            onTap: close,
            child: ColoredBox(color: Colors.black.withValues(alpha: 0.5)),
          ),
          Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 460, maxHeight: MediaQuery.sizeOf(context).height),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {},
                child: Container(
                  key: const Key('new-project-modal'),
                  margin: const EdgeInsets.all(PhotonSpace.lg),
                  padding: const EdgeInsets.all(PhotonSpace.md),
                  decoration: BoxDecoration(
                    color: c.substrate,
                    borderRadius: BorderRadius.circular(PhotonRadius.window),
                    border: Border.all(color: c.border),
                    boxShadow: t.level2,
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.add_box_outlined, size: 14, color: c.violetInk),
                            const SizedBox(width: PhotonSpace.sm - 2),
                            Expanded(child: Text('NEW PROJECT', style: t.text.labelCaps.copyWith(color: c.carbon))),
                            Semantics(
                              button: true,
                              label: 'Close',
                              child: GestureDetector(
                                key: const Key('new-project-close'),
                                behavior: HitTestBehavior.opaque,
                                onTap: close,
                                child: Padding(padding: const EdgeInsets.all(4), child: Icon(Icons.close, size: 13, color: c.textMuted)),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: PhotonSpace.md),
                        label('PROJECT NAME'),
                        TextField(
                          key: const Key('new-project-name'),
                          controller: _name,
                          focusNode: _nameFocus,
                          autofocus: true,
                          maxLines: 1,
                          textInputAction: TextInputAction.next,
                          style: t.text.ui(size: 12, color: c.carbon),
                          cursorColor: c.violetInk,
                          decoration: decoration('e.g. Chronos Watch · Hero Shot'),
                          onChanged: (_) {
                            if (_note != null) setState(() => _note = null);
                          },
                        ),
                        const SizedBox(height: PhotonSpace.md - 2),
                        label('DETAILS (OPTIONAL)'),
                        TextField(
                          key: const Key('new-project-details'),
                          controller: _about,
                          minLines: 3,
                          maxLines: 4,
                          style: t.text.ui(size: 12, height: 1.4, color: c.carbon),
                          cursorColor: c.violetInk,
                          decoration: decoration('What is this project about?'),
                        ),
                        const SizedBox(height: PhotonSpace.md - 2),
                        label('IMAGE (OPTIONAL)'),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                key: const Key('new-project-image'),
                                controller: _image,
                                focusNode: _imageFocus,
                                maxLines: 1,
                                textInputAction: TextInputAction.done,
                                style: t.text.mono(size: 10.5, height: 1.3, color: c.carbon),
                                cursorColor: c.violetInk,
                                decoration: decoration('Path to an image, or a https:// link'),
                                onChanged: (_) {
                                  if (_note != null) setState(() => _note = null);
                                },
                                onSubmitted: (_) => _create(),
                              ),
                            ),
                            const SizedBox(width: PhotonSpace.sm),
                            _SheetButton(
                              key: const Key('new-project-browse'),
                              label: _browsing ? 'OPENING...' : 'BROWSE...',
                              icon: Icons.folder_open,
                              onTap: _browse,
                            ),
                          ],
                        ),
                        const SizedBox(height: PhotonSpace.xs + 2),
                        Text(
                          _note ?? 'NO IMAGE IS ADDED UNLESS YOU CHOOSE ONE · THE PROJECT STARTS BLANK',
                          key: const Key('new-project-note'),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: t.text.labelCaps.copyWith(fontSize: 7.5, color: _note == null ? c.ghost : c.rose),
                        ),
                        const SizedBox(height: PhotonSpace.md),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            _SheetButton(key: const Key('new-project-cancel'), label: 'CANCEL', onTap: close),
                            const SizedBox(width: PhotonSpace.sm),
                            _SheetButton(
                              key: const Key('new-project-create'),
                              label: 'CREATE PROJECT',
                              icon: Icons.check,
                              primary: true,
                              onTap: _create,
                            ),
                          ],
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

class _SheetButton extends StatelessWidget {
  const _SheetButton({super.key, required this.label, required this.onTap, this.icon, this.primary = false});

  final String label;
  final VoidCallback onTap;
  final IconData? icon;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final t = context.photon;
    final c = t.colors;
    return Semantics(
      button: true,
      label: label,
      child: HoverBuilder(
        cursor: SystemMouseCursors.click,
        builder: (context, hovered) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: PhotonSpace.md - 2),
            decoration: BoxDecoration(
              color: primary
                  ? (hovered ? Color.alphaBlend(c.onCarbon.withValues(alpha: 0.14), c.carbon) : c.carbon)
                  : (hovered ? c.violet.withValues(alpha: 0.14) : Colors.transparent),
              borderRadius: BorderRadius.circular(PhotonRadius.control + 2),
              border: Border.all(color: primary ? Colors.transparent : (hovered ? c.violet : c.border)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 13, color: primary ? c.onCarbon : c.textMuted),
                  const SizedBox(width: PhotonSpace.sm - 2),
                ],
                Text(
                  label,
                  maxLines: 1,
                  style: t.text.labelCaps.copyWith(fontSize: 8.5, color: primary ? c.onCarbon : c.carbon, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
