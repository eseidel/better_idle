import 'package:flutter_test/flutter_test.dart';
import 'package:logic/logic.dart';

void main() {
  test('consumeTicks completes activity and adds toast', () {
    final normalTree = actionRegistry.byName('Normal Tree') as SkillAction;
    var state = GlobalState.empty();

    // Start activity
    state = state.startAction(normalTree);

    // Advance time by 3 seconds (30 ticks)
    // consumeTicks takes state and ticks
    // 3s = 3000ms. tickDuration = 100ms. So 30 ticks.
    final builder = StateUpdateBuilder(state);
    consumeTicks(builder, 30);
    state = builder.build();

    // Verify activity completed (progress resets on completion)
    expect(state.activeAction?.progressTicks, 0);

    // Verify rewards
    final items = state.inventory.items;
    expect(items.length, 1);
    expect(items.first.item.name, 'Normal Logs');
    expect(items.first.count, 1);

    // Verify XP
    expect(state.skillState(normalTree.skill).xp, normalTree.xp);
  });
}
