import 'dart:async';

import 'package:logic/logic.dart';
import 'package:scoped_deps/scoped_deps.dart';

class ToastService {
  final _toastController = StreamController<Changes>.broadcast();
  Stream<Changes> get toastStream => _toastController.stream;

  final _errorController = StreamController<String>.broadcast();
  Stream<String> get errorStream => _errorController.stream;

  final _deathController = StreamController<Counts<MelvorId>>.broadcast();
  Stream<Counts<MelvorId>> get deathStream => _deathController.stream;

  final _petUnlockedController = StreamController<MelvorId>.broadcast();
  Stream<MelvorId> get petUnlockedStream => _petUnlockedController.stream;

  final _skillMilestoneController = StreamController<Skill>.broadcast();
  Stream<Skill> get skillMilestoneStream => _skillMilestoneController.stream;

  void showToast(Changes changes) {
    _toastController.add(changes);
  }

  void showError(String message) {
    _errorController.add(message);
  }

  void showDeath(Counts<MelvorId> lostOnDeath) {
    _deathController.add(lostOnDeath);
  }

  void showPetUnlocked(MelvorId petId) {
    _petUnlockedController.add(petId);
  }

  void showSkillMilestone(Skill skill) {
    _skillMilestoneController.add(skill);
  }
}

final ScopedRef<ToastService> toastServiceRef = create(ToastService.new);
ToastService get toastService => read(toastServiceRef);
