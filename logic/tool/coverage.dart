// This is a CLI tool that reports coverage to stdout.
// ignore_for_file: avoid_print

// Runs tests with coverage and reports a summary.
// Usage: dart run tool/coverage.dart [--check]
// --check: exit with non-zero status if coverage is below 90%.

import 'dart:io';

void main(List<String> args) {
  final check = args.contains('--check');
  const threshold = 90.0;

  final logicDir = _findLogicDir();

  // Run tests with coverage.
  final testResult = Process.runSync('dart', [
    'test',
    '--coverage=coverage',
  ], workingDirectory: logicDir);
  if (testResult.exitCode != 0) {
    stderr
      ..writeln('Tests failed:')
      ..writeln(testResult.stdout)
      ..writeln(testResult.stderr);
    exit(1);
  }

  // Format coverage to lcov.
  final formatResult = Process.runSync('dart', [
    'pub',
    'global',
    'run',
    'coverage:format_coverage',
    '--lcov',
    '--in=coverage',
    '--out=coverage/lcov.info',
    '--report-on=lib/',
  ], workingDirectory: logicDir);
  if (formatResult.exitCode != 0) {
    stderr
      ..writeln('Coverage formatting failed:')
      ..writeln(formatResult.stdout)
      ..writeln(formatResult.stderr);
    exit(1);
  }

  // Parse lcov.info and compute summary.
  final lcovFile = File('$logicDir/coverage/lcov.info');
  if (!lcovFile.existsSync()) {
    stderr.writeln('No coverage/lcov.info found.');
    exit(1);
  }

  final lines = lcovFile.readAsLinesSync();
  var totalHit = 0;
  var totalFound = 0;
  final fileStats = <String, (int hit, int found)>{};
  String? currentFile;
  var fileHit = 0;
  var fileFound = 0;

  for (final line in lines) {
    if (line.startsWith('SF:')) {
      currentFile = line.substring(3);
      // Make path relative to logic/lib/.
      final libIndex = currentFile.indexOf('lib/');
      if (libIndex >= 0) {
        currentFile = currentFile.substring(libIndex);
      }
      fileHit = 0;
      fileFound = 0;
    } else if (line.startsWith('DA:')) {
      final parts = line.substring(3).split(',');
      if (parts.length >= 2) {
        fileFound++;
        if (int.parse(parts[1]) > 0) {
          fileHit++;
        }
      }
    } else if (line == 'end_of_record') {
      if (currentFile != null) {
        fileStats[currentFile] = (fileHit, fileFound);
        totalHit += fileHit;
        totalFound += fileFound;
      }
      currentFile = null;
    }
  }

  final overallPct = totalFound > 0 ? (totalHit / totalFound * 100) : 100.0;

  // Print summary.
  print(
    'Coverage: ${overallPct.toStringAsFixed(1)}% '
    '($totalHit/$totalFound lines)',
  );

  // Print files below threshold.
  final below = <String, (int, int)>{};
  for (final entry in fileStats.entries) {
    final (hit, found) = entry.value;
    if (found > 0) {
      final pct = hit / found * 100;
      if (pct < threshold) {
        below[entry.key] = (hit, found);
      }
    }
  }

  if (below.isNotEmpty) {
    print('\nFiles below $threshold%:');
    final sorted = below.entries.toList()
      ..sort((a, b) {
        final pctA = a.value.$1 / a.value.$2;
        final pctB = b.value.$1 / b.value.$2;
        return pctA.compareTo(pctB);
      });
    for (final entry in sorted) {
      final (hit, found) = entry.value;
      final pct = (hit / found * 100).toStringAsFixed(1);
      print('  $pct% ${entry.key} ($hit/$found)');
    }
  }

  if (check && overallPct < threshold) {
    stderr.writeln(
      'Coverage ${overallPct.toStringAsFixed(1)}% is below $threshold%.',
    );
    exit(1);
  }
}

String _findLogicDir() {
  final dir = Directory.current;
  // If we're already in logic/, use that.
  if (File('${dir.path}/pubspec.yaml').existsSync()) {
    return dir.path;
  }
  // Try logic/ subdirectory.
  final logicDir = Directory('${dir.path}/logic');
  if (logicDir.existsSync()) {
    return logicDir.path;
  }
  stderr.writeln('Could not find logic directory.');
  exit(1);
}
