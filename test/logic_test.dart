import 'package:better_idle/src/activities.dart';
import 'package:better_idle/src/state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('consumeTicks completes activity and adds toast', () {
    final normalTree = actionRegistry.byName('Normal Tree'); // Normal Tree (3s)
    var state = GlobalState.empty();

    // Start activity
    state = state.startAction(normalTree);

    // Advance time by 3 seconds (30 ticks)
    // consumeTicks takes state and ticks
    // 3s = 3000ms. tickDuration = 100ms. So 30 ticks.
    final builder = StateUpdateBuilder(state);
    consumeTicks(builder, 30);
    state = builder.build();

    // Verify activity completed (progress reset or activity cleared? logic says reset)
    expect(state.activeAction?.progressTicks, 0);

    // Verify rewards
    expect(state.inventory.items.length, 1);
    expect(state.inventory.items.first.name, 'Normal Logs');
    expect(state.inventory.items.first.count, 1);

    // Verify XP
    expect(state.skillState(normalTree.skill).xp, normalTree.xp);
  });
}
