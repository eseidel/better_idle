import 'package:better_idle/src/state.dart';
import 'package:flutter/widgets.dart';

extension BuildContextExtension on BuildContext {
  GlobalState get state => getState<GlobalState>();
}
