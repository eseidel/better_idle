import 'package:flutter/material.dart';
import 'package:logic/logic.dart';
import 'package:ui/src/logic/redux_actions.dart';
import 'package:ui/src/widgets/cached_image.dart';
import 'package:ui/src/widgets/game_scaffold.dart';
import 'package:ui/src/widgets/style.dart';

class PetsLogPage extends StatelessWidget {
  const PetsLogPage({super.key});

  @override
  Widget build(BuildContext context) {
    return GameScaffold(
      title: const Text('Pets'),
      body: StoreConnector<GlobalState, _PetsLogViewModel>(
        converter: (store) => _PetsLogViewModel(store.state),
        builder: (context, viewModel) {
          return Column(
            children: [
              _CompletionHeader(
                found: viewModel.foundCount,
                total: viewModel.totalCount,
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(12),
                  child: Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      for (final pet in viewModel.allPets)
                        _PetCell(pet: pet, found: viewModel.isPetFound(pet.id)),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _PetsLogViewModel {
  _PetsLogViewModel(this._state);

  final GlobalState _state;

  List<Pet> get allPets => _state.registries.pets.pets;

  List<Pet> get _completionPets =>
      allPets.where((p) => !p.ignoreCompletion).toList();

  int get foundCount =>
      _completionPets.where((p) => _state.unlockedPets.contains(p.id)).length;

  int get totalCount => _completionPets.length;

  bool isPetFound(MelvorId id) => _state.unlockedPets.contains(id);
}

class _CompletionHeader extends StatelessWidget {
  const _CompletionHeader({required this.found, required this.total});

  final int found;
  final int total;

  @override
  Widget build(BuildContext context) {
    final percent = total > 0 ? (found / total * 100).toStringAsFixed(0) : '0';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: Style.categoryHeaderColor,
      child: Text(
        'Pets Found: $found / $total ($percent%)',
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
      ),
    );
  }
}

class _PetCell extends StatelessWidget {
  const _PetCell({required this.pet, required this.found});

  final Pet pet;
  final bool found;

  static const double _size = 48;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: found ? pet.name : '???',
      child: Container(
        width: _size,
        height: _size,
        decoration: BoxDecoration(
          color: Style.cellBackgroundColor,
          borderRadius: BorderRadius.circular(4),
        ),
        child: found
            ? CachedImage(assetPath: pet.media, size: _size)
            : const Center(
                child: Icon(
                  Icons.help_outline,
                  size: _size * 0.6,
                  color: Style.iconColorDefault,
                ),
              ),
      ),
    );
  }
}
