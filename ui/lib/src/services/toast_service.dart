import 'dart:async';

import 'package:logic/logic.dart';
import 'package:scoped_deps/scoped_deps.dart';

class ToastService {
  final _toastController = StreamController<Changes>.broadcast();
  Stream<Changes> get toastStream => _toastController.stream;

  final _errorController = StreamController<String>.broadcast();
  Stream<String> get errorStream => _errorController.stream;

  void showToast(Changes changes) {
    _toastController.add(changes);
  }

  void showError(String message) {
    _errorController.add(message);
  }
}

final ScopedRef<ToastService> toastServiceRef = create(ToastService.new);
ToastService get toastService => read(toastServiceRef);
