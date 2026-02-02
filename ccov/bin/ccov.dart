// ignore_for_file: avoid_print

import 'package:args/args.dart';
import 'package:ccov/codecov_api.dart';

void printUsage(ArgParser parser) {
  print('Usage: ccov <command> [options]');
  print('');
  print('Commands:');
  print('  misses   List files by uncovered lines (default)');
  print('  summary  Show repo-level coverage totals');
  print('');
  print('Options:');
  print(parser.usage);
}

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Show this help.')
    ..addOption(
      'limit',
      abbr: 'n',
      defaultsTo: '20',
      help: 'Max files to show.',
    )
    ..addOption('exclude', help: 'Exclude files matching this substring.')
    ..addOption(
      'path',
      abbr: 'p',
      help: 'Only show files starting with this prefix.',
    );

  final ArgResults results;
  try {
    results = parser.parse(arguments);
  } on FormatException catch (e) {
    print(e.message);
    printUsage(parser);
    return;
  }

  if (results.flag('help')) {
    printUsage(parser);
    return;
  }

  final command = results.rest.isEmpty ? 'misses' : results.rest.first;
  final api = CodecovApi();

  try {
    switch (command) {
      case 'summary':
        await runSummary(api);
      case 'misses':
        await runMisses(
          api,
          limit: int.parse(results.option('limit')!),
          exclude: results.option('exclude'),
          pathPrefix: results.option('path'),
        );
      default:
        print('Unknown command: $command');
        printUsage(parser);
    }
  } finally {
    api.close();
  }
}

Future<void> runSummary(CodecovApi api) async {
  final data = await api.fetchSummary();
  final t = data['totals'] as Map<String, dynamic>;
  print('Files:    ${t['files']}');
  print('Lines:    ${t['lines']}');
  print('Hits:     ${t['hits']}');
  print('Misses:   ${t['misses']}');
  print('Coverage: ${t['coverage']}%');
}

Future<void> runMisses(
  CodecovApi api, {
  required int limit,
  String? exclude,
  String? pathPrefix,
}) async {
  final data = await api.fetchReport();
  var files = (data['files'] as List).cast<Map<String, dynamic>>();

  if (exclude != null) {
    files = files
        .where((f) => !(f['name'] as String).contains(exclude))
        .toList();
  }
  if (pathPrefix != null) {
    files = files
        .where((f) => (f['name'] as String).startsWith(pathPrefix))
        .toList();
  }

  files.sort((a, b) {
    final am = (a['totals'] as Map<String, dynamic>)['misses'] as int;
    final bm = (b['totals'] as Map<String, dynamic>)['misses'] as int;
    return bm.compareTo(am);
  });

  if (files.length > limit) {
    files = files.sublist(0, limit);
  }

  // Header.
  print(
    '${'Misses'.padLeft(6)}  ${'Lines'.padLeft(6)}  '
    '${'Cov%'.padLeft(6)}  File',
  );
  print(
    '${'------'.padLeft(6)}  ${'-----'.padLeft(6)}  '
    '${'----'.padLeft(6)}  ----',
  );

  for (final f in files) {
    final t = f['totals'] as Map<String, dynamic>;
    final misses = t['misses'] as int;
    final lines = t['lines'] as int;
    final cov = t['coverage'];
    final name = f['name'] as String;
    print(
      '${misses.toString().padLeft(6)}  ${lines.toString().padLeft(6)}  '
      '${cov.toString().padLeft(6)}  $name',
    );
  }
}
