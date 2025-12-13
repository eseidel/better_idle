import 'package:async_redux/async_redux.dart';
import 'package:flutter/widgets.dart';
import 'package:logic/logic.dart';

extension BuildContextExtension on BuildContext {
  GlobalState get state => getState<GlobalState>();
}
