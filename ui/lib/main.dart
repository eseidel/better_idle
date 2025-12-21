import 'dart:async';

import 'package:async_redux/local_persist.dart';
import 'package:better_idle/src/logic/game_loop.dart';
import 'package:better_idle/src/logic/redux_actions.dart';
import 'package:better_idle/src/services/image_cache_service.dart';
import 'package:better_idle/src/services/logger.dart';
import 'package:better_idle/src/services/toast_service.dart';
import 'package:better_idle/src/widgets/router.dart';
import 'package:better_idle/src/widgets/toast_overlay.dart';
import 'package:better_idle/src/widgets/welcome_back_dialog.dart';
import 'package:flutter/material.dart';
import 'package:logic/logic.dart';
import 'package:scoped_deps/scoped_deps.dart';

void main() {
  runScoped(
    () => runApp(const MyApp()),
    values: {loggerRef, toastServiceRef, imageCacheServiceRef},
  );
}

class MyPersistor extends Persistor<GlobalState> {
  MyPersistor(this.registries);

  final Registries registries;

  final LocalPersist _persist = LocalPersist('better_idle');
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
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        // Pause game loop
        widget.gameLoop.pause();
        widget.store.dispatch(
          ProcessLifecycleChangeAction(LifecycleChange.pause),
        );
      case AppLifecycleState.resumed:
        // Calculate time away and process it
        widget.store.dispatch(ResumeFromPauseAction());
        // Resume game loop if activity is active
        Future.microtask(() {
          final state = widget.store.state;
          if (state.isActive) {
            widget.gameLoop.start();
          }
          _checkAndShowDialog();
        });
        widget.store.dispatch(
          ProcessLifecycleChangeAction(LifecycleChange.resume),
        );
      case AppLifecycleState.inactive:
        // Just resume, don't process time away (app might be transitioning)
        widget.store.dispatch(
          ProcessLifecycleChangeAction(LifecycleChange.resume),
        );
      case AppLifecycleState.hidden:
      // ignored for now.
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

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    await loadRegistries();
    await imageCacheService.initialize();
    setState(() {
      _isDataLoaded = true;
    });
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
    return const _GameApp();
  }
}

class _GameApp extends StatefulWidget {
  const _GameApp();

  @override
  State<_GameApp> createState() => _GameAppState();
}

class _GameAppState extends State<_GameApp>
    with SingleTickerProviderStateMixin {
  late final Registries registries;
  late final MyPersistor _persistor;
  bool _isInitialized = false;
  late final Store<GlobalState> _store;
  late final GameLoop _gameLoop;

  @override
  void initState() {
    super.initState();
    _persistor = MyPersistor(registries);
    _persistor.readState().then((initialState) {
      setState(() {
        _store = Store<GlobalState>(
          initialState: initialState,
          persistor: _persistor,
        );
        _gameLoop = GameLoop(this, _store);
        _gameLoop.updateInterval = const Duration(milliseconds: 100);
        _isInitialized = true;
      });
    });
  }

  @override
  void dispose() {
    _gameLoop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return const SizedBox.shrink();
    }
    return StoreProvider<GlobalState>(
      store: _store,
      child: _AppLifecycleManager(
        store: _store,
        gameLoop: _gameLoop,
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
    );
  }
}
