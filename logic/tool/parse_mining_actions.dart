import 'package:logic/src/data/actions.dart';
import 'package:logic/src/data/melvor_data.dart';
import 'package:logic/src/data/melvor_id.dart';

/// Parses a Melvor category ID to determine the RockType.
RockType parseRockType(String? category) {
  if (category == 'melvorD:Essence') {
    return RockType.essence;
  }
  return RockType.ore;
}

/// Parses a Melvor item ID like "melvorD:Copper_Ore" to extract the name.
String parseProductName(String productId, RockType rockType) {
  final colonIndex = productId.indexOf(':');
  final rawName = colonIndex == -1
      ? productId
      : productId.substring(colonIndex + 1);
  return rawName.replaceAll('_', ' ');
}

/// Creates a MiningAction from Melvor rock data.
MiningAction parseMiningAction(Map<String, dynamic> rock) {
  final id = rock['id'] as String;
  final name = rock['name'] as String;
  final level = rock['level'] as int;
  final xp = rock['baseExperience'] as int;
  final respawnMs = rock['baseRespawnInterval'] as int;
  final quantity = rock['baseQuantity'] as int? ?? 1;
  final category = rock['category'] as String?;
  final productId = rock['productId'] as String;

  final rockType = parseRockType(category);
  final productName = parseProductName(productId, rockType);

  return MiningAction(
    id: id,
    name: name,
    unlockLevel: level,
    xp: xp,
    outputs: {MelvorId.fromName(productName): quantity},
    respawnSeconds: respawnMs ~/ 1000,
    rockType: rockType,
  );
}

Future<void> main() async {
  final melvorData = await MelvorData.load();
  final miningData = melvorData.lookupSkillData('melvorD:Mining');

  if (miningData == null) {
    print('Mining skill data not found');
    return;
  }

  final rocks = miningData['rockData'] as List<dynamic>? ?? [];
  print('Parsed ${rocks.length} mining actions:\n');

  for (final rock in rocks) {
    final action = parseMiningAction(rock as Map<String, dynamic>);
    print(action.name);
    print('  Level: ${action.unlockLevel}');
    print('  XP: ${action.xp}');
    print('  Outputs: ${action.outputs}');
    print('  Respawn: ${action.respawnTime.inSeconds}s');
    print('  Rock Type: ${action.rockType}');
    print('');
  }
}
