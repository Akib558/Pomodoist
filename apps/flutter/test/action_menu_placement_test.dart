import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pomodoist/ui/core/widgets/app_action_menu.dart';
import 'package:pomodoist/ui/core/widgets/app_context_menu_region.dart';

void main() {
  test('pointer menus use space above bottom tasks and stay at the click', () {
    const origin = Offset(100, 600);
    const viewport = Rect.fromLTRB(0, 24, 1000, 700);
    final placement = contextMenuPlacement(
      const Offset(200, 680),
      origin,
      viewport,
    );
    expect(placement.maxHeight, greaterThan(6 * 44));
    expect(placement.maxHeight, lessThan(680 - 24));
    expect(placement.anchor.followerAnchor.resolve(TextDirection.ltr).y, -1);
    expect(placement.anchor.offset + origin, const Offset(200, 676));

    final top = contextMenuPlacement(const Offset(200, 40), origin, viewport);
    expect(top.anchor.followerAnchor.resolve(TextDirection.ltr).y, 1);
    expect(top.anchor.offset + origin, const Offset(200, 44));

    // A keyboard or bottom panel can cover the original pointer position.
    final covered = contextMenuPlacement(
      const Offset(200, 680),
      origin,
      const Rect.fromLTRB(0, 24, 1000, 400),
    );
    expect(covered.anchor.offset + origin, const Offset(200, 396));
    expect(covered.maxHeight, inExclusiveRange(6 * 44, 400 - 24));
  });

  test('menus choose the larger side and scroll within that space', () {
    const viewport = Rect.fromLTRB(0, 24, 1000, 780);
    for (final (trigger, below, left) in [
      (const Rect.fromLTWH(900, 60, 48, 48), true, true),
      (const Rect.fromLTWH(20, 650, 48, 48), false, false),
      (const Rect.fromLTWH(900, 420, 48, 48), false, true),
    ]) {
      final placement = actionMenuPlacement(trigger, viewport);
      final target = placement.anchor.targetAnchor.resolve(TextDirection.ltr);
      final follower = placement.anchor.followerAnchor.resolve(
        TextDirection.ltr,
      );
      expect(target.y, below ? 1 : -1);
      // ShadAnchorAuto subtracts menu height for a top follower.
      expect(follower.y, target.y);
      expect(follower.x, left ? -1 : 1);
      final available = below
          ? viewport.bottom - trigger.bottom
          : trigger.top - viewport.top;
      expect(placement.maxHeight, greaterThanOrEqualTo(0));
      expect(placement.maxHeight, lessThan(available));
    }
    const trigger = Rect.fromLTWH(450, 330, 48, 48);
    expect(
      actionMenuPlacement(
        trigger,
        viewport,
      ).anchor.targetAnchor.resolve(TextDirection.ltr).y,
      1,
    );
    expect(
      actionMenuPlacement(
        trigger,
        const Rect.fromLTRB(0, 24, 1000, 480),
      ).anchor.targetAnchor.resolve(TextDirection.ltr).y,
      -1,
    );
    expect(
      actionMenuPlacement(
        trigger,
        const Rect.fromLTRB(0, 330, 1000, 378),
      ).maxHeight,
      0,
    );
  });
}
