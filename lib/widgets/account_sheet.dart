import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../state/studio_controller.dart';
import '../theme/photon_theme.dart';
import 'animated_profile_card.dart';

/// The account console: the [AnimatedBlueProfileCard] centred over a dimmed
/// backdrop. A backdrop click, Escape or the card's close button
/// dismisses it. The card holds the whole account (identity, plan and quota,
/// auth, keys and sessions) in its own tabs.
class AccountInspectorModal extends StatelessWidget {
  const AccountInspectorModal({super.key});

  /// The card's widest.
  static const double maxCardWidth = 560;

  @override
  Widget build(BuildContext context) {
    final studio = StudioScope.of(context);
    void close() => studio.setAccountModalOpen(false);
    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          close();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          GestureDetector(
            key: const Key('account-backdrop'),
            behavior: HitTestBehavior.opaque,
            onTap: close,
            // A flat architectural scrim, not a blur: a BackdropFilter re-blurs
            // the whole window behind the card on every frame the card tilts.
            // Its own layer, so it is painted once and only ever composited.
            child: RepaintBoundary(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.62),
                  gradient: RadialGradient(
                    radius: 0.9,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.22),
                    ],
                  ),
                ),
              ),
            ),
          ),
          LayoutBuilder(
            builder: (context, box) => Center(
              child: Padding(
                padding: const EdgeInsets.all(PhotonSpace.lg),
                child: ConstrainedBox(
                  // The card scrolls inside this height rather than overflow.
                  constraints: BoxConstraints(
                    maxWidth: maxCardWidth,
                    maxHeight: box.maxHeight - PhotonSpace.lg * 2,
                  ),
                  // Swallow clicks on the card so they do not reach the backdrop.
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {},
                    // Its own layer inside the modal: the card's tilt, ring and
                    // drawer never dirty the scrim behind it.
                    child: RepaintBoundary(
                      child: AnimatedBlueProfileCard(
                        key: const Key('animated-profile-card'),
                        onClose: close,
                      ),
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
