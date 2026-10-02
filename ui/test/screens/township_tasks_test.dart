import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logic/file_cache.dart';
import 'package:logic/logic.dart';
import 'package:logic/testing.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:ui/src/logic/redux_actions.dart';
import 'package:ui/src/screens/township.dart';
import 'package:ui/src/services/game_persist.dart';
import 'package:ui/src/services/image_cache_service.dart';
import 'package:ui/src/services/logger.dart';
import 'package:ui/src/services/toast_service.dart';
import 'package:ui/src/services/ui_preferences.dart';

/// In-memory [GamePersist] standing in for disk or localStorage.
class _FakePersist implements GamePersist {
  Object? saved;

  @override
  Future<Object?> loadJson() async => saved;

  @override
  Future<void> saveJson(Object? json) async => saved = json;

  @override
  Future<void> delete() async => saved = null;
}

/// Serves no images, so icons show their fallback without touching the
/// asset cache.
class _NoImages extends ImageCacheService {
  _NoImages() : super(FileCache.offline(cacheDir: Directory('.cache')));

  @override
  File? getCachedFile(String assetPath) => null;

  @override
  Future<File?> ensureAsset(String assetPath) async => null;
}

const _logsTaskId = MelvorId('melvorF:CasualTask0');
const _golbinTaskId = MelvorId('melvorF:CasualTask121');

void main() {
  late Registries registries;
  final imageCache = _NoImages();

  setUpAll(() async {
    registries = await loadCachedRegistries(cacheDir: Directory('.cache'));
  });

  GlobalState townState({int gp = 1000}) => GlobalState.test(
    registries,
    currencies: {Currency.gp: gp},
    township: TownshipState(
      registry: registries.township,
      worshipId: registries.township.deities.first.id,
      activeCasualTasks: const [_logsTaskId, _golbinTaskId],
      casualTaskTicksRemaining: ticksPerHour * 2,
    ),
  );

  Future<Store<GlobalState>> pumpTasksTab(
    WidgetTester tester,
    GlobalState state,
  ) async {
    // Tall enough that the main task sort header is built.
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = Store<GlobalState>(initialState: state);
    await tester.pumpWidget(
      StoreProvider<GlobalState>(
        store: store,
        child: ImageCacheServiceProvider(
          service: imageCache,
          child: const MaterialApp(home: TownshipPage()),
        ),
      ),
    );
    await tester.tap(find.text('Tasks'));
    await tester.pumpAndSettle();
    return store;
  }

  testWidgets('shows assigned casual tasks and when the next arrives', (
    tester,
  ) async {
    await runScoped(() async {
      await pumpTasksTab(tester, townState());
      expect(find.text('Casual Tasks (2 / 5)'), findsOneWidget);
      expect(find.text('Next task in 2h'), findsOneWidget);
      expect(find.text('Casual Task'), findsNWidgets(2));
      expect(find.text('Skip'), findsNWidgets(2));
    }, values: {uiPreferencesRef, toastServiceRef, loggerRef});
  });

  testWidgets('skipping a casual task asks first, then removes it', (
    tester,
  ) async {
    await runScoped(() async {
      final store = await pumpTasksTab(tester, townState());
      await tester.tap(find.text('Skip').first);
      await tester.pumpAndSettle();
      expect(find.text('Skip this task?'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'Skip'));
      await tester.pumpAndSettle();
      expect(store.state.township.activeCasualTasks, [_golbinTaskId]);
      expect(store.state.gp, 1000 - 83);
      expect(find.text('Casual Tasks (1 / 5)'), findsOneWidget);
    }, values: {uiPreferencesRef, toastServiceRef, loggerRef});
  });

  testWidgets('cannot skip without enough GP', (tester) async {
    await runScoped(() async {
      await pumpTasksTab(tester, townState(gp: 0));
      final skip = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Skip').first,
      );
      expect(skip.onPressed, isNull);
    }, values: {uiPreferencesRef, toastServiceRef, loggerRef});
  });

  testWidgets('remembers the task sort after leaving the page', (tester) async {
    final preferences = UiPreferences(persist: _FakePersist());
    await runScoped(
      () async {
        await pumpTasksTab(tester, townState());
        expect(find.text('Difficulty'), findsOneWidget);

        await tester.tap(find.text('Difficulty'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Completion').last);
        await tester.pumpAndSettle();
        expect(find.text('Completion'), findsOneWidget);

        // Leave the page, then come back.
        await tester.pumpWidget(const SizedBox());
        await pumpTasksTab(tester, townState());
        expect(find.text('Completion'), findsOneWidget);
        expect(find.text('Difficulty'), findsNothing);
      },
      values: {
        uiPreferencesRef.overrideWith(() => preferences),
        toastServiceRef,
        loggerRef,
      },
    );
  });
}
