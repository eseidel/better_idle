import 'package:flutter/material.dart';
import 'package:scoped_deps/scoped_deps.dart';

import 'src/game_loop.dart';
import 'src/logger.dart';
import 'src/router.dart';
import 'src/state.dart';

void main() {
  runScoped(() => runApp(const MyApp()), values: {loggerRef});
}

final store = Store<GlobalState>(initialState: GlobalState.empty());

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
      child: StoreConnector<GlobalState, Activity?>(
        converter: (store) => store.state.currentActivity,
        builder: (context, currentActivity) {
          return MaterialApp.router(routerConfig: router);
        },
      ),
    );
  }
}
