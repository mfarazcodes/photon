import 'package:flutter/material.dart';

import '../state/studio_controller.dart';
import '../theme/photon_theme.dart';
import 'photon_primitives.dart';

/// Shot manager: the studio's saved projects.
///
/// [Axis.vertical] is the 188px desktop column; [Axis.horizontal] is the
/// companion carousel. A card loads its project when tapped, or when dragged
/// onto `SCENE_VIEWPORT.rt` (the card carries the project id as a
/// `Draggable<String>`).
class ProjectsSidebar extends StatelessWidget {
  const ProjectsSidebar({super.key, this.axis = Axis.vertical});

  final Axis axis;

  static const double width = 188;
  static const double carouselCardWidth = 176;
  static const double carouselHeight = 112;

  @override
  Widget build(BuildContext context) {
    final studio = StudioScope.of(context);
    final vertical = axis == Axis.vertical;
    final projects = studio.projects;

    Widget card(StudioProject p) => _ProjectCard(
      project: p,
      selected: p.id == studio.activeProjectId,
      onSelect: () => studio.selectProject(p.id),
      onDuplicate: () => studio.duplicateProject(p.id),
      onDelete: () => studio.deleteProject(p.id),
      // Drag across the list's scroll axis so scrolling still works.
      dragAffinity: vertical ? Axis.horizontal : Axis.vertical,
    );

    final header = _Header(count: projects.length, onNew: studio.createNewProject);

    if (vertical) {
      return SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header,
            const SizedBox(height: PhotonSpace.sm),
            Expanded(
              child: ListView.separated(
                padding: EdgeInsets.zero,
                itemCount: projects.length,
                separatorBuilder: (_, _) => const SizedBox(height: PhotonSpace.sm),
                itemBuilder: (_, i) => card(projects[i]),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        const SizedBox(height: PhotonSpace.sm),
        SizedBox(
          height: carouselHeight,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.zero,
            itemCount: projects.length,
            separatorBuilder: (_, _) => const SizedBox(width: PhotonSpace.sm),
            itemBuilder: (_, i) => SizedBox(width: carouselCardWidth, child: card(projects[i])),
          ),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.count, required this.onNew});

  final int count;
  final VoidCallback onNew;

  @override
  Widget build(BuildContext context) {
    final t = context.photon;
    final c = t.colors;
    return SizedBox(
      height: 26,
      child: Row(
        children: [
          Icon(Icons.folder_open, size: 12, color: c.violetInk),
          const SizedBox(width: PhotonSpace.xs + 2),
          Flexible(
            child: Text('PROJECTS', maxLines: 1, overflow: TextOverflow.ellipsis, style: t.text.labelCaps),
          ),
          const SizedBox(width: PhotonSpace.xs + 2),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: c.violet.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(PhotonRadius.pill),
            ),
            child: Text('$count', style: t.text.labelCaps.copyWith(fontSize: 8, color: c.violetInk)),
          ),
          const Spacer(),
          Tooltip(
            message: 'New project from current settings',
            child: Semantics(
              button: true,
              label: 'New project',
              child: HoverBuilder(
                cursor: SystemMouseCursors.click,
                builder: (context, hovered) => GestureDetector(
                  key: const Key('new-project-btn'),
                  behavior: HitTestBehavior.opaque,
                  onTap: onNew,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    height: 22,
                    padding: const EdgeInsets.symmetric(horizontal: PhotonSpace.sm),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: hovered ? c.violet.withValues(alpha: 0.14) : Colors.transparent,
                      borderRadius: BorderRadius.circular(PhotonRadius.control),
                      border: Border.all(color: hovered ? c.violet : c.border),
                    ),
                    child: Text(
                      '+ NEW',
                      style: t.text.labelCaps.copyWith(fontSize: 8, color: hovered ? c.violetInk : c.textMuted),
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

class _ProjectCard extends StatelessWidget {
  const _ProjectCard({
    required this.project,
    required this.selected,
    required this.onSelect,
    required this.onDuplicate,
    required this.onDelete,
    required this.dragAffinity,
  });

  final StudioProject project;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback onDuplicate;
  final VoidCallback onDelete;
  final Axis dragAffinity;

  @override
  Widget build(BuildContext context) {
    return Draggable<String>(
      data: project.id,
      affinity: dragAffinity,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: Material(
        type: MaterialType.transparency,
        child: SizedBox(
          width: ProjectsSidebar.carouselCardWidth,
          child: _CardBody(project: project, selected: true, hovered: false, lifted: true),
        ),
      ),
      childWhenDragging: Opacity(
        opacity: 0.35,
        child: _CardBody(project: project, selected: false, hovered: false),
      ),
      child: Semantics(
        button: true,
        selected: selected,
        label: '${project.name}, ${project.status.label.toLowerCase()}. Tap to load, or drag onto the viewport.',
        child: HoverBuilder(
          cursor: SystemMouseCursors.click,
          builder: (context, hovered) => GestureDetector(
            key: ValueKey('project-${project.id}'),
            behavior: HitTestBehavior.opaque,
            onTap: onSelect,
            child: _CardBody(
              project: project,
              selected: selected,
              hovered: hovered,
              onDuplicate: onDuplicate,
              onDelete: onDelete,
            ),
          ),
        ),
      ),
    );
  }
}

class _CardBody extends StatelessWidget {
  const _CardBody({
    required this.project,
    required this.selected,
    required this.hovered,
    this.lifted = false,
    this.onDuplicate,
    this.onDelete,
  });

  final StudioProject project;
  final bool selected;
  final bool hovered;
  final bool lifted;
  final VoidCallback? onDuplicate;
  final VoidCallback? onDelete;

  static Color statusColor(PhotonPalette c, ProjectStatus s) => switch (s) {
    ProjectStatus.active => const Color(0xFF22C55E),
    ProjectStatus.rendered => c.violet,
    ProjectStatus.draft => const Color(0xFFF5A524),
  };

  @override
  Widget build(BuildContext context) {
    final t = context.photon;
    final c = t.colors;
    final status = statusColor(c, project.status);
    final borderColor = selected
        ? c.violet.withValues(alpha: 0.55)
        : hovered
        ? c.violet.withValues(alpha: 0.3)
        : c.border;

    final actions = hovered && onDuplicate != null && onDelete != null;

    return Container(
      decoration: BoxDecoration(
        color: selected ? Color.alphaBlend(c.violet.withValues(alpha: 0.08), c.substrate) : c.substrate,
        borderRadius: BorderRadius.circular(PhotonRadius.window),
        border: Border.all(color: borderColor),
        boxShadow: lifted ? t.causticGlow : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(PhotonSpace.md - 1, PhotonSpace.sm, PhotonSpace.sm, PhotonSpace.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(PhotonRadius.control),
                  child: SizedBox.square(
                    dimension: 32,
                    child: Image.asset(
                      project.previewAsset,
                      fit: BoxFit.cover,
                      cacheWidth: 96,
                      filterQuality: FilterQuality.medium,
                      errorBuilder: (_, _, _) => ColoredBox(color: c.hoverFill),
                    ),
                  ),
                ),
                const SizedBox(width: PhotonSpace.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              project.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: t.text.ui(size: 12, weight: FontWeight.w500, height: 1.3, tracking: -0.01),
                            ),
                          ),
                          if (actions) ...[
                            _MiniAction(
                              key: ValueKey('project-dup-${project.id}'),
                              icon: Icons.copy,
                              tooltip: 'Duplicate',
                              onTap: onDuplicate!,
                            ),
                            _MiniAction(
                              key: ValueKey('project-del-${project.id}'),
                              icon: Icons.close,
                              tooltip: 'Delete',
                              onTap: onDelete!,
                            ),
                          ] else
                            Tooltip(
                              message: project.status.label,
                              child: Pip(color: status, size: 6, glow: project.status == ProjectStatus.active),
                            ),
                        ],
                      ),
                      Text(
                        project.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.text.mono(size: 9, height: 1.4, color: c.textMuted),
                      ),
                      const SizedBox(height: 5),
                      // SPP and IOR; scales down rather than overflow.
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: c.hoverFill,
                            borderRadius: BorderRadius.circular(PhotonRadius.pill),
                          ),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              '${project.spp} SPP · IOR ${project.ior.toStringAsFixed(3)}',
                              maxLines: 1,
                              style: t.text.mono(size: 9, height: 1.2, weight: FontWeight.w500),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Pip(color: status, size: 5),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              '${project.status.label} · ${project.updatedAt}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: t.text.labelCaps.copyWith(fontSize: 7.5, letterSpacing: 0.4, color: c.ghost),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Active-project accent bar.
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: 3,
            child: ColoredBox(color: selected ? c.violet : Colors.transparent),
          ),
        ],
      ),
    );
  }
}

class _MiniAction extends StatelessWidget {
  const _MiniAction({super.key, required this.icon, required this.tooltip, required this.onTap});

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.photon.colors;
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        child: HoverBuilder(
          cursor: SystemMouseCursors.click,
          builder: (context, hovered) => GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: Container(
              width: 20,
              height: 18,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: hovered ? c.hoverFill : Colors.transparent,
                borderRadius: BorderRadius.circular(PhotonRadius.control - 1),
              ),
              child: Icon(icon, size: 11, color: hovered ? c.carbon : c.textMuted),
            ),
          ),
        ),
      ),
    );
  }
}
