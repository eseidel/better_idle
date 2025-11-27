// ignore_for_file: avoid_print
import 'dart:io';

import 'package:collection/collection.dart';

void main() {
  final tableFile = File('xp_table.txt');
  final table = tableFile.readAsStringSync();
  final lines = table.split('\n');
  final levelToXp = <int, int>{};
  for (var line in lines) {
    final parts = line.split(RegExp(r'\s+'));
    if (parts.length % 3 != 0) {
      throw Exception('Invalid line: $line');
    }
    final groups = parts.slices(3);
    for (var group in groups) {
      final level = int.parse(group[0]);
      final xp = int.parse(group[1].replaceAll(',', ''));
      levelToXp[level] = xp;
    }
  }
  final topLevel = levelToXp.keys.max;
  // for (var level = 1; level <= topLevel; level++) {
  //   final xp = levelToXp[level] as int;
  //   final previousXp = level > 1 ? levelToXp[level - 1] as int : 0;
  //   final xpFromPreviousLevel = xp - previousXp;
  //   print('$level: $xp, $xpFromPreviousLevel');
  // }

  print("final xpTable = <int>[");
  for (var level = 1; level <= topLevel; level++) {
    final xp = levelToXp[level] as int;
    print(' $xp,');
  }
  print('];');
}
