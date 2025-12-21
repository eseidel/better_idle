import 'package:logic/src/data/melvor_data.dart';

Future<void> main() async {
  final melvorData = await MelvorData.load();

  print('Found ${melvorData.skillCount} skills:\n');

  for (final skillId in melvorData.skillIds) {
    final skillData = melvorData.lookupSkillData(skillId)!;
    final keys = skillData.keys.toList();

    print(skillId);
    print('  Keys: ${keys.join(', ')}');
    print('');
  }
}
