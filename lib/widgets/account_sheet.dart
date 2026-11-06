import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../state/studio_controller.dart';
import '../theme/photon_theme.dart';
import 'animated_profile_card.dart';

/// The account console: the [AnimatedBlueProfileCard] centred over a dimmed,
/// blurred backdrop. A backdrop click, Escape or the card's close button
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
            key: const Key('account-backdrop'),
            behavior: HitTestBehavior.opaque,
            onTap: close,
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
              child: ColoredBox(color: Colors.black.withValues(alpha: 0.5)),
            ),
          ),
          LayoutBuilder(
            builder: (context, box) => Center(
              child: Padding(
                padding: const EdgeInsets.all(PhotonSpace.lg),
                child: ConstrainedBox(
                  // The card scrolls inside this height rather than overflow.
                  constraints: BoxConstraints(maxWidth: maxCardWidth, maxHeight: box.maxHeight - PhotonSpace.lg * 2),
                  // Swallow clicks on the card so they do not reach the backdrop.
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {},
                    child: AnimatedBlueProfileCard(key: const Key('animated-profile-card'), onClose: close),
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
