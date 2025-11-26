import 'package:better_idle/src/router.dart';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:scoped_deps/scoped_deps.dart';

export 'package:fluttertoast/fluttertoast.dart';

class ToastService {
  void showToast(String message) {
    final context = navigatorKey.currentContext;
    if (context == null) {
      // App likely not mounted or in background
      return;
    }
    final fToast = FToast().init(context);

    fToast.showToast(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(25.0),
          color: Colors.black87,
        ),
        child: Text(message, style: const TextStyle(color: Colors.white)),
      ),
      gravity: ToastGravity.BOTTOM,
      toastDuration: const Duration(seconds: 2),
    );
  }
}

final toastServiceRef = create(ToastService.new);
ToastService get toastService => read(toastServiceRef);
