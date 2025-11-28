import 'package:flutter/material.dart';

import '../state.dart';

export 'package:async_redux/async_redux.dart';

extension BuildContextExtension on BuildContext {
  GlobalState get state => getState<GlobalState>();
}
