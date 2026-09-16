// Prints a save-state JSON with farming plots mid-growth and ready to harvest.
//
// The UI package has no widget-test harness, so farming UI changes are checked
// by driving the real app. Pipe this into the web build's localStorage key
// `game_persist_melvor_slot_0` to land on a farming screen with something to
// look at:
//
//     dart run tool/debug_farming_save.dart > save.json
import 'dart:convert';
import 'dart:io';

import 'package:logic/logic.dart';
import 'package:logic/src/data/registries_io.dart';

Future<void> main() async {
  final registries = await loadRegistries();
  var state = GlobalState.empty(registries).copyWith(
    skillStates: {
      Skill.farming: const SkillState(xp: 500000, masteryPoolXp: 1500000),
    },
  );

  final allotment = registries.farming.categories.firstWhere(
    (c) => c.name == 'Allotments',
  );
  final crops = registries.farming.cropsForCategory(allotment.id).toList()
    ..sort((a, b) => a.unlockLevel.compareTo(b.unlockLevel));
  final crop = crops.first;

  // Stock seeds so the planting dialogs have something to list.
  for (final c in crops.take(4)) {
    state = state.copyWith(
      inventory: state.inventory.adding(
        ItemStack(registries.items.byId(c.seedId), count: 200),
      ),
    );
  }

  // Give the crop some mastery so the progress bars are not all empty.
  state = state.addActionMasteryXp(crop.id, 400000);

  // One plot mid-growth; the rest ready to harvest so Harvest All has work.
  final plots = registries.farming.plotsForCategory(allotment.id).toList();
  state = state
      .copyWith(
        plotStates: {
          plots[0].id: PlotState(cropId: crop.id, growthTicksRemaining: 40000),
          for (final plot in plots.skip(1))
            plot.id: PlotState(cropId: crop.id, growthTicksRemaining: 0),
        },
        unlockedPlots: {...state.unlockedPlots, ...plots.map((p) => p.id)},
      )
      .addCurrency(Currency.gp, 100000);

  stdout.write(jsonEncode(state.toJson()));
}
