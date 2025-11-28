import 'dart:async';

import 'package:scoped_deps/scoped_deps.dart';

import '../logic/consume_ticks.dart';

class ToastService {
  final _toastController = StreamController<Changes>.broadcast();
  Stream<Changes> get toastStream => _toastController.stream;

  void showToast(Changes changes) {
    _toastController.add(changes);
  }
}

final toastServiceRef = create(ToastService.new);
ToastService get toastService => read(toastServiceRef);
