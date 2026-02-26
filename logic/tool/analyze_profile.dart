// Analyzes Dart VM CPU profile JSON files.
//
// Usage: dart run tool/analyze_profile.dart [path/to/cpu_profile.json]
//
// Parses CpuSamples format and prints top functions by inclusive and
// exclusive sample counts, focusing on package:logic functions.
// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

void main(List<String> args) {
  final path = args.isNotEmpty ? args[0] : 'cpu_profile.json';
  final file = File(path);
  if (!file.existsSync()) {
    stderr.writeln('File not found: $path');
    exit(1);
  }

  final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;

  final functions = json['functions'] as List<dynamic>;
  final samples = json['samples'] as List<dynamic>;
  final sampleCount = json['sampleCount'] as int;
  final timeExtentMicros = json['timeExtentMicros'] as int;

  // Extract function names and resolved URLs.
  final functionNames = <int, String>{};
  final functionUrls = <int, String>{};
  for (var i = 0; i < functions.length; i++) {
    final fn = functions[i] as Map<String, dynamic>;
    final fnInfo = fn['function'] as Map<String, dynamic>;
    functionNames[i] = fnInfo['name'] as String;
    functionUrls[i] = (fn['resolvedUrl'] as String?) ?? '';
  }

  // Count inclusive and exclusive samples.
  final inclusiveCounts = <int, int>{};
  final exclusiveCounts = <int, int>{};

  for (final sample in samples) {
    final stack = (sample as Map<String, dynamic>)['stack'] as List<dynamic>;
    if (stack.isEmpty) continue;

    // Index 0 is the leaf (top of stack) = exclusive/self time.
    final leaf = stack[0] as int;
    exclusiveCounts[leaf] = (exclusiveCounts[leaf] ?? 0) + 1;

    // Every function in the stack gets an inclusive count, but only once
    // per sample (use a set to deduplicate).
    final seen = <int>{};
    for (final idx in stack) {
      final fnIdx = idx as int;
      if (seen.add(fnIdx)) {
        inclusiveCounts[fnIdx] = (inclusiveCounts[fnIdx] ?? 0) + 1;
      }
    }
  }

  final durationSec = timeExtentMicros / 1e6;

  print('CPU Profile Summary');
  print('=' * 100);
  print('Total samples: $sampleCount');
  print('Duration: ${durationSec.toStringAsFixed(3)}s');
  print('Sample period: ${json['samplePeriod']}us');
  print('');

  // Match package:logic by looking for /logic/lib/ in the resolved URL,
  // since the Dart VM uses file:// paths rather than package: URIs.
  bool isPackageLogic(int idx) {
    final url = functionUrls[idx]!;
    return url.contains('/logic/lib/') || url.contains('/logic/tool/');
  }

  String shortUrl(String url) {
    // Shorten to just the path after logic/.
    final match = RegExp(r'logic/(.+)$').firstMatch(url);
    if (match != null) return 'logic/${match.group(1)}';
    // For dart SDK, shorten.
    final sdkMatch = RegExp(r'sdk:///sdk/lib/(.+)$').firstMatch(url);
    if (sdkMatch != null) return 'dart:${sdkMatch.group(1)}';
    // For pub packages.
    final pubMatch = RegExp(r'pub\.dev/([^/]+)/lib/(.+)$').firstMatch(url);
    if (pubMatch != null) return '${pubMatch.group(1)}/${pubMatch.group(2)}';
    if (url.length > 60) return '...${url.substring(url.length - 57)}';
    return url;
  }

  String formatEntry(int idx, int count, {int nameWidth = 55}) {
    final pct = (count / sampleCount * 100).toStringAsFixed(1);
    final name = functionNames[idx]!;
    final url = functionUrls[idx]!;
    final displayName = name.length > nameWidth
        ? '${name.substring(0, nameWidth - 3)}...'
        : name.padRight(nameWidth);
    return '${pct.padLeft(6)}%  ${count.toString().padLeft(5)}  '
        '$displayName  ${shortUrl(url)}';
  }

  // --- package:logic inclusive ---
  print('Top 30 by INCLUSIVE samples (package:logic only)');
  print('-' * 100);
  final logicInclusive =
      inclusiveCounts.entries.where((e) => isPackageLogic(e.key)).toList()
        ..sort((a, b) => b.value.compareTo(a.value));
  for (var i = 0; i < logicInclusive.length && i < 30; i++) {
    final e = logicInclusive[i];
    print(formatEntry(e.key, e.value));
  }
  print('');

  // --- package:logic exclusive ---
  print('Top 30 by EXCLUSIVE samples (package:logic only)');
  print('-' * 100);
  final logicExclusive =
      exclusiveCounts.entries.where((e) => isPackageLogic(e.key)).toList()
        ..sort((a, b) => b.value.compareTo(a.value));
  for (var i = 0; i < logicExclusive.length && i < 30; i++) {
    final e = logicExclusive[i];
    print(formatEntry(e.key, e.value));
  }
  print('');

  // --- All functions inclusive (including dart:*) ---
  print('Top 30 by INCLUSIVE samples (ALL)');
  print('-' * 100);
  final allInclusive = inclusiveCounts.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  for (var i = 0; i < allInclusive.length && i < 30; i++) {
    final e = allInclusive[i];
    print(formatEntry(e.key, e.value));
  }
  print('');

  // --- All functions exclusive (including dart:*) ---
  print('Top 30 by EXCLUSIVE samples (ALL)');
  print('-' * 100);
  final allExclusive = exclusiveCounts.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  for (var i = 0; i < allExclusive.length && i < 30; i++) {
    final e = allExclusive[i];
    print(formatEntry(e.key, e.value));
  }
}
