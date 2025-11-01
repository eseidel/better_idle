import 'package:async_redux/local_persist.dart';
import 'package:flutter/material.dart';
import 'package:scoped_deps/scoped_deps.dart';

import 'src/game_loop.dart';
import 'src/logger.dart';
import 'src/router.dart';
import 'src/state.dart';

void main() {
  runScoped(() => runApp(const MyApp()), values: {loggerRef});
}

class MyPersistor extends Persistor<GlobalState> {
  final LocalPersist _persist = LocalPersist("better_idle");
  @override
  Future<GlobalState> readState() async {
    final state = await _persist.loadAsObj();
    print('readState: $state');
    return state == null ? GlobalState.empty() : GlobalState.fromJson(state);
  }

  @override
  Future<void> persistDifference({
    required GlobalState? lastPersistedState,
    required GlobalState newState,
  }) async {
    print('persistDifference: $lastPersistedState -> $newState');
    await _persist.saveJson(newState);
  }

  @override
  Future<void> deleteState() async {
    await _persist.delete();
  }
}

final store = Store<GlobalState>(
  initialState: GlobalState.empty(),
  persistor: MyPersistor(),
);

class _AppLifecycleManager extends StatefulWidget {
  final Widget child;
  const _AppLifecycleManager({required this.child});
  @override
  _AppLifecycleManagerState createState() => _AppLifecycleManagerState();
}

class _AppLifecycleManagerState extends State<_AppLifecycleManager>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    print('didChangeAppLifecycleState: $lifecycle');
    switch (lifecycle) {
      case AppLifecycleState.resumed:
      case AppLifecycleState.inactive:
        store.dispatch(ProcessLifecycleChangeAction(LifecycleChange.resume));
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        store.dispatch(ProcessLifecycleChangeAction(LifecycleChange.pause));
        break;
      default:
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

enum LifecycleChange { resume, pause }

class ProcessLifecycleChangeAction extends ReduxAction<GlobalState> {
  final LifecycleChange lifecycle;
  ProcessLifecycleChangeAction(this.lifecycle);

  @override
  Future<GlobalState?> reduce() async {
    switch (lifecycle) {
      case LifecycleChange.resume:
        store.resumePersistor();
        break;
      case LifecycleChange.pause:
        store.persistAndPausePersistor();
        break;
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

class _MyAppState extends State<MyApp> with SingleTickerProviderStateMixin {
  late final GameLoop _gameLoop;

  @override
  void initState() {
    super.initState();
    _gameLoop = GameLoop(this, store);
    _gameLoop.updateInterval = const Duration(milliseconds: 100);
  }

  @override
  void dispose() {
    _gameLoop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StoreProvider<GlobalState>(
      store: store,
      child: _AppLifecycleManager(
        child: StoreConnector<GlobalState, ActivityView?>(
          converter: (store) => store.state.currentActivity,
          builder: (context, currentActivity) {
            return MaterialApp.router(routerConfig: router);
          },
        ),
      ),
    );
  }
}
