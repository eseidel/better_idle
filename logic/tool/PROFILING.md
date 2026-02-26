# Resume Profiling Tools

Tools for benchmarking and profiling the tick resume path. Run from `logic/`.

## Benchmark

Measure how long a 24h resume takes (defaults to woodcutting "Normal Tree"):

```sh
dart run tool/benchmark_resume.dart [action_name]
```

## CPU Profile

Capture a Dart VM CPU profile and analyze hot spots:

```sh
dart --observe run tool/benchmark_resume.dart --profile
dart run tool/analyze_profile.dart cpu_profile.json
```

The analyzer prints top functions by inclusive (time in call tree) and
exclusive (self time) sample counts, filtered to `package:logic`.
