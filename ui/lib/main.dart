import 'dart:async';

import 'package:async_redux/local_persist.dart';
import 'package:flutter/material.dart';
import 'package:logic/logic.dart';
import 'package:path_provider/path_provider.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:ui/src/logic/game_loop.dart';
import 'package:ui/src/logic/redux_actions.dart';
import 'package:ui/src/services/image_cache_service.dart';
import 'package:ui/src/services/logger.dart';
import 'package:ui/src/services/save_slot_service.dart';
import 'package:ui/src/services/toast_service.dart';
import 'package:ui/src/widgets/router.dart';
import 'package:ui/src/widgets/toast_overlay.dart';
import 'package:ui/src/widgets/welcome_back_dialog.dart';

void main() {
  runScoped(() => runApp(const MyApp()), values: {loggerRef, toastServiceRef});
}

class MyPersistor extends Persistor<GlobalState> {
  MyPersistor(this.registries, {required this.activeSlot});

  final Registries registries;
  final int activeSlot;

  LocalPersist get _persist => LocalPersist('better_idle_slot_$activeSlot');

  @override
  Future<GlobalState> readState() async {
    try {
      final json = await _persist.loadJson() as Map<String, dynamic>?;
      if (json == null) {
        return GlobalState.empty(registries);
      }
      final state = GlobalState.fromJson(registries, json);
      if (!state.validate()) {
        logger.err('Invalid state.');
        return GlobalState.empty(registries);
      }
      return state;
    } on Object catch (e, stackTrace) {
      logger.err('Failed to load state: $e, stackTrace: $stackTrace');
      return GlobalState.empty(registries);
    }
  }

  @override
  Future<void> persistDifference({
    required GlobalState? lastPersistedState,
    required GlobalState newState,
  }) async {
    await _persist.saveJson(newState);

    // Update slot metadata with last played time
    final meta = await SaveSlotService.loadMeta();
    final newSlots = Map<int, SlotInfo>.from(meta.slots);
    newSlots[activeSlot] = SlotInfo(
      isEmpty: false,
      lastPlayed: DateTime.timestamp(),
    );
    await SaveSlotService.saveMeta(meta.copyWith(slots: newSlots));
  }

  @override
  Future<void> deleteState() async {
    await _persist.delete();
  }
}

class _AppLifecycleManager extends StatefulWidget {
  const _AppLifecycleManager({
    required this.child,
    required this.store,
    required this.gameLoop,
  });
  final Widget child;
  final Store<GlobalState> store;
  final GameLoop gameLoop;
  @override
  _AppLifecycleManagerState createState() => _AppLifecycleManagerState();
}

class _AppLifecycleManagerState extends State<_AppLifecycleManager>
    with WidgetsBindingObserver {
  bool _isDialogShowing = false;
  bool _wasTimeAwayNull = true; // Track if timeAway was null in previous state
  late final StreamSubscription<GlobalState> _storeSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Check if we should process time away on first launch (app restart)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final state = widget.store.state;
      _wasTimeAwayNull = state.timeAway == null;
      // If timeAway is null but we should show dialog (app restart),
      // process it first
      if (state.timeAway == null) {
        final timeSinceUpdate = DateTime.timestamp().difference(
          state.updatedAt,
        );
        // Only process if there was an active action and > 1s time passed
        if (state.isActive && timeSinceUpdate.inSeconds > 1) {
          widget.store.dispatch(ResumeFromPauseAction());
          // Check for dialog after action completes
          Future.microtask(_checkAndShowDialog);
        }
      } else {
        // timeAway already exists, check if we should show dialog
        _checkAndShowDialog();
      }
    });

    // Listen to store changes, but only show dialog when timeAway transitions
    // from null to non-null
    _storeSubscription = widget.store.onChange.listen((state) {
      if (mounted) {
        final currentTimeAway = state.timeAway;
        final isTimeAwayNull = currentTimeAway == null;

        // Only show dialog if timeAway transitioned from null to non-null
        if (_wasTimeAwayNull && !isTimeAwayNull) {
          _wasTimeAwayNull = false;
          // currentTimeAway is non-null here because !isTimeAwayNull
          if (!currentTimeAway.changes.isEmpty && !_isDialogShowing) {
            _checkAndShowDialog();
          }
        } else if (!_wasTimeAwayNull && isTimeAwayNull) {
          // timeAway cleared - reset flags
          _wasTimeAwayNull = true;
          if (_isDialogShowing) {
            _isDialogShowing = false;
          }
        }
        // If timeAway is non-null and was non-null before, it's just being
        // updated (accumulating changes) so don't show dialog again
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _storeSubscription.cancel();
    super.dispose();
  }

  void _checkAndShowDialog() {
    final state = widget.store.state;
    final timeAway = state.timeAway;

    // Show dialog if timeAway exists, has changes, and it's not already showing
    if (timeAway != null && !timeAway.changes.isEmpty && !_isDialogShowing) {
      _showDialogIfNeeded(timeAway);
    } else if (timeAway == null && _isDialogShowing) {
      // timeAway cleared - reset flag
      _isDialogShowing = false;
    }
  }

  void _showDialogIfNeeded(TimeAway timeAway) {
    // Don't show if already showing
    if (_isDialogShowing) {
      return;
    }

    final navigatorContext = navigatorKey.currentContext;
    if (navigatorContext == null) {
      // Navigator not ready yet, try again next frame
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_isDialogShowing) {
          _showDialogIfNeeded(timeAway);
        }
      });
      return;
    }

    // Check if Navigator already has a route (dialog might already be showing)
    final navigator = Navigator.maybeOf(navigatorContext);
    if (navigator == null) {
      return;
    }
    // If Navigator can pop, there's already a route (possibly our dialog)
    if (navigator.canPop()) {
      // Dialog or other route already showing
      _isDialogShowing = true;
      return;
    }

    _isDialogShowing = true;
    showDialog<void>(
      context: navigatorContext,
      builder: (context) => WelcomeBackDialog(timeAway: timeAway),
    ).then((_) {
      // Dialog dismissed - clear timeAway state and reset tracking
      widget.store.dispatch(DismissWelcomeBackDialogAction());
      if (mounted) {
        setState(() {
          _isDialogShowing = false;
        });
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    switch (lifecycle) {
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        // Suspend game loop - must handle hidden for iOS which sends
        // inactive → hidden → paused when backgrounding.
        // suspend() prevents auto-restart from state change listeners.
        widget.gameLoop.suspend();
        widget.store.dispatch(
          ProcessLifecycleChangeAction(LifecycleChange.pause),
        );
      case AppLifecycleState.resumed:
        // Calculate time away and process it
        widget.store.dispatch(ResumeFromPauseAction());
        // Resume game loop from suspension - this re-enables auto-start
        widget.gameLoop.resume();
        Future.microtask(_checkAndShowDialog);
        widget.store.dispatch(
          ProcessLifecycleChangeAction(LifecycleChange.resume),
        );
      case AppLifecycleState.inactive:
        // Just resume, don't process time away (app might be transitioning)
        widget.store.dispatch(
          ProcessLifecycleChangeAction(LifecycleChange.resume),
        );
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

enum LifecycleChange { resume, pause }

class ProcessLifecycleChangeAction extends ReduxAction<GlobalState> {
  ProcessLifecycleChangeAction(this.lifecycle);
  final LifecycleChange lifecycle;

  @override
  Future<GlobalState?> reduce() async {
    switch (lifecycle) {
      case LifecycleChange.resume:
        store.resumePersistor();
      case LifecycleChange.pause:
        store.persistAndPausePersistor();
    }
    return null;
  }
}

/// The main application widget.
class MyApp extends StatefulWidget {
  /// Constructs a [MyApp]
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  bool _isDataLoaded = false;
  late final ImageCacheService _imageCacheService;
  late final Registries _registries;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final cacheDir = await getApplicationCacheDirectory();
    final cache = Cache(cacheDir: cacheDir);
    _imageCacheService = ImageCacheService(cache);
    _registries = await loadRegistriesFromCache(cache);

    setState(() {
      _isDataLoaded = true;
    });
  }

  @override
  void dispose() {
    _imageCacheService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isDataLoaded) {
      return MaterialApp(
        themeMode: ThemeMode.dark,
        darkTheme: ThemeData.dark(),
        home: const Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }
    return ImageCacheServiceProvider(
      service: _imageCacheService,
      child: _GameApp(registries: _registries),
    );
  }
}

class _GameApp extends StatefulWidget {
  const _GameApp({required this.registries});

  final Registries registries;

  @override
  State<_GameApp> createState() => _GameAppState();
}

class _GameAppState extends State<_GameApp> {
  MyPersistor? _persistor;
  bool _isInitialized = false;
  Store<GlobalState>? _store;
  GameLoop? _gameLoop;
  int _activeSlot = 0;

  @override
  void initState() {
    super.initState();
    _initializeWithSlot();
  }

  Future<void> _initializeWithSlot() async {
    // Run migration first (only does work on first launch after update)
    await SaveSlotService.migrateIfNeeded();

    // Load meta to get active slot
    final meta = await SaveSlotService.loadMeta();
    _activeSlot = meta.activeSlot;

    _persistor = MyPersistor(widget.registries, activeSlot: _activeSlot);
    final initialState = await _persistor!.readState();

    setState(() {
      _store = Store<GlobalState>(
        initialState: initialState,
        persistor: _persistor,
      );
      _gameLoop = GameLoop(_store!);
      _isInitialized = true;
    });
  }

  /// Switch to a different save slot. This rebuilds the entire game state.
  Future<void> switchSlot(int newSlot) async {
    if (newSlot == _activeSlot) return;

    // Persist current state before switching
    _store?.persistAndPausePersistor();

    // Dispose current game loop
    _gameLoop?.dispose();

    setState(() {
      _isInitialized = false;
    });

    // Update meta with new active slot
    final meta = await SaveSlotService.loadMeta();
    await SaveSlotService.saveMeta(meta.copyWith(activeSlot: newSlot));

    _activeSlot = newSlot;
    _persistor = MyPersistor(widget.registries, activeSlot: newSlot);
    final newState = await _persistor!.readState();

    setState(() {
      _store = Store<GlobalState>(
        initialState: newState,
        persistor: _persistor,
      );
      _gameLoop = GameLoop(_store!);
      _isInitialized = true;
    });
  }

  /// Delete a save slot and reset it to empty state.
  Future<void> deleteSlot(int slot) async {
    await SaveSlotService.deleteSlot(slot);

    // If deleting the active slot, reset to empty state
    if (slot == _activeSlot) {
      _gameLoop?.dispose();
      setState(() {
        _isInitialized = false;
      });

      final newState = GlobalState.empty(widget.registries);
      _persistor = MyPersistor(widget.registries, activeSlot: _activeSlot);

      setState(() {
        _store = Store<GlobalState>(
          initialState: newState,
          persistor: _persistor,
        );
        _gameLoop = GameLoop(_store!);
        _isInitialized = true;
      });
    }
  }

  int get activeSlot => _activeSlot;

  @override
  void dispose() {
    _gameLoop?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return const SizedBox.shrink();
    }
    return SaveSlotManager(
      activeSlot: _activeSlot,
      switchSlot: switchSlot,
      deleteSlot: deleteSlot,
      child: StoreProvider<GlobalState>(
        store: _store!,
        child: _AppLifecycleManager(
          store: _store!,
          gameLoop: _gameLoop!,
          child: MaterialApp.router(
            routerConfig: router,
            themeMode: ThemeMode.dark,
            darkTheme: ThemeData.dark(),
            builder: (context, child) {
              return ToastOverlay(
                service: toastService,
                child: child ?? const SizedBox.shrink(),
              );
            },
          ),
        ),
      ),
    );
  }
}
