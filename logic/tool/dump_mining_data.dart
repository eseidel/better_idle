import 'package:logic/src/data/melvor_data.dart';

Future<void> main() async {
  final melvorData = await MelvorData.load();
  final miningData = melvorData.lookupSkillData('melvorD:Mining');

  if (miningData == null) {
    print('Mining skill data not found');
    return;
  }

  final rocks = miningData['rockData'] as List<dynamic>? ?? [];
  print('Found ${rocks.length} rocks\n');

  // Print all rocks
  for (final rock in rocks) {
    final r = rock as Map<String, dynamic>;
    print(
      '${r['name']} (level ${r['level']}, ${r['baseExperience']}xp, '
      'respawn ${r['baseRespawnInterval']}ms, qty ${r['baseQuantity']}, '
      'category ${r['category']})',
    );
  }
}
